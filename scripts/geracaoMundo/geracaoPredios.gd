extends Node3D

# =============================================================================
#  GERADOR DE PREDIOS E CASAS
# =============================================================================
# Preenche as quadras geradas por geracaoQuadras.gd com construcoes 3D.
# As construcoes sao blocos (retangulares, quadrados ou em L) de alturas
# variadas, respeitando a calcada e maximizando o preenchimento da quadra.
#
# Tipos de construcao:
#   - Casa: 1-2 andares, base menor
#   - Predio: 3-8+ andares, base maior
#   - Em L: duas caixas retangulares unidas formando um L
#
# As construcoes sao geradas como malhas 3D independentes (MeshInstance3D)
# com materiais configuráveis. Sprites decorativos (portas, janelas, etc)
# sao aplicados como quads nas faces dos predios.
#
# TEXTURAS: use os exports texturas_parede, texturas_telhado para trocar.
# SPRITES: use os exports sprites_porta, sprites_janela, sprites_detalhe
# para trocar os elementos decorativos dos predios.
#
# Ordem de chamada:
#   terreno.gerar_alturas()
#   ruas.gerar_ruas()
#   quadras.gerar_quadras()
#   predios.gerar_predios()    <- este script
#   await terreno.gerar_malha()
# =============================================================================

const T_QUADRA := 7
const T_CALCADA := 6
const T_RUA := 4
const T_PONTE := 5

const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

# -----------------------------------------------------------------------------
#  CONFIGURACOES
# -----------------------------------------------------------------------------
@export_group("Ligacao")
## Caminho do no de quadras.
@export var no_quadras: NodePath = ^"../Quadras"

@export_group("Dimensoes")
## Menor lado de uma construcao (em blocos).
@export_range(2, 10) var construcao_min := 3
## Maior lado de uma construcao (em blocos).
@export_range(4, 30) var construcao_max := 12
## Margem minima entre construcao e borda da quadra (calcada).
@export_range(0, 4) var margem_calcada := 1
## Espaco minimo entre duas construcoes.
@export_range(0, 3) var espaco_entre := 1

@export_group("Alturas")
## Altura minima de uma casa (em andares, 1 andar = 3 blocos).
@export_range(1, 3) var andares_casa_min := 1
## Altura maxima de uma casa (em andares).
@export_range(1, 4) var andares_casa_max := 2
## Altura minima de um predio (em andares).
@export_range(2, 6) var andares_predio_min := 3
## Altura maxima de um predio (em andares).
@export_range(3, 20) var andares_predio_max := 8
## Blocos por andar.
@export_range(2, 5) var blocos_por_andar := 3
## Chance de uma construcao grande ser um predio (vs casa grande).
@export_range(0.0, 1.0, 0.05) var chance_predio := 0.6

@export_group("Formas")
## Chance de gerar construcao em L (se couber).
@export_range(0.0, 1.0, 0.05) var chance_forma_L := 0.25
## Chance de construcao retangular (vs quadrada).
@export_range(0.0, 1.0, 0.05) var chance_retangular := 0.7

@export_group("Coerencia")
## Construcoes vizinhas tendem a ter alturas parecidas.
@export var coerencia_altura := true
## Raio de influencia da coerencia (em blocos).
@export_range(5, 40) var raio_coerencia := 15
## Forca da coerencia (0 = sem influencia, 1 = altura identica aos vizinhos).
@export_range(0.0, 1.0, 0.05) var forca_coerencia := 0.6

@export_group("Texturas de Construcao")
## Texturas para paredes dos predios (escolhidas aleatoriamente por construcao).
@export var texturas_parede: Array[Texture2D] = []
## Texturas para telhados.
@export var texturas_telhado: Array[Texture2D] = []

@export_group("Sprites Decorativos")
## Sprites de portas (colocadas no terreo, na face da frente).
## Se vazio, gera sprites placeholder automaticamente.
@export var sprites_porta: Array[Texture2D] = []
## Sprites de janelas (distribuidas pelas faces).
## Se vazio, gera sprites placeholder automaticamente.
@export var sprites_janela: Array[Texture2D] = []
## Sprites de detalhes extras (ar condicionado, letreiros, etc).
## Se vazio, gera sprites placeholder automaticamente.
@export var sprites_detalhe: Array[Texture2D] = []
## Gerar sprites placeholder se nenhum for atribuido.
@export var gerar_sprites_teste := true
## Largura de uma janela em blocos.
@export_range(0.5, 2.0, 0.1) var janela_largura := 1.0
## Altura de uma janela em blocos.
@export_range(0.5, 2.0, 0.1) var janela_altura := 1.0
## Largura de uma porta em blocos.
@export_range(0.8, 2.0, 0.1) var porta_largura := 1.0
## Altura de uma porta em blocos.
@export_range(1.0, 3.0, 0.1) var porta_altura := 2.0
## Espaco horizontal entre janelas (em blocos).
@export_range(0.5, 4.0, 0.1) var janela_espacamento := 2.0
## Offset vertical da janela dentro do andar (0 = base do andar).
@export_range(0.2, 2.0, 0.1) var janela_offset_y := 0.8
## Chance de uma janela aparecer em cada slot possivel.
@export_range(0.0, 1.0, 0.05) var chance_janela := 0.85
## Chance de detalhe extra em cada slot de andar.
@export_range(0.0, 1.0, 0.05) var chance_detalhe := 0.15

@export_group("Cores Padrao (sem textura)")
## Paleta de cores para paredes (usada quando nao ha texturas).
@export var cores_parede: Array[Color] = [
	Color("e8dcc8"),  # bege claro
	Color("d4c4a8"),  # bege escuro
	Color("c8b898"),  # areia
	Color("b8c8d8"),  # azul claro
	Color("d8d0c0"),  # creme
	Color("c0b8a0"),  # khaki
	Color("e0d8c8"),  # marfim
	Color("c8c0b0"),  # cinza quente
]
## Paleta de cores para telhados.
@export var cores_telhado: Array[Color] = [
	Color("8b4513"),  # marrom
	Color("a0522d"),  # sienna
	Color("6b3a2a"),  # marrom escuro
	Color("708090"),  # cinza ardosia
	Color("556b2f"),  # verde escuro
	Color("4a4a50"),  # cinza escuro
]

@export_group("Depuracao")
@export var imprimir_relatorio := true

# -----------------------------------------------------------------------------
#  DADOS INTERNOS
# -----------------------------------------------------------------------------
class Construcao:
	var caixas: Array[Rect2i] = []     # 1 caixa = retangular/quadrado, 2 = L
	var andares: int = 1
	var altura_base: int = 0           # altura do chao (Global.mapa)
	var cor_parede: Color = Color.WHITE
	var cor_telhado: Color = Color.GRAY
	var idx_textura_parede: int = -1   # -1 = usar cor
	var idx_textura_telhado: int = -1
	var frente: Vector2i = Vector2i.ZERO  # direcao da frente

var _rng := RandomNumberGenerator.new()
var _larg := 0
var _prof := 0
var _ocupado: PackedByteArray = PackedByteArray()   # 1 = ja tem construcao
var _construcoes: Array[Construcao] = []
var _raiz: Node3D

# Materiais cacheados
var _mat_cache: Dictionary = {}  # chave: cor -> material
var _sprite_mats: Dictionary = {}

# Shader para predios
const PREDIO_SHADER_CODE := """
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

uniform vec4 cor_albedo : source_color = vec4(1.0);
uniform sampler2D textura_albedo : source_color, filter_nearest_mipmap, repeat_enable;
uniform bool usar_textura = false;

void fragment() {
	if (usar_textura) {
		ALBEDO = texture(textura_albedo, UV).rgb;
	} else {
		ALBEDO = cor_albedo.rgb;
	}
	ROUGHNESS = 1.0;
}
"""

# Shader para sprites decorativos (com transparencia)
const SPRITE_SHADER_CODE := """
shader_type spatial;
render_mode diffuse_lambert, specular_disabled, cull_back;

uniform sampler2D textura : source_color, filter_nearest;
uniform vec4 cor_fallback : source_color = vec4(0.2, 0.15, 0.1, 1.0);
uniform bool usar_textura = false;

void fragment() {
	if (usar_textura) {
		vec4 c = texture(textura, UV);
		ALBEDO = c.rgb;
		ALPHA = c.a;
		ALPHA_SCISSOR_THRESHOLD = 0.5;
	} else {
		ALBEDO = cor_fallback.rgb;
		ALPHA = cor_fallback.a;
	}
	ROUGHNESS = 1.0;
}
"""

var _shader_predio: Shader
var _shader_sprite: Shader


func gerar_predios() -> void:
	if Global.mapa.is_empty():
		push_error("Predios: chame terreno/ruas/quadras antes de gerar_predios().")
		return

	_larg = Global.largura
	_prof = Global.profundidade
	_rng.seed = Global.seed + 31337

	_ocupado.resize(_larg * _prof)
	_ocupado.fill(0)
	_construcoes.clear()
	_mat_cache.clear()
	_sprite_mats.clear()

	# Gerar sprites placeholder se necessario
	if gerar_sprites_teste:
		_gerar_sprites_placeholder()

	# Preparar shaders
	_shader_predio = Shader.new()
	_shader_predio.code = PREDIO_SHADER_CODE
	_shader_sprite = Shader.new()
	_shader_sprite.code = SPRITE_SHADER_CODE

	# Limpar nos anteriores
	if _raiz:
		_raiz.queue_free()
	_raiz = Node3D.new()
	_raiz.name = "ConstrucoesRoot"
	add_child(_raiz)

	# Buscar quadras
	var quadras_node = get_node_or_null(no_quadras)
	if quadras_node == null:
		push_warning("Predios: no de quadras nao encontrado em '%s'." % [no_quadras])
		return

	var lista: Variant = quadras_node.get("lista_quadras")
	if lista == null or lista.is_empty():
		push_warning("Predios: nenhuma quadra disponivel.")
		return

	# Gerar construcoes para cada quadra
	for quadra in lista:
		_preencher_quadra(quadra)

	# Construir malhas 3D
	for c in _construcoes:
		_construir_malha(c)

	if imprimir_relatorio:
		print("Predios: %d construcoes geradas." % [_construcoes.size()])


# ---------------------------------------------------------------------------
# PREENCHIMENTO DE UMA QUADRA
# ---------------------------------------------------------------------------
func _preencher_quadra(quadra) -> void:
	var rect: Rect2i = quadra.rect
	# Area util = quadra menos margem de calcada
	var util := Rect2i(
		rect.position.x + margem_calcada,
		rect.position.y + margem_calcada,
		rect.size.x - margem_calcada * 2,
		rect.size.y - margem_calcada * 2
	)
	if util.size.x < construcao_min or util.size.y < construcao_min:
		return

	# Tentar preencher a area util com construcoes
	# Usa uma abordagem de subdivisao + empacotamento
	var blocos := _subdividir_area(util)
	for bloco in blocos:
		_colocar_construcao(bloco, rect)


# Subdivide a area em blocos adequados para construcoes
func _subdividir_area(area: Rect2i) -> Array[Rect2i]:
	var saida: Array[Rect2i] = []
	var fila: Array[Rect2i] = [area]

	while not fila.is_empty():
		var r: Rect2i = fila.pop_back()
		var w := r.size.x
		var h := r.size.y

		if w < construcao_min or h < construcao_min:
			continue

		# Se cabe como construcao unica, aceitar
		if w <= construcao_max and h <= construcao_max:
			saida.append(r)
			continue

		# Precisa dividir - corta no lado maior
		if w >= h:
			# Cortar em X
			var min_corte := construcao_min
			var max_corte := w - construcao_min - espaco_entre
			if min_corte > max_corte:
				# Nao da pra dividir bem, aceita inteiro se nao for absurdo
				saida.append(r)
				continue
			var corte := _rng.randi_range(min_corte, max_corte)
			fila.append(Rect2i(r.position.x, r.position.y, corte, h))
			var resto := w - corte - espaco_entre
			if resto >= construcao_min:
				fila.append(Rect2i(r.position.x + corte + espaco_entre, r.position.y, resto, h))
		else:
			# Cortar em Z
			var min_corte := construcao_min
			var max_corte := h - construcao_min - espaco_entre
			if min_corte > max_corte:
				saida.append(r)
				continue
			var corte := _rng.randi_range(min_corte, max_corte)
			fila.append(Rect2i(r.position.x, r.position.y, w, corte))
			var resto := h - corte - espaco_entre
			if resto >= construcao_min:
				fila.append(Rect2i(r.position.x, r.position.y + corte + espaco_entre, w, resto))

	return saida


# Coloca uma construcao dentro de um bloco
func _colocar_construcao(bloco: Rect2i, quadra_rect: Rect2i) -> void:
	if bloco.size.x < construcao_min or bloco.size.y < construcao_min:
		return

	# Verificar se a area esta livre
	if not _area_livre(bloco):
		return

	# Verificar se e tudo quadra valida
	if not _area_valida(bloco):
		return

	var c := Construcao.new()
	c.altura_base = _altura_media(bloco)
	c.frente = _detectar_frente(bloco, quadra_rect)

	# Decidir forma: L, retangular ou quadrado
	var forma := _rng.randf()
	if forma < chance_forma_L and bloco.size.x >= construcao_min * 2 and bloco.size.y >= construcao_min * 2:
		# Forma em L
		c.caixas = _gerar_forma_L(bloco)
	elif forma < chance_forma_L + chance_retangular:
		# Retangular (usar o bloco inteiro ou parte dele)
		c.caixas = [_ajustar_retangulo(bloco)]
	else:
		# Quadrado
		var lado := mini(bloco.size.x, bloco.size.y)
		lado = mini(lado, construcao_max)
		var ox := _rng.randi_range(0, maxi(bloco.size.x - lado, 0))
		var oz := _rng.randi_range(0, maxi(bloco.size.y - lado, 0))
		c.caixas = [Rect2i(bloco.position.x + ox, bloco.position.y + oz, lado, lado)]

	if c.caixas.is_empty():
		return

	# Decidir se e casa ou predio
	var area_total := 0
	for cx in c.caixas:
		area_total += cx.get_area()

	var e_predio := _rng.randf() < chance_predio and area_total >= construcao_min * construcao_min * 2

	if e_predio:
		c.andares = _rng.randi_range(andares_predio_min, andares_predio_max)
	else:
		c.andares = _rng.randi_range(andares_casa_min, andares_casa_max)

	# Aplicar coerencia de altura
	if coerencia_altura:
		c.andares = _aplicar_coerencia(c)

	# Cores/texturas
	if not cores_parede.is_empty():
		c.cor_parede = cores_parede[_rng.randi() % cores_parede.size()]
	if not cores_telhado.is_empty():
		c.cor_telhado = cores_telhado[_rng.randi() % cores_telhado.size()]
	if not texturas_parede.is_empty():
		c.idx_textura_parede = _rng.randi() % texturas_parede.size()
	if not texturas_telhado.is_empty():
		c.idx_textura_telhado = _rng.randi() % texturas_telhado.size()

	# Marcar area como ocupada
	for cx in c.caixas:
		_marcar_ocupado(cx)

	_construcoes.append(c)


# ---------------------------------------------------------------------------
# FORMAS
# ---------------------------------------------------------------------------
func _gerar_forma_L(bloco: Rect2i) -> Array[Rect2i]:
	var w := bloco.size.x
	var h := bloco.size.y
	var x0 := bloco.position.x
	var z0 := bloco.position.y

	# Dividir o bloco em L: duas caixas que se sobrepoem em um canto
	var tipo_L := _rng.randi_range(0, 3)  # 4 rotacoes do L

	# Tamanho dos dois bracos do L
	var bw1 := _rng.randi_range(construcao_min, maxi(w - construcao_min, construcao_min))
	var bh1 := h
	var bw2 := w
	var bh2 := _rng.randi_range(construcao_min, maxi(h - construcao_min, construcao_min))

	var caixas: Array[Rect2i] = []

	match tipo_L:
		0:  # L normal (canto superior esquerdo)
			caixas.append(Rect2i(x0, z0, bw1, bh1))       # braco vertical
			caixas.append(Rect2i(x0, z0, bw2, bh2))       # braco horizontal
		1:  # L invertido (canto superior direito)
			caixas.append(Rect2i(x0 + w - bw1, z0, bw1, bh1))
			caixas.append(Rect2i(x0, z0, bw2, bh2))
		2:  # L de cabeca (canto inferior esquerdo)
			caixas.append(Rect2i(x0, z0, bw1, bh1))
			caixas.append(Rect2i(x0, z0 + h - bh2, bw2, bh2))
		3:  # L invertido de cabeca (canto inferior direito)
			caixas.append(Rect2i(x0 + w - bw1, z0, bw1, bh1))
			caixas.append(Rect2i(x0, z0 + h - bh2, bw2, bh2))

	# Verificar validade
	for cx in caixas:
		if cx.size.x < construcao_min or cx.size.y < construcao_min:
			return [_ajustar_retangulo(bloco)]  # fallback para retangulo
		if not _area_valida(cx):
			return [_ajustar_retangulo(bloco)]

	return caixas


func _ajustar_retangulo(bloco: Rect2i) -> Rect2i:
	var w := mini(bloco.size.x, construcao_max)
	var h := mini(bloco.size.y, construcao_max)
	# Pequena variacao para nao ficar tudo do mesmo tamanho
	if w > construcao_min + 1:
		w = _rng.randi_range(maxi(construcao_min, w - 3), w)
	if h > construcao_min + 1:
		h = _rng.randi_range(maxi(construcao_min, h - 3), h)
	var ox := _rng.randi_range(0, maxi(bloco.size.x - w, 0))
	var oz := _rng.randi_range(0, maxi(bloco.size.y - h, 0))
	return Rect2i(bloco.position.x + ox, bloco.position.y + oz, w, h)


# ---------------------------------------------------------------------------
# COERENCIA DE ALTURA
# ---------------------------------------------------------------------------
func _aplicar_coerencia(c: Construcao) -> int:
	if _construcoes.is_empty():
		return c.andares

	var centro := Vector2(c.caixas[0].position.x + c.caixas[0].size.x * 0.5,
						  c.caixas[0].position.y + c.caixas[0].size.y * 0.5)

	var soma := 0.0
	var peso_total := 0.0

	for outra in _construcoes:
		var outro_centro := Vector2(outra.caixas[0].position.x + outra.caixas[0].size.x * 0.5,
									outra.caixas[0].position.y + outra.caixas[0].size.y * 0.5)
		var dist := centro.distance_to(outro_centro)
		if dist < raio_coerencia:
			var peso := 1.0 - (dist / raio_coerencia)
			soma += outra.andares * peso
			peso_total += peso

	if peso_total < 0.01:
		return c.andares

	var media := soma / peso_total
	var alvo := lerpf(float(c.andares), media, forca_coerencia)
	return clampi(roundi(alvo), andares_casa_min, andares_predio_max)


# ---------------------------------------------------------------------------
# DETECCAO DE FRENTE (lado mais proximo da rua)
# ---------------------------------------------------------------------------
func _detectar_frente(bloco: Rect2i, quadra_rect: Rect2i) -> Vector2i:
	var melhor := Vector2i.ZERO
	var melhor_n := 0

	for d in 4:
		var dv: Vector2i = DIRS[d]
		var n := 0
		if dv.x != 0:
			var x: int = bloco.end.x if dv.x > 0 else bloco.position.x - 1
			for z in range(bloco.position.y, bloco.end.y):
				if _e_via(x, z):
					n += 1
		else:
			var z: int = bloco.end.y if dv.y > 0 else bloco.position.y - 1
			for x in range(bloco.position.x, bloco.end.x):
				if _e_via(x, z):
					n += 1
		if n > melhor_n:
			melhor_n = n
			melhor = dv

	# Fallback: usar o lado mais proximo da borda da quadra
	if melhor == Vector2i.ZERO:
		var cx := bloco.position.x + bloco.size.x / 2
		var cz := bloco.position.y + bloco.size.y / 2
		var dist_esq := cx - quadra_rect.position.x
		var dist_dir := quadra_rect.end.x - cx
		var dist_cim := cz - quadra_rect.position.y
		var dist_bai := quadra_rect.end.y - cz
		var menor := mini(mini(dist_esq, dist_dir), mini(dist_cim, dist_bai))
		if menor == dist_esq:
			melhor = Vector2i(-1, 0)
		elif menor == dist_dir:
			melhor = Vector2i(1, 0)
		elif menor == dist_cim:
			melhor = Vector2i(0, -1)
		else:
			melhor = Vector2i(0, 1)

	return melhor


func _e_via(x: int, z: int) -> bool:
	if x < 0 or z < 0 or x >= _larg or z >= _prof:
		return false
	var t = Global.tipos[x * _prof + z]
	return t == T_RUA or t == T_CALCADA or t == T_PONTE


# ---------------------------------------------------------------------------
# VERIFICACOES
# ---------------------------------------------------------------------------
func _area_livre(r: Rect2i) -> bool:
	for x in range(r.position.x, r.end.x):
		for z in range(r.position.y, r.end.y):
			if x < 0 or z < 0 or x >= _larg or z >= _prof:
				return false
			if _ocupado[x * _prof + z] != 0:
				return false
	return true


func _area_valida(r: Rect2i) -> bool:
	for x in range(r.position.x, r.end.x):
		for z in range(r.position.y, r.end.y):
			if x < 0 or z < 0 or x >= _larg or z >= _prof:
				return false
			if Global.tipos[x * _prof + z] != T_QUADRA:
				return false
	return true


func _marcar_ocupado(r: Rect2i) -> void:
	for x in range(r.position.x, r.end.x):
		for z in range(r.position.y, r.end.y):
			if x >= 0 and z >= 0 and x < _larg and z < _prof:
				_ocupado[x * _prof + z] = 1


func _altura_media(r: Rect2i) -> int:
	var soma := 0
	var n := 0
	for x in range(r.position.x, r.end.x):
		for z in range(r.position.y, r.end.y):
			if x >= 0 and z >= 0 and x < _larg and z < _prof:
				soma += Global.mapa[x * _prof + z]
				n += 1
	if n == 0:
		return 1
	return roundi(float(soma) / n)


# ---------------------------------------------------------------------------
# CONSTRUCAO DA MALHA 3D
# ---------------------------------------------------------------------------
func _construir_malha(c: Construcao) -> void:
	var s: float = Global.tamanho_cubo
	var altura_total: float = c.andares * blocos_por_andar * s
	var base_y: float = c.altura_base * s

	# Material da parede
	var mat_parede := _obter_material_predio(c.cor_parede, c.idx_textura_parede, false)
	# Material do telhado
	var mat_telhado := _obter_material_predio(c.cor_telhado, c.idx_textura_telhado, true)

	for caixa in c.caixas:
		var no_caixa := Node3D.new()
		no_caixa.name = "Construcao_%d_%d" % [caixa.position.x, caixa.position.y]

		# === PAREDES ===
		var mesh_paredes := _gerar_mesh_paredes(caixa, base_y, altura_total, s)
		var mi_paredes := MeshInstance3D.new()
		mi_paredes.mesh = mesh_paredes
		mi_paredes.material_override = mat_parede
		mi_paredes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		no_caixa.add_child(mi_paredes)

		# === TELHADO ===
		var mesh_telhado := _gerar_mesh_telhado(caixa, base_y + altura_total, s)
		var mi_telhado := MeshInstance3D.new()
		mi_telhado.mesh = mesh_telhado
		mi_telhado.material_override = mat_telhado
		mi_telhado.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		no_caixa.add_child(mi_telhado)

		# === SPRITES DECORATIVOS ===
		_adicionar_decoracoes(no_caixa, c, caixa, base_y, altura_total, s)

		_raiz.add_child(no_caixa)


func _gerar_mesh_paredes(caixa: Rect2i, base_y: float, altura: float, s: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var x0: float = caixa.position.x * s
	var z0: float = caixa.position.y * s
	var x1: float = caixa.end.x * s
	var z1: float = caixa.end.y * s
	var w: float = (x1 - x0)
	var h: float = (z1 - z0)
	var y0: float = base_y
	var y1: float = base_y + altura

	# Face Norte (Z-)
	_quad_st(st, Vector3(x0, y0, z0), Vector3(w, 0, 0), Vector3(0, altura, 0), Vector3(0, 0, -1), w / s, altura / s)
	# Face Sul (Z+)
	_quad_st(st, Vector3(x1, y0, z1), Vector3(-w, 0, 0), Vector3(0, altura, 0), Vector3(0, 0, 1), w / s, altura / s)
	# Face Oeste (X-)
	_quad_st(st, Vector3(x0, y0, z1), Vector3(0, 0, -h), Vector3(0, altura, 0), Vector3(-1, 0, 0), h / s, altura / s)
	# Face Leste (X+)
	_quad_st(st, Vector3(x1, y0, z0), Vector3(0, 0, h), Vector3(0, altura, 0), Vector3(1, 0, 0), h / s, altura / s)

	st.generate_tangents()
	return st.commit()


func _gerar_mesh_telhado(caixa: Rect2i, topo_y: float, s: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var x0: float = caixa.position.x * s
	var z0: float = caixa.position.y * s
	var x1: float = caixa.end.x * s
	var z1: float = caixa.end.y * s
	var w: float = x1 - x0
	var h: float = z1 - z0

	# Topo
	_quad_st(st, Vector3(x0, topo_y, z0), Vector3(w, 0, 0), Vector3(0, 0, h), Vector3(0, 1, 0), w / s, h / s)

	st.generate_tangents()
	return st.commit()


func _quad_st(st: SurfaceTool, origem: Vector3, du: Vector3, dv: Vector3, normal: Vector3, u_tile: float, v_tile: float) -> void:
	# 4 vertices: origem, origem+du, origem+du+dv, origem+dv
	var p0 := origem
	var p1 := origem + du
	var p2 := origem + du + dv
	var p3 := origem + dv

	st.set_normal(normal)

	# No Godot, a face frontal usa sentido horario (clockwise).
	# Se du.cross(dv) aponta no mesmo sentido da normal, o sentido horario e p0 -> p2 -> p1 e p0 -> p3 -> p2.
	if du.cross(dv).dot(normal) > 0.0:
		# Tri 1
		st.set_uv(Vector2(0, v_tile)); st.add_vertex(p0)
		st.set_uv(Vector2(u_tile, 0)); st.add_vertex(p2)
		st.set_uv(Vector2(u_tile, v_tile)); st.add_vertex(p1)
		# Tri 2
		st.set_uv(Vector2(0, v_tile)); st.add_vertex(p0)
		st.set_uv(Vector2(0, 0)); st.add_vertex(p3)
		st.set_uv(Vector2(u_tile, 0)); st.add_vertex(p2)
	else:
		# Tri 1
		st.set_uv(Vector2(0, v_tile)); st.add_vertex(p0)
		st.set_uv(Vector2(u_tile, v_tile)); st.add_vertex(p1)
		st.set_uv(Vector2(u_tile, 0)); st.add_vertex(p2)
		# Tri 2
		st.set_uv(Vector2(0, v_tile)); st.add_vertex(p0)
		st.set_uv(Vector2(u_tile, 0)); st.add_vertex(p2)
		st.set_uv(Vector2(0, 0)); st.add_vertex(p3)


# ---------------------------------------------------------------------------
# MATERIAIS
# ---------------------------------------------------------------------------
func _obter_material_predio(cor: Color, idx_tex: int, e_telhado: bool) -> ShaderMaterial:
	var chave := "%s_%d_%s" % [cor.to_html(), idx_tex, str(e_telhado)]
	if chave in _mat_cache:
		return _mat_cache[chave]

	var mat := ShaderMaterial.new()
	mat.shader = _shader_predio
	mat.set_shader_parameter("cor_albedo", cor)

	if idx_tex >= 0:
		var tex: Texture2D
		if e_telhado and idx_tex < texturas_telhado.size():
			tex = texturas_telhado[idx_tex]
		elif not e_telhado and idx_tex < texturas_parede.size():
			tex = texturas_parede[idx_tex]
		if tex:
			mat.set_shader_parameter("textura_albedo", tex)
			mat.set_shader_parameter("usar_textura", true)
		else:
			mat.set_shader_parameter("usar_textura", false)
	else:
		mat.set_shader_parameter("usar_textura", false)

	_mat_cache[chave] = mat
	return mat


func _obter_material_sprite(tex: Texture2D, cor_fallback: Color) -> ShaderMaterial:
	var chave: String
	if tex:
		chave = "spr_%d" % [tex.get_rid().get_id()]
	else:
		chave = "spr_%s" % [cor_fallback.to_html()]
	if chave in _sprite_mats:
		return _sprite_mats[chave]

	var mat := ShaderMaterial.new()
	mat.shader = _shader_sprite
	mat.render_priority = 1
	if tex:
		mat.set_shader_parameter("textura", tex)
		mat.set_shader_parameter("usar_textura", true)
	else:
		mat.set_shader_parameter("usar_textura", false)
		mat.set_shader_parameter("cor_fallback", cor_fallback)

	_sprite_mats[chave] = mat
	return mat


# ---------------------------------------------------------------------------
# DECORACOES (PORTAS, JANELAS, DETALHES)
# ---------------------------------------------------------------------------
func _adicionar_decoracoes(parent: Node3D, c: Construcao, caixa: Rect2i, base_y: float, altura_total: float, s: float) -> void:
	var x0: float = caixa.position.x * s
	var z0: float = caixa.position.y * s
	var x1: float = caixa.end.x * s
	var z1: float = caixa.end.y * s

	# Dados das 4 faces: [ponto_inicio, direcao_ao_longo, normal, comprimento]
	var faces := [
		# Norte (Z-)
		{"pos": Vector3(x0, base_y, z0), "ao_longo": Vector3(1, 0, 0), "normal": Vector3(0, 0, -1), "comp": x1 - x0, "dir": Vector2i(0, -1)},
		# Sul (Z+)
		{"pos": Vector3(x1, base_y, z1), "ao_longo": Vector3(-1, 0, 0), "normal": Vector3(0, 0, 1), "comp": x1 - x0, "dir": Vector2i(0, 1)},
		# Oeste (X-)
		{"pos": Vector3(x0, base_y, z1), "ao_longo": Vector3(0, 0, -1), "normal": Vector3(-1, 0, 0), "comp": z1 - z0, "dir": Vector2i(-1, 0)},
		# Leste (X+)
		{"pos": Vector3(x1, base_y, z0), "ao_longo": Vector3(0, 0, 1), "normal": Vector3(1, 0, 0), "comp": z1 - z0, "dir": Vector2i(1, 0)},
	]

	var altura_andar: float = blocos_por_andar * s
	var porta_colocada := false

	for face in faces:
		var e_frente: bool = (face["dir"] as Vector2i) == c.frente
		var pos: Vector3 = face["pos"]
		var ao_longo: Vector3 = face["ao_longo"]
		var normal: Vector3 = face["normal"]
		var comp: float = face["comp"]

		# === PORTA (apenas na frente, terreo) ===
		if e_frente and not porta_colocada:
			var porta_x: float = comp * 0.5 - porta_largura * s * 0.5
			var porta_pos := pos + ao_longo * porta_x + normal * 0.03
			_colocar_sprite_quad(parent, porta_pos, ao_longo, normal,
				porta_largura * s, porta_altura * s, _escolher_sprite_porta())
			porta_colocada = true

		# === JANELAS (todos os andares) ===
		for andar in c.andares:
			var y_andar: float = andar * altura_andar

			# Se e o terreo e e a frente, pular a regiao da porta
			var num_janelas := floori(comp / (janela_espacamento * s))
			if num_janelas <= 0:
				continue

			var espacamento_real: float = comp / num_janelas

			for j in num_janelas:
				# Pular o slot central no terreo da frente (porta)
				if andar == 0 and e_frente:
					var pos_j := (j + 0.5) * espacamento_real
					if absf(pos_j - comp * 0.5) < porta_largura * s:
						continue

				if _rng.randf() > chance_janela:
					continue

				var off_x: float = (j + 0.5) * espacamento_real - janela_largura * s * 0.5
				var jan_pos := pos + ao_longo * off_x + normal * 0.03 + Vector3(0, y_andar + janela_offset_y * s, 0)
				_colocar_sprite_quad(parent, jan_pos, ao_longo, normal,
					janela_largura * s, janela_altura * s, _escolher_sprite_janela())

		# === DETALHES EXTRAS ===
		if not sprites_detalhe.is_empty() or chance_detalhe > 0:
			for andar in range(1, c.andares):
				if _rng.randf() > chance_detalhe:
					continue
				var det_x: float = _rng.randf_range(1.0, comp - 1.0)
				var det_y: float = andar * altura_andar + _rng.randf_range(0.5, altura_andar - 1.0) * s
				var det_pos := pos + ao_longo * det_x + normal * 0.04 + Vector3(0, det_y, 0)
				_colocar_sprite_quad(parent, det_pos, ao_longo, normal,
					0.8 * s, 0.6 * s, _escolher_sprite_detalhe())


func _colocar_sprite_quad(parent: Node3D, pos: Vector3, ao_longo: Vector3, normal: Vector3,
	largura: float, altura: float, material: ShaderMaterial) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var du := ao_longo.normalized() * largura
	var dv := Vector3(0.0, altura, 0.0)

	st.set_normal(normal)

	var p0 := pos
	var p1 := pos + du
	var p2 := pos + du + dv
	var p3 := pos + dv

	if du.cross(dv).dot(normal) > 0.0:
		st.set_uv(Vector2(0, 1)); st.add_vertex(p0)
		st.set_uv(Vector2(1, 0)); st.add_vertex(p2)
		st.set_uv(Vector2(1, 1)); st.add_vertex(p1)

		st.set_uv(Vector2(0, 1)); st.add_vertex(p0)
		st.set_uv(Vector2(0, 0)); st.add_vertex(p3)
		st.set_uv(Vector2(1, 0)); st.add_vertex(p2)
	else:
		st.set_uv(Vector2(0, 1)); st.add_vertex(p0)
		st.set_uv(Vector2(1, 1)); st.add_vertex(p1)
		st.set_uv(Vector2(1, 0)); st.add_vertex(p2)

		st.set_uv(Vector2(0, 1)); st.add_vertex(p0)
		st.set_uv(Vector2(1, 0)); st.add_vertex(p2)
		st.set_uv(Vector2(0, 0)); st.add_vertex(p3)

	st.generate_tangents()
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


# Escolher sprites com fallback para cor solida
func _escolher_sprite_porta() -> ShaderMaterial:
	if not sprites_porta.is_empty():
		return _obter_material_sprite(sprites_porta[_rng.randi() % sprites_porta.size()], Color.TRANSPARENT)
	return _obter_material_sprite(null, Color("5a3a1a"))  # marrom porta


func _escolher_sprite_janela() -> ShaderMaterial:
	if not sprites_janela.is_empty():
		return _obter_material_sprite(sprites_janela[_rng.randi() % sprites_janela.size()], Color.TRANSPARENT)
	# Janela = cor clara com transparencia parcial para simular vidro
	var cores_janela := [
		Color("8ec8e8"),  # azul claro (vidro)
		Color("a8d8f0"),  # azul mais claro
		Color("78b8d8"),  # azul medio
		Color("c8d8e0"),  # cinza azulado
	]
	return _obter_material_sprite(null, cores_janela[_rng.randi() % cores_janela.size()])


func _escolher_sprite_detalhe() -> ShaderMaterial:
	if not sprites_detalhe.is_empty():
		return _obter_material_sprite(sprites_detalhe[_rng.randi() % sprites_detalhe.size()], Color.TRANSPARENT)
	var cores_det := [
		Color("888888"),  # cinza (ar condicionado)
		Color("666666"),  # cinza escuro
		Color("998877"),  # bege (letreiro)
	]
	return _obter_material_sprite(null, cores_det[_rng.randi() % cores_det.size()])



# ---------------------------------------------------------------------------
# GERACAO DE SPRITES PLACEHOLDER (teste)
# ---------------------------------------------------------------------------
# Cria sprites procedurais pixel-art para portas, janelas e detalhes.
# So gera se os arrays correspondentes estiverem vazios.
# ---------------------------------------------------------------------------
func _gerar_sprites_placeholder() -> void:
	if sprites_porta.is_empty():
		sprites_porta.append(_criar_textura_porta())
	if sprites_janela.is_empty():
		sprites_janela.append(_criar_textura_janela_residencial())
		sprites_janela.append(_criar_textura_janela_comercial())
	if sprites_detalhe.is_empty():
		sprites_detalhe.append(_criar_textura_ar_condicionado())


func _criar_textura_porta() -> ImageTexture:
	var img := Image.create(16, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	# Moldura
	for x in 16:
		for y in 32:
			if x == 0 or x == 15 or y == 0:
				img.set_pixel(x, y, Color("3a2a1a"))
			elif x >= 1 and x <= 14 and y >= 1 and y <= 30:
				img.set_pixel(x, y, Color("6b4226"))
	# Paineis (sulcos na porta)
	for x in range(3, 13):
		for y in range(3, 13):
			img.set_pixel(x, y, Color("7a5232"))
	for x in range(3, 13):
		for y in range(17, 27):
			img.set_pixel(x, y, Color("7a5232"))
	# Linhas dos paineis
	for x in range(2, 14):
		img.set_pixel(x, 2, Color("4a3018"))
		img.set_pixel(x, 13, Color("4a3018"))
		img.set_pixel(x, 16, Color("4a3018"))
		img.set_pixel(x, 27, Color("4a3018"))
	for y in range(2, 28):
		img.set_pixel(2, y, Color("4a3018"))
		img.set_pixel(13, y, Color("4a3018"))
	# Macaneta
	img.set_pixel(11, 19, Color("d4a830"))
	img.set_pixel(11, 20, Color("d4a830"))
	img.set_pixel(12, 19, Color("b89028"))
	img.set_pixel(12, 20, Color("b89028"))

	return ImageTexture.create_from_image(img)


func _criar_textura_janela_residencial() -> ImageTexture:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	for x in 16:
		for y in 16:
			if x == 0 or x == 15 or y == 0 or y == 15:
				img.set_pixel(x, y, Color("f0e8e0"))  # moldura branca
			elif x == 7 or x == 8:
				img.set_pixel(x, y, Color("e0d8d0"))  # barra vertical
			elif y == 7 or y == 8:
				img.set_pixel(x, y, Color("e0d8d0"))  # barra horizontal
			elif x >= 1 and x <= 6 and y >= 1 and y <= 6:
				img.set_pixel(x, y, Color("90c8e8"))  # vidro sup esq
			elif x >= 9 and x <= 14 and y >= 1 and y <= 6:
				img.set_pixel(x, y, Color("88c0e0"))  # vidro sup dir
			elif x >= 1 and x <= 6 and y >= 9 and y <= 14:
				img.set_pixel(x, y, Color("80b8d8"))  # vidro inf esq
			elif x >= 9 and x <= 14 and y >= 9 and y <= 14:
				img.set_pixel(x, y, Color("78b0d0"))  # vidro inf dir
	# Reflexo
	img.set_pixel(3, 3, Color("b0e0f8"))
	img.set_pixel(4, 3, Color("a8d8f0"))
	img.set_pixel(3, 4, Color("a8d8f0"))

	return ImageTexture.create_from_image(img)


func _criar_textura_janela_comercial() -> ImageTexture:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	for x in 16:
		for y in 16:
			if x == 0 or x == 15 or y == 0 or y == 15:
				img.set_pixel(x, y, Color("383838"))  # moldura escura
			elif y == 7 or y == 8:
				img.set_pixel(x, y, Color("404040"))  # divisoria
			else:
				img.set_pixel(x, y, Color("406888"))  # vidro fumê
	# Reflexo
	img.set_pixel(2, 2, Color("6090b0"))
	img.set_pixel(3, 2, Color("5888a8"))
	img.set_pixel(2, 3, Color("5888a8"))
	img.set_pixel(3, 3, Color("5080a0"))

	return ImageTexture.create_from_image(img)


func _criar_textura_ar_condicionado() -> ImageTexture:
	var img := Image.create(16, 12, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	# Corpo da unidade
	for x in 16:
		for y in 12:
			if x == 0 or x == 15 or y == 0 or y == 11:
				img.set_pixel(x, y, Color("989898"))  # borda
			elif y >= 2 and y <= 9:
				if x % 2 == 0:
					img.set_pixel(x, y, Color("787878"))  # grade
				else:
					img.set_pixel(x, y, Color("b8b8b8"))  # espaco
			else:
				img.set_pixel(x, y, Color("c0c0c0"))  # corpo
	# Detalhe da marca
	img.set_pixel(7, 1, Color("4080a0"))
	img.set_pixel(8, 1, Color("4080a0"))

	return ImageTexture.create_from_image(img)
