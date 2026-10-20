extends Node3D

# As ruas NAO sao malhas novas: elas alteram Global.mapa (altura) e
# Global.tipos (tipo do bloco) ANTES da malha do terreno ser gerada.
#
# Logica:
#   1) escolhe "distritos" retangulares em terra firme e terreno calmo
#   2) cada distrito: rua de contorno + subdivisao recursiva em quarteiroes
#      (cortes que terminam em T), becos sem saida e anexos
#   3) distritos sao ligados por vias ortogonais (A*), evitando agua
#   4) so se NAO houver rota por terra, a via cruza um lago com uma ponte

# Indices de tipo (iguais aos de terreno.gd / Global.tipos)
const T_AGUA := 0
const T_RUA := 4
const T_PONTE := 5

const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

@export_group("Distritos")
@export var quantidade_distritos := 8
@export var largura_distrito := Vector2i(40, 112)        # min, max (em blocos)
@export var profundidade_distrito := Vector2i(32, 80)    # min, max (em blocos)
@export var distancia_entre_distritos := 12
@export var desnivel_max := 6.0                          # relevo maximo dentro do distrito

@export_group("Quarteiroes")
@export var bloco_min := 14            # menor lado de um quarteirao (entre eixos de ruas)
@export var bloco_max := 40            # acima disso sempre divide
@export var chance_parar := 0.7       # chance de nao dividir mais um bloco medio
@export var chance_beco := 0.2       # beco sem saida dentro do quarteirao
@export var chance_beco_bulbo := 0   # retorno redondo no fim do beco
@export var chance_anexo := 0      # bloco extra colado ao distrito

@export_group("Ruas")
@export var largura_rua := 3
@export var largura_avenida := 5     # contorno dos distritos e ligacoes
@export var ondulacao := 0          # balanco lateral das ruas (0 = reto)
@export var ligacoes_extra := 1        # ligacoes alem do minimo (criam ciclos)

@export_group("Pontes")
@export var permitir_pontes := true
@export var ponte_max := 12            # maior vao (em blocos) que pode virar ponte

@export_group("Altura das ruas")
@export var suavizacao := 10        # raio do desfoque do relevo (maior = ruas mais planas)

## Retangulos (em celulas) dos quarteiroes livres, para quadras/predios.
var quarteiroes: Array[Rect2i] = []

var _rng := RandomNumberGenerator.new()
var _larg := 0
var _prof := 0
var _mapa := PackedInt32Array()
var _tipos := PackedByteArray()
var _suave := PackedFloat32Array()
var _alt_ponte := PackedInt32Array()
var _nivel_agua_max := 0

var _distritos: Array[Rect2i] = []   # position = canto, size = distancia entre eixos das ruas
var _anexos: Array[Rect2i] = []
var _folhas: Array[Rect2i] = []

var _nos_x := 0
var _nos_z := 0
var _hf := PackedFloat32Array()      # heap do A*: custo
var _hn := PackedInt32Array()        # heap do A*: estado


func gerar_ruas() -> void:
	if Global.mapa.is_empty():
		push_error("Ruas: chame terreno.gerar_alturas() antes de gerar_ruas().")
		return

	_larg = Global.largura
	_prof = Global.profundidade
	var n := _larg * _prof
	_rng.seed = Global.seed + 7919

	_mapa = Global.mapa.duplicate()
	_tipos = Global.tipos.duplicate()
	_alt_ponte = PackedInt32Array()
	_alt_ponte.resize(n)
	_distritos.clear()
	_anexos.clear()
	_folhas.clear()
	quarteiroes.clear()

	_suave = _calcular_suave()

	_nivel_agua_max = 0
	for i in n:
		if _tipos[i] == T_AGUA:
			_nivel_agua_max = maxi(_nivel_agua_max, _mapa[i])

	_escolher_distritos()
	if _distritos.is_empty():
		push_warning("Ruas: nenhum local adequado para distritos (muita agua ou relevo?).")
	for k in _distritos.size():
		_desenhar_distrito(k)
	_ligar_distritos()
	_calcular_quarteiroes()

	# Altura final: ruas seguem o relevo suavizado; pontes usam a altura do vao
	var h_max: int = Global.altura_maxima
	for i in n:
		var t := _tipos[i]
		if t == T_RUA:
			_mapa[i] = clampi(roundi(_suave[i]), 1, h_max)
		elif t == T_PONTE:
			_mapa[i] = _alt_ponte[i]

	Global.mapa = _mapa
	Global.tipos = _tipos


# ---------------------------------------------------------------------------
# RELEVO SUAVIZADO (desfoque de caixa via tabela de somas, O(1) por celula)
# ---------------------------------------------------------------------------
func _calcular_suave() -> PackedFloat32Array:
	var w := _prof + 1
	var sat := PackedInt32Array()
	sat.resize((_larg + 1) * w)
	for x in _larg:
		for z in _prof:
			sat[(x + 1) * w + z + 1] = _mapa[x * _prof + z] + sat[x * w + z + 1] + sat[(x + 1) * w + z] - sat[x * w + z]

	var saida := PackedFloat32Array()
	saida.resize(_larg * _prof)
	var r := suavizacao
	for x in _larg:
		var x0 := maxi(x - r, 0)
		var x1 := mini(x + r + 1, _larg)
		for z in _prof:
			var z0 := maxi(z - r, 0)
			var z1 := mini(z + r + 1, _prof)
			var soma := sat[x1 * w + z1] - sat[x0 * w + z1] - sat[x1 * w + z0] + sat[x0 * w + z0]
			saida[x * _prof + z] = soma / float((x1 - x0) * (z1 - z0))
	return saida


# ---------------------------------------------------------------------------
# PRIMITIVAS
# ---------------------------------------------------------------------------
func _dentro(x: int, z: int, margem: int = 0) -> bool:
	return x >= margem and z >= margem and x < _larg - margem and z < _prof - margem


func _e_agua(x: int, z: int) -> bool:
	return _tipos[x * _prof + z] == T_AGUA


# chamado so com _dentro(x, z, 4) verdadeiro
func _agua_perto_fino(x: int, z: int) -> bool:
	return _tipos[x * _prof + z] == T_AGUA \
		or _tipos[(x + 2) * _prof + z] == T_AGUA \
		or _tipos[(x - 2) * _prof + z] == T_AGUA \
		or _tipos[x * _prof + z + 2] == T_AGUA \
		or _tipos[x * _prof + z - 2] == T_AGUA


func _contem(r: Rect2i, x: int, z: int) -> bool:
	return x >= r.position.x and x <= r.end.x and z >= r.position.y and z <= r.end.y


func _na_borda(x: int, z: int, r: Rect2i) -> bool:
	if not _contem(r, x, z):
		return false
	return x == r.position.x or x == r.end.x or z == r.position.y or z == r.end.y


# Pinta a rua em volta de (cx, cz). Agua so vira ponte se h_ponte >= 0.
func _carimbar(cx: int, cz: int, largura: int, redondo: bool, h_ponte: int = -1) -> void:
	var a := -((largura - 1) >> 1)
	var b := largura >> 1
	var r2 := largura * largura * 0.25
	for dx in range(a, b + 1):
		for dz in range(a, b + 1):
			if redondo and dx * dx + dz * dz > r2:
				continue
			var x := cx + dx
			var z := cz + dz
			if not _dentro(x, z):
				continue
			var i := x * _prof + z
			if _tipos[i] == T_AGUA:
				if h_ponte < 0:
					continue
				_tipos[i] = T_PONTE
				_alt_ponte[i] = h_ponte
			elif _tipos[i] != T_PONTE:
				_tipos[i] = T_RUA


# Ponte sobre uma lista ordenada de celulas de agua; altura interpolada entre as margens
func _construir_ponte(celulas: Array[Vector2i], h0: float, h1: float, largura: int, redondo: bool) -> void:
	var n := celulas.size()
	for k in n:
		var t := (k + 1.0) / (n + 1.0)
		var h := maxi(roundi(lerpf(h0, h1, t)), _nivel_agua_max + 1)
		_carimbar(celulas[k].x, celulas[k].y, largura, redondo, h)


# Celulas centrais de uma linha reta alinhada a um eixo, com balanco lateral
# que vale zero nas pontas (os encontros em T continuam encaixando).
func _pontos_linha(a: Vector2i, b: Vector2i, onda: float) -> Array[Vector2i]:
	var pts: Array[Vector2i] = []
	var horizontal := a.y == b.y
	var comp := absi(b.x - a.x) if horizontal else absi(b.y - a.y)
	var sx := signi(b.x - a.x)
	var sz := signi(b.y - a.y)
	var fase := _rng.randf() * TAU
	var freq := _rng.randf_range(3.0, 10.0)
	for k in range(comp + 1):
		var off := 0
		if onda > 0.0 and comp > 0:
			var t := k / float(comp)
			off = roundi(onda * sin(PI * t) * sin(t * freq + fase))
		var x := a.x + sx * k
		var z := a.y + sz * k
		if horizontal:
			z += off
		else:
			x += off
		pts.append(Vector2i(x, z))
	return pts


func _tracar(a: Vector2i, b: Vector2i, largura: int, onda: float, ponte: bool) -> void:
	var pts := _pontos_linha(a, b, onda)
	var run: Array[Vector2i] = []
	var antes := Vector2i(-1, -1)
	for i in pts.size():
		var c := pts[i]
		if ponte and _e_agua(c.x, c.y):
			run.append(c)
			continue
		if not run.is_empty():
			if antes.x >= 0:
				var h0 := _suave[antes.x * _prof + antes.y]
				var h1 := _suave[c.x * _prof + c.y]
				_construir_ponte(run, h0, h1, largura, false)
			run = []
		_carimbar(c.x, c.y, largura, false)
		antes = c


# Soma das variacoes de altura ao longo da linha (menor = rua mais plana)
func _custo_linha(a: Vector2i, b: Vector2i) -> float:
	var pts := _pontos_linha(a, b, 0.0)
	var custo := 0.0
	var anterior := _suave[pts[0].x * _prof + pts[0].y]
	for k in range(2, pts.size(), 2):
		var h := _suave[pts[k].x * _prof + pts[k].y]
		custo += absf(h - anterior)
		anterior = h
	return custo


# ---------------------------------------------------------------------------
# DISTRITOS
# ---------------------------------------------------------------------------
func _tem_agua(r: Rect2i, margem: int) -> bool:
	var x_a := maxi(r.position.x - margem, 0)
	var x_b := mini(r.end.x + margem, _larg - 1)
	var z_a := maxi(r.position.y - margem, 0)
	var z_b := mini(r.end.y + margem, _prof - 1)
	for x in range(x_a, x_b + 1, 2):
		for z in range(z_a, z_b + 1, 2):
			if _tipos[x * _prof + z] == T_AGUA:
				return true
	return false


func _sobrepoe(r: Rect2i, ignorar: int, folga: int) -> bool:
	var g := r.grow(folga)
	for k in _distritos.size():
		if k != ignorar and g.intersects(_distritos[k]):
			return true
	for k in _anexos.size():
		if g.intersects(_anexos[k]):
			return true
	return false


func _desnivel(r: Rect2i) -> float:
	var mn := INF
	var mx := -INF
	for x in range(r.position.x, r.end.x + 1, 4):
		for z in range(r.position.y, r.end.y + 1, 4):
			var h := _suave[x * _prof + z]
			mn = minf(mn, h)
			mx = maxf(mx, h)
	return mx - mn


func _escolher_distritos() -> void:
	for n in quantidade_distritos:
		var melhor := Rect2i()
		var melhor_nota := INF
		for tent in 60:
			var w := _rng.randi_range(largura_distrito.x >> 2, largura_distrito.y >> 2) << 2
			var h := _rng.randi_range(profundidade_distrito.x >> 2, profundidade_distrito.y >> 2) << 2
			var max_x := (_larg - w - 9) >> 2
			var max_z := (_prof - h - 9) >> 2
			if max_x < 2 or max_z < 2:
				continue
			var r := Rect2i(_rng.randi_range(2, max_x) << 2, _rng.randi_range(2, max_z) << 2, w, h)
			if _tem_agua(r, 4):
				continue
			if _sobrepoe(r, -1, distancia_entre_distritos):
				continue
			var nota := _desnivel(r)
			if nota > desnivel_max:
				continue
			nota += _rng.randf() * 1.5   # prefere terreno calmo, com variacao
			if nota < melhor_nota:
				melhor_nota = nota
				melhor = r
		if melhor_nota < INF:
			_distritos.append(melhor)


func _desenhar_distrito(idx: int) -> void:
	var r := _distritos[idx]
	var x0 := r.position.x
	var z0 := r.position.y
	var x1 := r.end.x
	var z1 := r.end.y

	# contorno
	_tracar(Vector2i(x0, z0), Vector2i(x1, z0), largura_avenida, ondulacao, false)
	_tracar(Vector2i(x0, z1), Vector2i(x1, z1), largura_avenida, ondulacao, false)
	_tracar(Vector2i(x0, z0), Vector2i(x0, z1), largura_avenida, ondulacao, false)
	_tracar(Vector2i(x1, z0), Vector2i(x1, z1), largura_avenida, ondulacao, false)

	_dividir(x0, z0, x1, z1)

	if _rng.randf() < chance_anexo:
		_anexo(r, idx)


# Subdivisao recursiva: cada corte cruza so o bloco atual e termina em T
func _dividir(x0: int, z0: int, x1: int, z1: int) -> void:
	var w := x1 - x0
	var h := z1 - z0
	var pode_v := w >= bloco_min * 2
	var pode_h := h >= bloco_min * 2
	var grande := maxi(w, h) > bloco_max

	if (not pode_v and not pode_h) or (not grande and _rng.randf() < chance_parar):
		_folha(x0, z0, x1, z1)
		return

	var vertical: bool
	if pode_v and pode_h:
		vertical = (w >= h) if _rng.randf() < 0.8 else (w < h)
	else:
		vertical = pode_v

	if vertical:
		var x := _melhor_corte(x0 + bloco_min, x1 - bloco_min, true, z0, z1)
		_tracar(Vector2i(x, z0), Vector2i(x, z1), largura_rua, ondulacao, false)
		_dividir(x0, z0, x, z1)
		_dividir(x, z0, x1, z1)
	else:
		var z := _melhor_corte(z0 + bloco_min, z1 - bloco_min, false, x0, x1)
		_tracar(Vector2i(x0, z), Vector2i(x1, z), largura_rua, ondulacao, false)
		_dividir(x0, z0, x1, z)
		_dividir(x0, z, x1, z1)


# Entre 4 posicoes candidatas, escolhe a de rua mais plana
func _melhor_corte(minimo: int, maximo: int, vertical: bool, a0: int, a1: int) -> int:
	var melhor := _rng.randi_range(minimo, maximo)
	var melhor_custo := INF
	for k in 4:
		var c := _rng.randi_range(minimo, maximo)
		var custo := INF
		if vertical:
			custo = _custo_linha(Vector2i(c, a0), Vector2i(c, a1))
		else:
			custo = _custo_linha(Vector2i(a0, c), Vector2i(a1, c))
		if custo < melhor_custo:
			melhor_custo = custo
			melhor = c
	return melhor


# Quarteirao final: registra e, as vezes, cria um beco sem saida
func _folha(x0: int, z0: int, x1: int, z1: int) -> void:
	var w := x1 - x0
	var h := z1 - z0
	if w - 7 > 0 and h - 7 > 0:
		_folhas.append(Rect2i(x0 + 4, z0 + 4, w - 7, h - 7))

	if mini(w, h) < 22 or _rng.randf() >= chance_beco:
		return

	var px := _rng.randi_range(x0 + 8, x1 - 8)
	var pz := _rng.randi_range(z0 + 8, z1 - 8)
	var dh := int(h * _rng.randf_range(0.35, 0.65))
	var dw := int(w * _rng.randf_range(0.35, 0.65))
	var a := Vector2i.ZERO
	var b := Vector2i.ZERO
	match _rng.randi_range(0, 3):
		0:   # entra pela borda norte
			a = Vector2i(px, z0)
			b = Vector2i(px, z0 + dh)
		1:   # entra pela borda sul
			a = Vector2i(px, z1)
			b = Vector2i(px, z1 - dh)
		2:   # entra pela borda oeste
			a = Vector2i(x0, pz)
			b = Vector2i(x0 + dw, pz)
		_:   # entra pela borda leste
			a = Vector2i(x1, pz)
			b = Vector2i(x1 - dw, pz)

	_tracar(a, b, largura_rua, ondulacao * 0.6, false)
	if _rng.randf() < chance_beco_bulbo:
		_carimbar(b.x, b.y, largura_rua + 2, true)


# Bloco extra colado a um lado do distrito
func _anexo(r: Rect2i, idx: int) -> void:
	var lado := _rng.randi_range(0, 3)   # 0 norte, 1 sul, 2 oeste, 3 leste
	var prof_a := _rng.randi_range(10, 18)
	var larg_a := _rng.randi_range(12, 28)
	var x0 := r.position.x
	var z0 := r.position.y
	var x1 := r.end.x
	var z1 := r.end.y
	var ar := Rect2i()

	match lado:
		0:
			var xa := _rng.randi_range(x0 + 6, maxi(x1 - 6 - larg_a, x0 + 6))
			ar = Rect2i(xa, z0 - prof_a, larg_a, prof_a)
		1:
			var xa := _rng.randi_range(x0 + 6, maxi(x1 - 6 - larg_a, x0 + 6))
			ar = Rect2i(xa, z1, larg_a, prof_a)
		2:
			var za := _rng.randi_range(z0 + 6, maxi(z1 - 6 - larg_a, z0 + 6))
			ar = Rect2i(x0 - prof_a, za, prof_a, larg_a)
		_:
			var za := _rng.randi_range(z0 + 6, maxi(z1 - 6 - larg_a, z0 + 6))
			ar = Rect2i(x1, za, prof_a, larg_a)

	# precisa caber no mapa, sem agua e sem encostar em outros distritos
	if ar.position.x < 8 or ar.position.y < 8 or ar.end.x > _larg - 9 or ar.end.y > _prof - 9:
		return
	if _tem_agua(ar, 3) or _sobrepoe(ar, idx, 6):
		return

	var p := ar.position
	var e := ar.end
	if lado != 1:
		_tracar(Vector2i(p.x, p.y), Vector2i(e.x, p.y), largura_rua, ondulacao, false)
	if lado != 0:
		_tracar(Vector2i(p.x, e.y), Vector2i(e.x, e.y), largura_rua, ondulacao, false)
	if lado != 3:
		_tracar(Vector2i(p.x, p.y), Vector2i(p.x, e.y), largura_rua, ondulacao, false)
	if lado != 2:
		_tracar(Vector2i(e.x, p.y), Vector2i(e.x, e.y), largura_rua, ondulacao, false)

	_anexos.append(ar)
	if ar.size.x - 7 > 0 and ar.size.y - 7 > 0:
		_folhas.append(Rect2i(p.x + 4, p.y + 4, ar.size.x - 7, ar.size.y - 7))


# ---------------------------------------------------------------------------
# LIGACAO ENTRE DISTRITOS
# ---------------------------------------------------------------------------
func _centro(i: int) -> Vector2:
	return Vector2(_distritos[i].position) + Vector2(_distritos[i].size) * 0.5


func _tem_aresta(arestas: Array[Vector2i], i: int, j: int) -> bool:
	for k in arestas.size():
		var e := arestas[k]
		if (e.x == i and e.y == j) or (e.x == j and e.y == i):
			return true
	return false


func _ligar_distritos() -> void:
	var n := _distritos.size()
	if n < 2:
		return
	_nos_x = ((_larg - 1) >> 2) + 1
	_nos_z = ((_prof - 1) >> 2) + 1

	# arvore geradora minima (Prim) pelas distancias entre centros
	var arestas: Array[Vector2i] = []
	var ligados: Array[int] = [0]
	while ligados.size() < n:
		var melhor := Vector2i(-1, -1)
		var melhor_d := INF
		for a in ligados.size():
			var i := ligados[a]
			for j in n:
				if ligados.has(j):
					continue
				var d := _centro(i).distance_to(_centro(j))
				if d < melhor_d:
					melhor_d = d
					melhor = Vector2i(i, j)
		arestas.append(melhor)
		ligados.append(melhor.y)

	# ligacoes extras (ciclos)
	for extra in ligacoes_extra:
		var melhor := Vector2i(-1, -1)
		var melhor_d := INF
		for i in n:
			for j in range(i + 1, n):
				if _tem_aresta(arestas, i, j):
					continue
				var d := _centro(i).distance_to(_centro(j))
				if d < melhor_d:
					melhor_d = d
					melhor = Vector2i(i, j)
		if melhor.x >= 0:
			arestas.append(melhor)

	for k in arestas.size():
		var e := arestas[k]
		var cantos := _rota(e.x, e.y, false)
		if cantos.is_empty() and permitir_pontes:
			cantos = _rota(e.x, e.y, true)
			if not cantos.is_empty() and _vao_maximo(cantos) > ponte_max:
				cantos = []
		if cantos.is_empty():
			push_warning("Ruas: nao foi possivel ligar os distritos %d e %d." % [e.x, e.y])
			continue
		for c in range(cantos.size() - 1):
			_tracar(cantos[c], cantos[c + 1], largura_avenida, ondulacao, true)


func _vao_maximo(cantos: Array[Vector2i]) -> int:
	var maior := 0
	var atual := 0
	for k in range(cantos.size() - 1):
		var pts := _pontos_linha(cantos[k], cantos[k + 1], 0.0)
		for i in pts.size():
			if _e_agua(pts[i].x, pts[i].y):
				atual += 1
				maior = maxi(maior, atual)
			else:
				atual = 0
	return maior


# No da malha grossa (passo 4) pode ser usado pela via?
func _no_livre(x: int, z: int, a: int, b: int, com_agua: bool) -> bool:
	if not _dentro(x, z, 4):
		return false
	for k in _distritos.size():
		var r := _distritos[k]
		if k == a or k == b:
			if _contem(r, x, z) and not _na_borda(x, z, r):
				return false   # interior do proprio distrito
		elif _contem(r.grow(4), x, z):
			return false
	for k in _anexos.size():
		if _contem(_anexos[k].grow(4), x, z):
			return false
	if com_agua:
		return true
	return not _agua_perto_fino(x, z)


func _dist_ret(x: int, z: int, r: Rect2i) -> float:
	var dx := maxi(maxi(r.position.x - x, x - r.end.x), 0)
	var dz := maxi(maxi(r.position.y - z, z - r.end.y), 0)
	return float(dx + dz)


# A* na malha grossa, com estado (no, direcao) para penalizar curvas.
# Retorna os cantos da rota (pontos de fim de cada trecho reto) ou [].
@warning_ignore("integer_division")
func _rota(a: int, b: int, com_agua: bool) -> Array[Vector2i]:
	var ra := _distritos[a]
	var rb := _distritos[b]
	var total := _nos_x * _nos_z * 4

	var g := PackedFloat32Array()
	g.resize(total)
	g.fill(INF)
	var veio := PackedInt32Array()
	veio.resize(total)
	veio.fill(-1)
	var fechado := PackedByteArray()
	fechado.resize(total)
	_hf.clear()
	_hn.clear()

	# fontes: todos os nos da borda do distrito de origem
	for i in range(ra.position.x >> 2, (ra.end.x >> 2) + 1):
		for j in range(ra.position.y >> 2, (ra.end.y >> 2) + 1):
			if _na_borda(i * 4, j * 4, ra):
				for d in 4:
					var s := (i * _nos_z + j) * 4 + d
					g[s] = 0.0
					_heap_push(_dist_ret(i * 4, j * 4, rb), s)

	while not _hn.is_empty():
		var s := _heap_pop()
		if fechado[s] != 0:
			continue
		fechado[s] = 1

		var d := s & 3
		var no := s >> 2
		var i := no / _nos_z
		var j := no % _nos_z
		var x := i * 4
		var z := j * 4

		if _na_borda(x, z, rb):
			return _reconstruir(s, veio)

		for nd in 4:
			if nd == (d ^ 1):
				continue   # sem retorno em U
			var dv: Vector2i = DIRS[nd]
			var ni := i + dv.x
			var nj := j + dv.y
			if ni < 0 or nj < 0 or ni >= _nos_x or nj >= _nos_z:
				continue
			var x2 := ni * 4
			var z2 := nj * 4
			if not _no_livre(x2, z2, a, b, com_agua):
				continue

			var custo := 4.0
			custo += 3.0 * absf(_suave[x2 * _prof + z2] - _suave[x * _prof + z])
			var bloqueado := false
			for k in range(1, 5):
				if _e_agua(x + dv.x * k, z + dv.y * k):
					if com_agua:
						custo += 6.0
					elif k < 4:
						bloqueado = true
						break
			if bloqueado:
				continue
			if nd != d:
				custo += 6.0   # penaliza curvas: vias mais retas

			var s2 := (ni * _nos_z + nj) * 4 + nd
			var novo := g[s] + custo
			if novo < g[s2]:
				g[s2] = novo
				veio[s2] = s
				_heap_push(novo + _dist_ret(x2, z2, rb), s2)

	return []


@warning_ignore("integer_division")
func _reconstruir(fim: int, veio: PackedInt32Array) -> Array[Vector2i]:
	var pts: Array[Vector2i] = []
	var s := fim
	while s != -1:
		var no := s >> 2
		pts.append(Vector2i((no / _nos_z) * 4, (no % _nos_z) * 4))
		s = veio[s]
	pts.reverse()
	if pts.size() < 2:
		return []

	var cantos: Array[Vector2i] = [pts[0]]
	for k in range(1, pts.size() - 1):
		if pts[k] - pts[k - 1] != pts[k + 1] - pts[k]:
			cantos.append(pts[k])
	cantos.append(pts[pts.size() - 1])
	return cantos


# ---------------------------------------------------------------------------
# HEAP BINARIO (fila de prioridade do A*)
# ---------------------------------------------------------------------------
func _heap_troca(i: int, j: int) -> void:
	var f := _hf[i]
	_hf[i] = _hf[j]
	_hf[j] = f
	var n := _hn[i]
	_hn[i] = _hn[j]
	_hn[j] = n


func _heap_push(f: float, n: int) -> void:
	_hf.append(f)
	_hn.append(n)
	var i := _hf.size() - 1
	while i > 0:
		var p := (i - 1) >> 1
		if _hf[p] <= _hf[i]:
			break
		_heap_troca(i, p)
		i = p


func _heap_pop() -> int:
	var topo := _hn[0]
	var ultimo := _hf.size() - 1
	_hf[0] = _hf[ultimo]
	_hn[0] = _hn[ultimo]
	_hf.resize(ultimo)
	_hn.resize(ultimo)
	var i := 0
	while true:
		var l := i * 2 + 1
		var r := l + 1
		var m := i
		if l < ultimo and _hf[l] < _hf[m]:
			m = l
		if r < ultimo and _hf[r] < _hf[m]:
			m = r
		if m == i:
			break
		_heap_troca(i, m)
		i = m
	return topo


# ---------------------------------------------------------------------------
# QUARTEIROES LIVRES (para quadras/predios)
# ---------------------------------------------------------------------------
func _calcular_quarteiroes() -> void:
	for k in _folhas.size():
		var r := _folhas[k]
		var total := r.size.x * r.size.y
		if total <= 0:
			continue
		var livres := 0
		for x in range(r.position.x, r.end.x):
			for z in range(r.position.y, r.end.y):
				var t := _tipos[x * _prof + z]
				if t != T_AGUA and t != T_RUA and t != T_PONTE:
					livres += 1
		if livres >= total * 0.85:
			quarteiroes.append(r)
