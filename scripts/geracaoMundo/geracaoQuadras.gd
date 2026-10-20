extends Node3D

# =============================================================================
#  GERADOR DE QUADRAS
# =============================================================================
# Assim como as ruas, as quadras NAO sao malhas novas: elas alteram Global.tipos
# (tipo do bloco) e Global.mapa (altura) ANTES da malha do terreno ser gerada.
# Basta ter um tipo novo (com cor/textura propria) para diferenciar tudo.
#
# Tipos escritos por este script (indices iguais aos de terreno.gd):
#   6 = CALCADA  faixa ao longo das ruas
#   7 = QUADRA   chao do quarteirao/lote, onde os predios e casas podem ser criados
#   (4 = rua e 5 = ponte continuam sendo os de ruas.gd)
#
# Ordem de chamada (no main):
#   terreno.gerar_alturas()
#   ruas.gerar_ruas()
#   quadras.gerar_quadras()      <- este script
#   predios.gerar_predios()      <- usa quadras.lista_quadras / quadras.lista_lotes
#   await terreno.gerar_malha()
#
# Logica:
#   1) distancia de cada celula ate a rua mais proxima (BFS)
#   2) calcada = celulas livres a ate "largura_calcada" de uma rua
#      (herda a altura da rua vizinha, entao fica rente a ela)
#   3) quadras INTERNAS: os quarteiroes de ruas.quarteiroes. Se um beco corta o
#      quarteirao, ele e dividido em varias quadras retangulares
#   4) quadras EXTERNAS: faixas livres do lado de fora das ruas (contorno dos
#      distritos, anexos e ligacoes), cortadas em pedacos
#   5) VERIFICACAO de cada quadra: tamanho minimo, sem agua/rua, desnivel
#      aceitavel. As aprovadas sao niveladas (altura unica) e recebem o tipo 7
#   6) cada quadra e dividida em lotes (com a direcao da frente voltada p/ rua)
#
# -----------------------------------------------------------------------------
#  RECEITAS RAPIDAS
# -----------------------------------------------------------------------------
#  * Sem quadras do lado de fora das ruas ... quadras_externas = false
#  * Menos quadras externas ................. diminua chance_quadra_externa
#  * Calcada mais larga/estreita ............ largura_calcada
#  * Calcada mais alta que a rua (meio-fio) . elevacao_calcada = 1
#  * Manter o relevo original nas quadras ... nivelar_quadras = false
#  * Lotes maiores/menores .................. lote_min / lote_max
#
# TEXTURAS: o tipo 6 (calcada) e o 7 (quadra) usam o mesmo esquema do terreno.gd:
# basta colocar texturas nos indices 6 e 7 de "texturas_topo" / "texturas_lateral"
# do no Terreno (ou trocar as cores padrao em _cores_topo).
# =============================================================================

const T_AGUA := 0
const T_AREIA := 1
const T_GRAMA := 2
const T_PEDRA := 3
const T_RUA := 4
const T_PONTE := 5
const T_CALCADA := 6
const T_QUADRA := 7

const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const LADRILHO := 64   # tamanho do bloco de trabalho na busca de quadras externas

# -----------------------------------------------------------------------------
#  CONFIGURACOES
# -----------------------------------------------------------------------------
@export_group("Ligacao")
## Caminho do no de ruas (de onde vem a lista de quarteiroes internos).
@export var no_ruas: NodePath = ^"../Ruas"

@export_group("Calcadas")
## Largura da calcada ao longo das ruas (0 = sem calcada).
@export_range(0, 6) var largura_calcada := 2
## Quantos blocos a calcada fica acima da rua (0 = rente, 1 = meio-fio).
@export_range(0, 2) var elevacao_calcada := 0

@export_group("Quadras")
## Cria quadras nos quarteiroes entre as ruas (dentro dos distritos).
@export var quadras_internas := true
## Cria quadras tambem do lado de fora das ruas.
@export var quadras_externas := true
## Menor lado aceito para uma quadra (em blocos).
@export_range(3, 40) var quadra_min := 6
## Menor area aceita para uma quadra (em blocos).
@export var quadra_area_min := 48
## Desnivel maximo do terreno original dentro de uma quadra. Acima disso a quadra e rejeitada.
@export_range(0, 6) var desnivel_max_quadra := 3
## Aplana cada quadra numa altura unica (recomendado para predios).
@export var nivelar_quadras := true
## Quantos blocos o chao da quadra fica acima da calcada/rua vizinha.
@export_range(0, 2) var elevacao_quadra := 0
## Permite quadras sobre areia (perto de lagos).
@export var permitir_areia := false
## Distancia minima da agua para uma quadra EXTERNA.
@export_range(0, 12) var margem_agua := 3
## Distancia minima da borda do mapa.
@export_range(0, 20) var margem_mapa := 6

@export_group("Quadras externas")
## Espessura da faixa do lado de fora das ruas onde podem nascer quadras.
@export_range(4, 40) var profundidade_externa := 14
## Chance de cada pedaco de faixa virar quadra (o resto fica como terreno).
@export_range(0.0, 1.0, 0.01) var chance_quadra_externa := 0.75
## Comprimento maximo de uma quadra externa (faixas longas sao cortadas).
@export_range(10, 120) var comprimento_max_externa := 40

@export_group("Lotes")
## Divide cada quadra em lotes para predios e casas.
@export var gerar_lotes := true
## Menor lado de um lote.
@export_range(4, 40) var lote_min := 8
## Maior lado de um lote. Quadras maiores que isso sao divididas.
@export_range(6, 80) var lote_max := 16

@export_group("Depuracao")
@export var imprimir_relatorio := true

# -----------------------------------------------------------------------------
#  DADOS PUBLICOS (para o script de predios)
# -----------------------------------------------------------------------------
class Lote:
	var rect := Rect2i()          # celulas (x, z) do lote
	var altura := 0               # altura do chao (confiavel com nivelar_quadras ligado)
	var frente := Vector2i.ZERO   # lado voltado p/ rua/calcada: (1,0) (-1,0) (0,1) (0,-1); ZERO = interno, sem acesso

class Quadra:
	var rect := Rect2i()
	var externa := false          # false = entre ruas (dentro de distrito), true = fora das ruas
	var altura := 0
	var lotes: Array[Lote] = []

var lista_quadras: Array[Quadra] = []
var lista_lotes: Array[Lote] = []
var relatorio := ""

# -----------------------------------------------------------------------------
#  ESTADO INTERNO
# -----------------------------------------------------------------------------
var _rng := RandomNumberGenerator.new()
var _larg := 0
var _prof := 0
var _mapa := PackedInt32Array()
var _tipos := PackedByteArray()
var _livre := PackedByteArray()       # 1 = terreno natural disponivel para calcada/quadra
var _reservado := PackedByteArray()   # 1 = pertence a um quarteirao interno
var _ext := PackedByteArray()         # 1 = candidato a quadra externa
var _dist_rua := PackedByteArray()
var _dist_agua := PackedByteArray()
var _alt_rua := PackedInt32Array()    # altura da rua mais proxima

var _n_calcada := 0
var _n_internas := 0
var _n_externas := 0
var _n_rej_desnivel := 0
var _n_descartadas := 0


func gerar_quadras() -> void:
	if Global.mapa.is_empty():
		push_error("Quadras: chame terreno.gerar_alturas() e ruas.gerar_ruas() antes de gerar_quadras().")
		return

	_larg = Global.largura
	_prof = Global.profundidade
	_rng.seed = Global.seed + 104729

	_mapa = Global.mapa.duplicate()
	_tipos = Global.tipos.duplicate()
	lista_quadras.clear()
	lista_lotes.clear()
	_n_calcada = 0
	_n_internas = 0
	_n_externas = 0
	_n_rej_desnivel = 0
	_n_descartadas = 0

	_preparar_mascaras()
	_pintar_calcadas()
	_processar_internas()
	_processar_externas()

	Global.mapa = _mapa
	Global.tipos = _tipos

	var com_frente := 0
	for l in lista_lotes:
		if l.frente != Vector2i.ZERO:
			com_frente += 1
	relatorio = "Quadras: %d (%d internas, %d externas) | lotes: %d (%d com frente p/ rua) | rejeitadas por desnivel: %d | descartadas: %d | calcada: %d celulas" % [
		lista_quadras.size(), _n_internas, _n_externas, lista_lotes.size(), com_frente,
		_n_rej_desnivel, _n_descartadas, _n_calcada]
	if imprimir_relatorio:
		print(relatorio)
	if lista_quadras.is_empty():
		push_warning("Quadras: nenhuma quadra valida. Reduza quadra_min/desnivel ou gere mais ruas.")


# ---------------------------------------------------------------------------
# VERIFICACAO PUBLICA: o retangulo (em celulas) e todo quadra e esta no mesmo nivel?
# Use no script de predios antes de colocar uma construcao.
# ---------------------------------------------------------------------------
func area_construivel(r: Rect2i, exigir_plano: bool = true) -> bool:
	if r.size.x <= 0 or r.size.y <= 0:
		return false
	var h0 := Global.altura_em(r.position.x, r.position.y)
	for x in range(r.position.x, r.end.x):
		for z in range(r.position.y, r.end.y):
			if Global.tipo_em(x, z) != T_QUADRA:
				return false
			if exigir_plano and Global.altura_em(x, z) != h0:
				return false
	return true


# ---------------------------------------------------------------------------
# PRIMITIVAS
# ---------------------------------------------------------------------------
func _dentro(x: int, z: int, margem: int = 0) -> bool:
	return x >= margem and z >= margem and x < _larg - margem and z < _prof - margem


func _e_via(x: int, z: int) -> bool:
	if not _dentro(x, z):
		return false
	var t := _tipos[x * _prof + z]
	return t == T_RUA or t == T_CALCADA or t == T_PONTE


# Altura de rua/calcada na celula, ou -1 se nao for.
func _alt_via(x: int, z: int) -> int:
	if not _dentro(x, z):
		return -1
	var i := x * _prof + z
	var t := _tipos[i]
	if t == T_RUA or t == T_CALCADA:
		return _mapa[i]
	return -1


func _preparar_mascaras() -> void:
	var n := _larg * _prof
	_livre = PackedByteArray()
	_livre.resize(n)
	_reservado = PackedByteArray()
	_reservado.resize(n)
	_ext = PackedByteArray()
	_ext.resize(n)
	_alt_rua = PackedInt32Array()
	_alt_rua.resize(n)

	var fonte_rua := PackedByteArray()
	fonte_rua.resize(n)
	var fonte_agua := PackedByteArray()
	fonte_agua.resize(n)

	for x in _larg:
		for z in _prof:
			var i := x * _prof + z
			var t := _tipos[i]
			if t == T_RUA or t == T_PONTE:
				fonte_rua[i] = 1
			elif t == T_AGUA:
				fonte_agua[i] = 1
			elif _dentro(x, z, margem_mapa) \
					and (t == T_GRAMA or t == T_PEDRA or (t == T_AREIA and permitir_areia)):
				_livre[i] = 1

	var limite := clampi(largura_calcada + profundidade_externa, 1, 250)
	_dist_rua = _bfs(fonte_rua, limite, true, true)
	_dist_agua = _bfs(fonte_agua, clampi(margem_agua, 0, 250), false, false)


# Busca em largura (vizinhanca de 8). Distancia 255 = nao alcancada.
# so_terra: so atravessa celulas livres. guardar_alt: propaga a altura da fonte.
@warning_ignore("integer_division")
func _bfs(fontes: PackedByteArray, limite: int, so_terra: bool, guardar_alt: bool) -> PackedByteArray:
	var n := _larg * _prof
	var dist := PackedByteArray()
	dist.resize(n)
	dist.fill(255)
	var fila := PackedInt32Array()
	for i in n:
		if fontes[i] != 0:
			dist[i] = 0
			fila.append(i)
			if guardar_alt:
				_alt_rua[i] = _mapa[i]

	var cabeca := 0
	while cabeca < fila.size():
		var i := fila[cabeca]
		cabeca += 1
		var d := dist[i]
		if d >= limite:
			continue
		var x := i / _prof
		var z := i % _prof
		for dx in range(-1, 2):
			var nx := x + dx
			if nx < 0 or nx >= _larg:
				continue
			for dz in range(-1, 2):
				if dx == 0 and dz == 0:
					continue
				var nz := z + dz
				if nz < 0 or nz >= _prof:
					continue
				var j := nx * _prof + nz
				if dist[j] != 255:
					continue
				if so_terra and _livre[j] == 0:
					continue
				dist[j] = d + 1
				if guardar_alt:
					_alt_rua[j] = _alt_rua[i]
				fila.append(j)
	return dist


# ---------------------------------------------------------------------------
# CALCADAS
# ---------------------------------------------------------------------------
func _pintar_calcadas() -> void:
	if largura_calcada <= 0:
		return
	for i in _larg * _prof:
		if _livre[i] != 0 and _dist_rua[i] <= largura_calcada:
			_tipos[i] = T_CALCADA
			_mapa[i] = maxi(_alt_rua[i] + elevacao_calcada, 1)
			_livre[i] = 0
			_n_calcada += 1


# ---------------------------------------------------------------------------
# QUADRAS INTERNAS (quarteiroes entre as ruas)
# ---------------------------------------------------------------------------
func _processar_internas() -> void:
	var ruas := get_node_or_null(no_ruas)
	if ruas == null:
		push_warning("Quadras: no de ruas nao encontrado em '%s'." % [no_ruas])
		return
	var folhas: Variant = ruas.get("quarteiroes")
	if folhas == null:
		push_warning("Quadras: o no de ruas nao tem a lista 'quarteiroes'.")
		return

	var mapa_rect := Rect2i(0, 0, _larg, _prof)
	for k in folhas.size():
		var folha: Rect2i = folhas[k]
		# cresce 3 celulas para cobrir o vao entre a calcada e o quarteirao
		var caixa := folha.grow(3).intersection(mapa_rect)
		for x in range(caixa.position.x, caixa.end.x):
			for z in range(caixa.position.y, caixa.end.y):
				var i := x * _prof + z
				if _livre[i] != 0:
					_reservado[i] = 1   # fica fora das quadras externas, mesmo sem virar quadra
		if quadras_internas:
			for r in _extrair(caixa, _livre):
				_registrar(r, false)


# ---------------------------------------------------------------------------
# QUADRAS EXTERNAS (faixas do lado de fora das ruas)
# ---------------------------------------------------------------------------
func _processar_externas() -> void:
	if not quadras_externas:
		return

	var limite := largura_calcada + profundidade_externa
	for i in _larg * _prof:
		if _livre[i] != 0 and _reservado[i] == 0 \
				and _dist_rua[i] <= limite and _dist_agua[i] > margem_agua:
			_ext[i] = 1

	# trabalha em ladrilhos para manter a busca rapida
	var mapa_rect := Rect2i(0, 0, _larg, _prof)
	for tx in range(0, _larg, LADRILHO):
		for tz in range(0, _prof, LADRILHO):
			var caixa := Rect2i(tx, tz, LADRILHO, LADRILHO).intersection(mapa_rect)
			for r in _extrair(caixa, _ext):
				for parte in _dividir_externa(r):
					if _rng.randf() < chance_quadra_externa:
						_registrar(parte, true)
					else:
						_n_descartadas += 1


# Corta uma faixa longa em pedacos de ate comprimento_max_externa
func _dividir_externa(r: Rect2i) -> Array[Rect2i]:
	var saida: Array[Rect2i] = []
	var comp_max := maxi(comprimento_max_externa, quadra_min)
	var ao_longo_x := r.size.x >= r.size.y
	var comp := r.size.x if ao_longo_x else r.size.y
	var partes := maxi(ceili(comp / float(comp_max)), 1)
	var ini := 0
	for k in partes:
		var fim := roundi(comp * (k + 1) / float(partes))
		if ao_longo_x:
			saida.append(Rect2i(r.position.x + ini, r.position.y, fim - ini, r.size.y))
		else:
			saida.append(Rect2i(r.position.x, r.position.y + ini, r.size.x, fim - ini))
		ini = fim
	return saida


# ---------------------------------------------------------------------------
# EXTRACAO DE RETANGULOS (maior retangulo livre, repetidamente)
# ---------------------------------------------------------------------------
# Maior retangulo de celulas com mascara = 1 dentro da caixa, com os dois lados
# >= quadra_min. Retorna Rect2i vazio se nao houver.
func _melhor_retangulo(caixa: Rect2i, mascara: PackedByteArray) -> Rect2i:
	var bw := caixa.size.x
	var bd := caixa.size.y
	var z_base := caixa.position.y
	var alturas := PackedInt32Array()
	alturas.resize(bd + 1)   # ultimo item e sentinela (sempre 0)
	var pilha: Array[int] = []
	var melhor := Rect2i()
	var melhor_area := 0

	for lx in bw:
		var gx := caixa.position.x + lx
		var base := gx * _prof + z_base
		for lz in bd:
			if mascara[base + lz] != 0:
				alturas[lz] += 1
			else:
				alturas[lz] = 0
		pilha.clear()
		for lz in range(bd + 1):
			var h := alturas[lz]
			while not pilha.is_empty() and alturas[pilha[pilha.size() - 1]] >= h:
				var topo: int = pilha.pop_back()
				var altura := alturas[topo]
				var esq := pilha[pilha.size() - 1] + 1 if not pilha.is_empty() else 0
				var larg := lz - esq
				if altura >= quadra_min and larg >= quadra_min and altura * larg > melhor_area:
					melhor_area = altura * larg
					melhor = Rect2i(gx - altura + 1, z_base + esq, altura, larg)
			pilha.append(lz)
	return melhor


func _limpar(r: Rect2i, mascara: PackedByteArray) -> void:
	for x in range(r.position.x, r.end.x):
		for z in range(r.position.y, r.end.y):
			mascara[x * _prof + z] = 0


func _extrair(caixa: Rect2i, mascara: PackedByteArray) -> Array[Rect2i]:
	var saida: Array[Rect2i] = []
	if caixa.size.x < quadra_min or caixa.size.y < quadra_min:
		return saida
	for tent in 32:
		var r := _melhor_retangulo(caixa, mascara)
		if r.size.x < quadra_min or r.size.y < quadra_min or r.get_area() < quadra_area_min:
			break
		saida.append(r)
		_limpar(r, mascara)
	return saida


# ---------------------------------------------------------------------------
# VERIFICACAO E REGISTRO DE UMA QUADRA
# ---------------------------------------------------------------------------
func _registrar(r: Rect2i, externa: bool) -> void:
	# verificacao: desnivel do relevo original dentro da quadra
	var mn := 1 << 20
	var mx := -(1 << 20)
	for x in range(r.position.x, r.end.x):
		for z in range(r.position.y, r.end.y):
			var h := _mapa[x * _prof + z]
			mn = mini(mn, h)
			mx = maxi(mx, h)
	if mx - mn > desnivel_max_quadra:
		_n_rej_desnivel += 1
		return

	var alvo := maxi(_altura_alvo(r) + elevacao_quadra, 1)

	for x in range(r.position.x, r.end.x):
		for z in range(r.position.y, r.end.y):
			var i := x * _prof + z
			_tipos[i] = T_QUADRA
			if nivelar_quadras:
				_mapa[i] = alvo

	var q := Quadra.new()
	q.rect = r
	q.externa = externa
	q.altura = alvo
	if gerar_lotes:
		for lr in _lotear(r):
			var l := Lote.new()
			l.rect = lr
			l.altura = alvo if nivelar_quadras else _mapa[(lr.position.x + (lr.size.x >> 1)) * _prof + lr.position.y + (lr.size.y >> 1)]
			l.frente = _frente(lr)
			q.lotes.append(l)
			lista_lotes.append(l)
	lista_quadras.append(q)
	if externa:
		_n_externas += 1
	else:
		_n_internas += 1


# Altura para nivelar: media das ruas/calcadas que rodeiam a quadra.
# Sem nenhuma por perto, usa a media do proprio terreno.
func _altura_alvo(r: Rect2i) -> int:
	var soma := 0
	var cont := 0
	for x in range(r.position.x, r.end.x):
		for z in [r.position.y - 1, r.end.y]:
			var h := _alt_via(x, z)
			if h >= 0:
				soma += h
				cont += 1
	for z in range(r.position.y, r.end.y):
		for x in [r.position.x - 1, r.end.x]:
			var h := _alt_via(x, z)
			if h >= 0:
				soma += h
				cont += 1
	if cont > 0:
		return roundi(soma / float(cont))

	soma = 0
	for x in range(r.position.x, r.end.x):
		for z in range(r.position.y, r.end.y):
			soma += _mapa[x * _prof + z]
	return roundi(soma / float(r.size.x * r.size.y))


# ---------------------------------------------------------------------------
# LOTES
# ---------------------------------------------------------------------------
# Divisao recursiva: corta o lado maior ate todos os lotes terem lado <= lote_max
func _lotear(r: Rect2i) -> Array[Rect2i]:
	var saida: Array[Rect2i] = []
	var minimo := mini(lote_min, (lote_max + 1) >> 1)
	var fila: Array[Rect2i] = [r]
	while not fila.is_empty():
		var c: Rect2i = fila.pop_back()
		var w := c.size.x
		var h := c.size.y
		if w <= lote_max and h <= lote_max:
			saida.append(c)
			continue
		if w >= h:
			var corte := _rng.randi_range(minimo, w - minimo)
			fila.append(Rect2i(c.position.x, c.position.y, corte, h))
			fila.append(Rect2i(c.position.x + corte, c.position.y, w - corte, h))
		else:
			var corte := _rng.randi_range(minimo, h - minimo)
			fila.append(Rect2i(c.position.x, c.position.y, w, corte))
			fila.append(Rect2i(c.position.x, c.position.y + corte, w, h - corte))
	return saida


# Direcao do lado do lote que encosta mais em rua/calcada (ZERO se nenhum).
func _frente(r: Rect2i) -> Vector2i:
	var melhor := Vector2i.ZERO
	var melhor_n := 0
	for d in 4:
		var dv: Vector2i = DIRS[d]
		var n := 0
		if dv.x != 0:
			var x := r.end.x if dv.x > 0 else r.position.x - 1
			for z in range(r.position.y, r.end.y):
				if _e_via(x, z):
					n += 1
		else:
			var z := r.end.y if dv.y > 0 else r.position.y - 1
			for x in range(r.position.x, r.end.x):
				if _e_via(x, z):
					n += 1
		if n > melhor_n:
			melhor_n = n
			melhor = dv
	return melhor
