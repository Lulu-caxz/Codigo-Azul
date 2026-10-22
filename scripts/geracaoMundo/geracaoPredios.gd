extends Node3D

# =============================================================================
#  GERADOR DE PREDIOS E CASAS  (versao refinada)
# =============================================================================
# Preenche as quadras geradas por geracaoQuadras.gd com construcoes 3D.
#
# O QUE MUDOU EM RELACAO A VERSAO ANTERIOR
#   * Portas, janelas e detalhes (ar condicionado...) NUNCA se sobrepoem: cada
#     face guarda uma lista de retangulos ocupados e todo sprite novo e testado
#     contra ela. Sprites tambem ficam afastados das quinas.
#   * Construcao em L agora e feita com caixas que NAO se sobrepoem. Faces
#     internas (onde uma caixa encosta na outra) nao sao geradas, nem recebem
#     janelas. Antes havia telhados coplanares (z-fighting) e janelas dentro
#     da outra caixa.
#   * Uma porta por construcao, na face da frente (a maior parede voltada p/ rua).
#   * Texturas nao sao mais espelhadas nas paredes.
#   * Geometria MESCLADA: cada chunk vira 1 malha solida (paredes+telhados) e
#     1 malha de sprites, com 1 surface por material. Antes eram ~2 + dezenas
#     de MeshInstance3D POR construcao (cada janela era um no).
#   * Cor das paredes/telhados vai no vertex color (1 material para todas as cores).
#   * Chunks sao gerados em thread (WorkerThreadPool) e so existem perto da
#     camera: entram ao chegar perto e sao liberados ao se afastar.
#   * Coerencia de altura usa grade espacial (antes era O(n^2)).
#   * Frente da construcao detectada olhando a rua alem da borda da quadra.
#   * Base da construcao = menor altura do terreno sob ela (sem buracos).
#
# Ordem de chamada (igual a antes):
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

## Tamanho (em celulas) do chunk de construcoes usado no streaming.
const CHUNK_PREDIOS := 32

# -----------------------------------------------------------------------------
#  CONFIGURACOES
# -----------------------------------------------------------------------------
@export_group("Ligacao")
## Caminho do no de quadras.
@export var no_quadras: NodePath = ^"../Quadras"

@export_group("Renderizacao por Distancia")
## Gera/mostra construcoes apenas perto da camera. Desligue para gerar tudo de uma vez.
@export var renderizar_so_proximo := true
## Distancia (unidades do mundo) em que um chunk de construcoes passa a ser gerado.
@export_range(30.0, 600.0, 1.0) var distancia_render := 110.0
## Folga extra antes de liberar um chunk (evita liga/desliga na fronteira).
@export_range(0.0, 200.0, 1.0) var histerese_render := 30.0
## Intervalo (segundos) entre verificacoes da posicao da camera.
@export_range(0.05, 2.0, 0.05) var intervalo_atualizacao := 0.25
## Quantos chunks podem ser calculados em thread ao mesmo tempo.
@export_range(1, 8) var tarefas_simultaneas := 2
## Quantos chunks prontos sao montados (viram nos) por frame.
@export_range(1, 8) var montagens_por_frame := 2
## Construcoes projetam sombra (paredes e telhados; sprites nunca projetam).
@export var projetar_sombras := true

@export_group("Colisao")
## Gera colisao solida para paredes/predios.
@export var gerar_colisao := true
## Camada de fisica em que as construcoes ficam (o mundo costuma ser a 1).
@export_flags_3d_physics var camada_colisao := 1

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
## Altura minima de uma casa (em andares).
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
## Sprites de portas (terreo, na face da frente). Vazio = placeholder.
@export var sprites_porta: Array[Texture2D] = []
## Sprites de janelas. Vazio = placeholder.
@export var sprites_janela: Array[Texture2D] = []
## Sprites de detalhes extras (ar condicionado, letreiros...). Vazio = placeholder.
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
## Largura de um detalhe (ar condicionado...) em blocos.
@export_range(0.3, 2.0, 0.1) var detalhe_largura := 0.8
## Altura de um detalhe em blocos.
@export_range(0.3, 2.0, 0.1) var detalhe_altura := 0.6
## Espaco horizontal entre janelas (em blocos).
@export_range(0.5, 4.0, 0.1) var janela_espacamento := 2.0
## Offset vertical da janela dentro do andar (0 = base do andar).
@export_range(0.2, 2.0, 0.1) var janela_offset_y := 0.8
## Chance de uma janela aparecer em cada slot possivel.
@export_range(0.0, 1.0, 0.05) var chance_janela := 0.85
## Chance de detalhe extra em cada andar de cada parede.
@export_range(0.0, 1.0, 0.05) var chance_detalhe := 0.15
## Maximo de detalhes extras por parede.
@export_range(0, 6) var detalhes_por_parede_max := 2
## Distancia minima (blocos) entre qualquer sprite e a quina da parede.
@export_range(0.2, 2.0, 0.1) var margem_borda_sprite := 0.6
## Folga minima (blocos) entre dois sprites na mesma parede.
@export_range(0.0, 1.0, 0.05) var folga_entre_sprites := 0.25
## Quantas posicoes sao tentadas para cada detalhe antes de desistir.
@export_range(1, 20) var tentativas_detalhe := 8
## Quanto o sprite sai da parede (evita z-fighting).
@export_range(0.005, 0.1, 0.005) var recuo_sprite := 0.03

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

@export_group("Abrigo")
## Cor das paredes do abrigo.
@export var cor_abrigo_parede: Color = Color("3a6ea8")
## Cor do telhado do abrigo.
@export var cor_abrigo_telhado: Color = Color("1f4f8a")
## Sprite retangular exibido acima da porta do abrigo (se vazio, gera um retangulo com a cor das paredes).
@export var sprite_abrigo: Texture2D
## Tamanho (pixel_size) do sprite do abrigo.
@export_range(0.001, 0.5, 0.001) var tamanho_sprite_abrigo: float = 0.02
## Texto exibido no sinal do abrigo.
@export var texto_abrigo: String = "ABRIGO"

@export_group("Depuracao")
@export var imprimir_relatorio := true

# -----------------------------------------------------------------------------
#  DADOS INTERNOS
# -----------------------------------------------------------------------------
class Construcao:
	var caixas: Array[Rect2i] = []     # caixas SEM sobreposicao (1 = retangulo, 2 = L)
	var bbox := Rect2i()               # retangulo que envolve todas as caixas
	var andares := 1
	var altura_base := 0               # altura do chao (Global.mapa)
	var cor_parede := Color.WHITE
	var cor_telhado := Color.GRAY
	var idx_textura_parede := -1       # -1 = usar cor
	var idx_textura_telhado := -1
	var frente := Vector2i.ZERO        # direcao da frente
	var semente := 0                   # semente propria das decoracoes (deterministico)
	var eh_abrigo := false             # marca a construcao escolhida como abrigo
	var tem_porta := false
	var porta_mundo := Vector3.ZERO     # posicao da porta (interacao)


# Acumulador de geometria (um por material dentro de um chunk).
class Acum:
	var vert := PackedVector3Array()
	var norm := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cores := PackedColorArray()
	var indices := PackedInt32Array()

	# Quad por origem + dois vetores de aresta. O sentido dos triangulos e
	# ajustado para a face frontal (horario no Godot) apontar para a normal.
	func quad(origem: Vector3, du: Vector3, dv: Vector3, normal: Vector3,
			tile_u: float, tile_v: float, cor: Color, v_invertido: bool) -> void:
		var base := vert.size()
		vert.append(origem)
		vert.append(origem + du)
		vert.append(origem + du + dv)
		vert.append(origem + dv)
		if v_invertido:
			# origem embaixo (v = maximo): imagem fica de pe nas paredes
			uvs.append(Vector2(0.0, tile_v))
			uvs.append(Vector2(tile_u, tile_v))
			uvs.append(Vector2(tile_u, 0.0))
			uvs.append(Vector2(0.0, 0.0))
		else:
			uvs.append(Vector2(0.0, 0.0))
			uvs.append(Vector2(tile_u, 0.0))
			uvs.append(Vector2(tile_u, tile_v))
			uvs.append(Vector2(0.0, tile_v))
		for i in 4:
			norm.append(normal)
			cores.append(cor)
		if du.cross(dv).dot(normal) > 0.0:
			indices.append_array(PackedInt32Array([base, base + 2, base + 1, base, base + 3, base + 2]))
		else:
			indices.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))


var _rng := RandomNumberGenerator.new()
var _larg := 0
var _prof := 0
var _mapa := PackedInt32Array()
var _tipos := PackedByteArray()
var _ocupado := PackedByteArray()                 # 1 = ja tem construcao
var _construcoes: Array[Construcao] = []
var _grade_coer: Dictionary = {}                  # Vector2i -> Array[Construcao]
var _raiz: Node3D

# Abrigo escolhido na geracao
var abrigo_construcao: Construcao = null
var abrigo_posicao: Vector3 = Vector3.ZERO      # centro da construcao (para o mapa)
var abrigo_porta_pos: Vector3 = Vector3.ZERO    # porta (interacao)

# Chunks de construcoes
var _chunks: Dictionary = {}          # Vector2i -> Array[Construcao]
var _chunk_rects: Dictionary = {}     # Vector2i -> Rect2 (x,z em unidades do mundo)
var _chunk_nos: Dictionary = {}       # Vector2i -> Node3D (chunks existentes)
var _tarefas: Dictionary = {}         # Vector2i -> {"id": int, "dados": Dictionary}
var _desejados: Dictionary = {}       # Vector2i -> true (dentro do raio de saida)
var _fila: Array = []                 # chunks a gerar, do mais perto ao mais longe
var _tempo := 0.0
var _gerado := false

# Sprites (indices em _tex_sprites; -1 = cor solida de fallback)
var _tex_sprites: Array[Texture2D] = []
var _idx_portas: Array[int] = []
var _idx_janelas: Array[int] = []
var _idx_detalhes: Array[int] = []

var _cores_janela: Array[Color] = [Color("8ec8e8"), Color("a8d8f0"), Color("78b8d8"), Color("c8d8e0")]
var _cores_detalhe: Array[Color] = [Color("888888"), Color("666666"), Color("998877")]
var _cor_porta := Color("5a3a1a")

# Materiais
var _mats_pred: Dictionary = {}
var _mats_sprite: Dictionary = {}
var _shader_predio: Shader
var _shader_sprite: Shader

# Cor vem do vertex color (ja em espaco linear); textura, se houver, e multiplicada.
const PREDIO_SHADER_CODE := """
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

uniform sampler2D textura_albedo : source_color, filter_nearest_mipmap, repeat_enable;
uniform bool usar_textura = false;

void fragment() {
	vec3 base = COLOR.rgb;
	if (usar_textura) {
		base = texture(textura_albedo, UV).rgb * COLOR.rgb;
	}
	ALBEDO = base;
	ROUGHNESS = 1.0;
}
"""

# Sprites decorativos: recorte por alpha (opaco, sem ordenacao de transparencia).
const SPRITE_SHADER_CODE := """
shader_type spatial;
render_mode diffuse_lambert, specular_disabled, cull_back;

uniform sampler2D textura : source_color, filter_nearest_mipmap, repeat_disable;
uniform bool usar_textura = false;

void fragment() {
	vec4 c = vec4(1.0);
	if (usar_textura) {
		c = texture(textura, UV);
	}
	ALBEDO = c.rgb * COLOR.rgb;
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 1.0;
}
"""


# ---------------------------------------------------------------------------
# GERACAO (planejamento das construcoes: so dados, sem nos)
# ---------------------------------------------------------------------------
func gerar_predios() -> void:
	if Global.mapa.is_empty():
		push_error("Predios: chame terreno/ruas/quadras antes de gerar_predios().")
		return

	_esperar_tarefas()
	_gerado = false

	_larg = Global.largura
	_prof = Global.profundidade
	_mapa = Global.mapa
	_tipos = Global.tipos
	_rng.seed = Global.seed + 31337

	_ocupado.resize(_larg * _prof)
	_ocupado.fill(0)
	_construcoes.clear()
	_grade_coer.clear()
	_chunks.clear()
	_chunk_rects.clear()
	_chunk_nos.clear()
	_desejados.clear()
	_fila.clear()
	_mats_pred.clear()
	_mats_sprite.clear()

	_preparar_sprites()

	if _shader_predio == null:
		_shader_predio = Shader.new()
		_shader_predio.code = PREDIO_SHADER_CODE
	if _shader_sprite == null:
		_shader_sprite = Shader.new()
		_shader_sprite.code = SPRITE_SHADER_CODE

	if is_instance_valid(_raiz):
		_raiz.queue_free()
	_raiz = Node3D.new()
	_raiz.name = "ConstrucoesRoot"
	add_child(_raiz)

	var quadras_node = get_node_or_null(no_quadras)
	if quadras_node == null:
		push_warning("Predios: no de quadras nao encontrado em '%s'." % [no_quadras])
		return

	var lista: Variant = quadras_node.get("lista_quadras")
	if lista == null or lista.is_empty():
		push_warning("Predios: nenhuma quadra disponivel.")
		return

	for quadra in lista:
		_preencher_quadra(quadra)

	# Escolhe uma construcao como abrigo: deve ter porta voltada para uma via.
	# Candidatos: porta voltada para BAIXO (sul) e com via na frente.
	var candidatos: Array[Construcao] = []
	for c in _construcoes:
		if c.frente == Vector2i(0, 1) and _porta_voltada_para_via(c):
			candidatos.append(c)
	if candidatos.is_empty():
		for c in _construcoes:
			if c.frente == Vector2i(0, 1):
				candidatos.append(c)
	if candidatos.is_empty():
		candidatos = _construcoes.duplicate()

	print("ABRIGO: construcoes=", _construcoes.size(), " candidatos=", candidatos.size())
	if not candidatos.is_empty():
		abrigo_construcao = candidatos[_rng.randi() % candidatos.size()]
		abrigo_construcao.eh_abrigo = true
		abrigo_construcao.cor_parede = cor_abrigo_parede.srgb_to_linear()
		abrigo_construcao.cor_telhado = cor_abrigo_telhado.srgb_to_linear()
		abrigo_construcao.idx_textura_parede = -1
		abrigo_construcao.idx_textura_telhado = -1

		var s := Global.tamanho_cubo
		var bb := abrigo_construcao.bbox
		var dv := abrigo_construcao.frente
		var base_y := abrigo_construcao.altura_base * s
		var door_x: float
		var door_z: float
		if dv.x > 0:
			door_x = (bb.end.x) * s
			door_z = (bb.position.y + bb.size.y * 0.5) * s
		elif dv.x < 0:
			door_x = (bb.position.x) * s
			door_z = (bb.position.y + bb.size.y * 0.5) * s
		elif dv.y > 0:
			door_x = (bb.position.x + bb.size.x * 0.5) * s
			door_z = (bb.end.y) * s
		else:
			door_x = (bb.position.x + bb.size.x * 0.5) * s
			door_z = (bb.position.y) * s

		abrigo_posicao = Vector3(bb.get_center().x * s, base_y, bb.get_center().y * s)
		abrigo_porta_pos = Vector3(door_x, base_y + porta_altura * s * 0.5, door_z)
		abrigo_construcao.porta_mundo = abrigo_porta_pos
		Global.abrigo_position = Vector3(abrigo_posicao.x, 0.0, abrigo_posicao.z)
		print(Global.abrigo_position)
		print("ABRIGO selecionado: porta=", abrigo_porta_pos, " centro=", abrigo_posicao)
		_criar_sinal_abrigo(abrigo_porta_pos, Vector3(0.0, 0.0, 1.0))

	_indexar_chunks()

	if imprimir_relatorio:
		print("Predios: %d construcoes em %d chunks (streaming: %s)." % [
			_construcoes.size(), _chunks.size(), str(renderizar_so_proximo)])

	_tempo = intervalo_atualizacao   # forca atualizacao imediata
	_gerado = true

	if not renderizar_so_proximo:
		# Modo antigo: gera tudo agora, sem threads.
		for ch in _chunks:
			var dados := {"paredes": {}, "telhados": {}, "sprites": {}}
			for c in _chunks[ch]:
				_gerar_geometria(c, dados["paredes"], dados["telhados"], dados["sprites"])
			_montar_chunk(ch, dados)


# Adicione esta função no seu script de Prédios (logo após gerar_predios):

## Força o carregamento e montagem de todos os chunks próximos à câmera antes de liberar a tela
func aguardar_chunks_iniciais() -> void:
	if not renderizar_so_proximo:
		return # Se o streaming estiver desligado, gerar_predios() já montou tudo.

	# Atualiza a lista de chunks desejados com base na posição atual da câmera
	_atualizar_chunks()

	# Loop até que a fila de espera e as tarefas nas threads terminem completamente
	while not _fila.is_empty() or not _tarefas.is_empty():
		# 1. Inicia tarefas nas threads disponíveis
		while _tarefas.size() < tarefas_simultaneas and not _fila.is_empty():
			var ch: Vector2i = _fila.pop_front()
			if _chunk_nos.has(ch) or _tarefas.has(ch) or not _desejados.has(ch):
				continue
			_iniciar_chunk(ch)

		# 2. Verifica e monta todos os chunks que já terminaram (sem limite por frame aqui)
		for ch in _tarefas.keys():
			var t: Dictionary = _tarefas[ch]
			if WorkerThreadPool.is_task_completed(t["id"]):
				WorkerThreadPool.wait_for_task_completion(t["id"])
				_tarefas.erase(ch)
				if _desejados.has(ch) and not _chunk_nos.has(ch):
					_montar_chunk(ch, t["dados"])

		await get_tree().process_frame


# ---------------------------------------------------------------------------
# STREAMING POR DISTANCIA DA CAMERA
# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	if not _gerado or not renderizar_so_proximo:
		return

	_tempo += delta
	if _tempo >= intervalo_atualizacao:
		_tempo = 0.0
		_atualizar_chunks()

	# 1) monta chunks cujas threads terminaram
	var montados := 0
	for ch in _tarefas.keys():
		if montados >= montagens_por_frame:
			break
		var t: Dictionary = _tarefas[ch]
		if WorkerThreadPool.is_task_completed(t["id"]):
			WorkerThreadPool.wait_for_task_completion(t["id"])
			_tarefas.erase(ch)
			if _desejados.has(ch) and not _chunk_nos.has(ch):
				_montar_chunk(ch, t["dados"])
				montados += 1

	# 2) inicia novas tarefas (do mais perto ao mais longe)
	while _tarefas.size() < tarefas_simultaneas and not _fila.is_empty():
		var ch: Vector2i = _fila.pop_front()
		if _chunk_nos.has(ch) or _tarefas.has(ch) or not _desejados.has(ch):
			continue
		_iniciar_chunk(ch)


func _atualizar_chunks() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var p := to_local(cam.global_position)
	var pxz := Vector2(p.x, p.z)
	var r_entra := distancia_render
	var r_sai := distancia_render + histerese_render

	var candidatos: Array = []
	for ch in _chunks:
		var d := _dist_rect(pxz, _chunk_rects[ch])
		if d > r_sai:
			_desejados.erase(ch)
			if _chunk_nos.has(ch):
				(_chunk_nos[ch] as Node3D).queue_free()
				_chunk_nos.erase(ch)
		elif d <= r_entra:
			_desejados[ch] = true
			if not _chunk_nos.has(ch) and not _tarefas.has(ch):
				candidatos.append([d, ch])

	candidatos.sort_custom(func(a, b): return a[0] < b[0])
	_fila.clear()
	for item in candidatos:
		_fila.append(item[1])


func _dist_rect(p: Vector2, r: Rect2) -> float:
	var dx := maxf(maxf(r.position.x - p.x, p.x - r.end.x), 0.0)
	var dz := maxf(maxf(r.position.y - p.y, p.y - r.end.y), 0.0)
	return sqrt(dx * dx + dz * dz)


func _iniciar_chunk(ch: Vector2i) -> void:
	var dados := {"paredes": {}, "telhados": {}, "sprites": {}}
	var id := WorkerThreadPool.add_task(_gerar_chunk_thread.bind(ch, dados), false, "Predios")
	_tarefas[ch] = {"id": id, "dados": dados}


# Roda em thread: so calcula arrays (nenhum no/recurso e tocado aqui).
func _gerar_chunk_thread(ch: Vector2i, dados: Dictionary) -> void:
	for c in _chunks[ch]:
		_gerar_geometria(c, dados["paredes"], dados["telhados"], dados["sprites"])


func _esperar_tarefas() -> void:
	for ch in _tarefas:
		WorkerThreadPool.wait_for_task_completion(_tarefas[ch]["id"])
	_tarefas.clear()


func _exit_tree() -> void:
	_esperar_tarefas()


# Thread principal: transforma os arrays em malhas + nos.
func _montar_chunk(ch: Vector2i, dados: Dictionary) -> void:
	if not is_instance_valid(_raiz):
		return
	var no := Node3D.new()
	no.name = "Chunk_%d_%d" % [ch.x, ch.y]

	var solido := ArrayMesh.new()
	_commit(solido, dados["paredes"], 0)
	_commit(solido, dados["telhados"], 1)
	if solido.get_surface_count() > 0:
		var mi := MeshInstance3D.new()
		mi.mesh = solido
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if projetar_sombras \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		no.add_child(mi)

	var deco := ArrayMesh.new()
	_commit(deco, dados["sprites"], 2)
	if deco.get_surface_count() > 0:
		var mi2 := MeshInstance3D.new()
		mi2.mesh = deco
		mi2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		no.add_child(mi2)

	if gerar_colisao:
		_criar_colisao(ch, no)

	_raiz.add_child(no)
	_chunk_nos[ch] = no


# Thread principal: 1 StaticBody3D por chunk, 1 caixa de colisao por caixa de construcao.
func _criar_colisao(ch: Vector2i, no: Node3D) -> void:
	var s: float = Global.tamanho_cubo
	var corpo := StaticBody3D.new()
	corpo.name = "Colisao"
	corpo.collision_layer = camada_colisao
	corpo.collision_mask = 0   # corpo estatico nao precisa detectar nada

	for c in _chunks[ch]:
		var altura: float = c.andares * blocos_por_andar * s
		var base_y: float = c.altura_base * s
		for caixa in c.caixas:
			var forma := BoxShape3D.new()
			forma.size = Vector3(caixa.size.x * s, altura, caixa.size.y * s)
			var cs := CollisionShape3D.new()
			cs.shape = forma
			cs.position = Vector3(
				(caixa.position.x + caixa.size.x * 0.5) * s,
				base_y + altura * 0.5,
				(caixa.position.y + caixa.size.y * 0.5) * s)
			corpo.add_child(cs)

	if corpo.get_child_count() > 0:
		no.add_child(corpo)
	else:
		corpo.free()

# tipo: 0 = paredes, 1 = telhados, 2 = sprites
func _commit(malha: ArrayMesh, grupos: Dictionary, tipo: int) -> void:
	for k in grupos:
		var a: Acum = grupos[k]
		if a.vert.is_empty():
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = a.vert
		arrays[Mesh.ARRAY_NORMAL] = a.norm
		arrays[Mesh.ARRAY_TEX_UV] = a.uvs
		arrays[Mesh.ARRAY_COLOR] = a.cores
		arrays[Mesh.ARRAY_INDEX] = a.indices
		malha.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var mat: ShaderMaterial
		match tipo:
			0:
				mat = _mat_predio(int(k), false)
			1:
				mat = _mat_predio(int(k), true)
			_:
				mat = _mat_sprite(int(k))
		malha.surface_set_material(malha.get_surface_count() - 1, mat)


func _indexar_chunks() -> void:
	var s: float = Global.tamanho_cubo
	for c in _construcoes:
		var ch := Vector2i(c.bbox.get_center() / CHUNK_PREDIOS)
		var r := Rect2(Vector2(c.bbox.position) * s, Vector2(c.bbox.size) * s)
		if not _chunks.has(ch):
			_chunks[ch] = []
			_chunk_rects[ch] = r
		else:
			_chunk_rects[ch] = (_chunk_rects[ch] as Rect2).merge(r)
		(_chunks[ch] as Array).append(c)


# ---------------------------------------------------------------------------
# PREENCHIMENTO DE UMA QUADRA
# ---------------------------------------------------------------------------
func _preencher_quadra(quadra) -> void:
	var rect: Rect2i = quadra.rect
	var util := Rect2i(
		rect.position.x + margem_calcada,
		rect.position.y + margem_calcada,
		rect.size.x - margem_calcada * 2,
		rect.size.y - margem_calcada * 2
	)
	if util.size.x < construcao_min or util.size.y < construcao_min:
		return

	for bloco in _subdividir_area(util):
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

		if w <= construcao_max and h <= construcao_max:
			saida.append(r)
			continue

		if w >= h:
			var max_corte := w - construcao_min - espaco_entre
			if construcao_min > max_corte:
				saida.append(r)
				continue
			var corte := _rng.randi_range(construcao_min, max_corte)
			fila.append(Rect2i(r.position.x, r.position.y, corte, h))
			var resto := w - corte - espaco_entre
			if resto >= construcao_min:
				fila.append(Rect2i(r.position.x + corte + espaco_entre, r.position.y, resto, h))
		else:
			var max_corte := h - construcao_min - espaco_entre
			if construcao_min > max_corte:
				saida.append(r)
				continue
			var corte := _rng.randi_range(construcao_min, max_corte)
			fila.append(Rect2i(r.position.x, r.position.y, w, corte))
			var resto := h - corte - espaco_entre
			if resto >= construcao_min:
				fila.append(Rect2i(r.position.x, r.position.y + corte + espaco_entre, w, resto))

	return saida


func _colocar_construcao(bloco: Rect2i, quadra_rect: Rect2i) -> void:
	if bloco.size.x < construcao_min or bloco.size.y < construcao_min:
		return
	if not _area_livre(bloco) or not _area_valida(bloco):
		return

	var c := Construcao.new()

	# Forma: L, retangular ou quadrada
	var forma := _rng.randf()
	if forma < chance_forma_L and bloco.size.x >= construcao_min * 2 and bloco.size.y >= construcao_min * 2:
		c.caixas = _gerar_forma_L(bloco)
	elif forma < chance_forma_L + chance_retangular:
		c.caixas = [_ajustar_retangulo(bloco)]
	else:
		var lado := mini(mini(bloco.size.x, bloco.size.y), construcao_max)
		var ox := _rng.randi_range(0, maxi(bloco.size.x - lado, 0))
		var oz := _rng.randi_range(0, maxi(bloco.size.y - lado, 0))
		c.caixas = [Rect2i(bloco.position.x + ox, bloco.position.y + oz, lado, lado)]

	if c.caixas.is_empty():
		return

	var bb := c.caixas[0]
	var area_total := 0
	for k in c.caixas.size():
		bb = bb.merge(c.caixas[k])
		area_total += c.caixas[k].get_area()
	c.bbox = bb
	c.altura_base = _altura_minima(c.caixas)
	c.frente = _detectar_frente(bb, quadra_rect)
	c.semente = _rng.randi()

	# Casa ou predio
	var e_predio := _rng.randf() < chance_predio and area_total >= construcao_min * construcao_min * 2
	if e_predio:
		c.andares = _rng.randi_range(andares_predio_min, andares_predio_max)
	else:
		c.andares = _rng.randi_range(andares_casa_min, andares_casa_max)

	if coerencia_altura:
		c.andares = _aplicar_coerencia(c)

	# Cores / texturas
	if not cores_parede.is_empty():
		c.cor_parede = cores_parede[_rng.randi() % cores_parede.size()]
	if not cores_telhado.is_empty():
		c.cor_telhado = cores_telhado[_rng.randi() % cores_telhado.size()]
	if not texturas_parede.is_empty():
		c.idx_textura_parede = _rng.randi() % texturas_parede.size()
	if not texturas_telhado.is_empty():
		c.idx_textura_telhado = _rng.randi() % texturas_telhado.size()

	for cx in c.caixas:
		_marcar_ocupado(cx)

	_construcoes.append(c)
	var chave := _chave_coer(c)
	if not _grade_coer.has(chave):
		_grade_coer[chave] = []
	(_grade_coer[chave] as Array).append(c)


# ---------------------------------------------------------------------------
# FORMAS
# ---------------------------------------------------------------------------
# L formado por DUAS CAIXAS QUE NAO SE SOBREPOEM:
#   - braco vertical: faixa de largura bw em toda a profundidade do bloco
#   - braco horizontal: o que sobra da largura, com altura bh, colado em cima ou embaixo
func _gerar_forma_L(bloco: Rect2i) -> Array[Rect2i]:
	var w := bloco.size.x
	var h := bloco.size.y
	var x0 := bloco.position.x
	var z0 := bloco.position.y

	if w < construcao_min * 2 or h < construcao_min * 2:
		return [_ajustar_retangulo(bloco)]

	var bw := _rng.randi_range(construcao_min, w - construcao_min)
	var bh := _rng.randi_range(construcao_min, h - construcao_min)
	var esquerda := _rng.randf() < 0.5
	var em_cima := _rng.randf() < 0.5

	var caixas: Array[Rect2i] = []
	var xv := x0 if esquerda else x0 + w - bw
	caixas.append(Rect2i(xv, z0, bw, h))

	var xh := x0 + bw if esquerda else x0
	var zh := z0 if em_cima else z0 + h - bh
	caixas.append(Rect2i(xh, zh, w - bw, bh))
	return caixas


func _ajustar_retangulo(bloco: Rect2i) -> Rect2i:
	var w := mini(bloco.size.x, construcao_max)
	var h := mini(bloco.size.y, construcao_max)
	if w > construcao_min + 1:
		w = _rng.randi_range(maxi(construcao_min, w - 3), w)
	if h > construcao_min + 1:
		h = _rng.randi_range(maxi(construcao_min, h - 3), h)
	var ox := _rng.randi_range(0, maxi(bloco.size.x - w, 0))
	var oz := _rng.randi_range(0, maxi(bloco.size.y - h, 0))
	return Rect2i(bloco.position.x + ox, bloco.position.y + oz, w, h)


# ---------------------------------------------------------------------------
# COERENCIA DE ALTURA (grade espacial: so olha as celulas vizinhas)
# ---------------------------------------------------------------------------
func _chave_coer(c: Construcao) -> Vector2i:
	return Vector2i(Vector2(c.bbox.get_center()) / float(raio_coerencia))


func _aplicar_coerencia(c: Construcao) -> int:
	var centro := Vector2(c.bbox.get_center())
	var base := _chave_coer(c)
	var soma := 0.0
	var peso_total := 0.0

	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var chave := base + Vector2i(dx, dz)
			if not _grade_coer.has(chave):
				continue
			for outra in _grade_coer[chave]:
				var dist := centro.distance_to(Vector2(outra.bbox.get_center()))
				if dist < raio_coerencia:
					var peso := 1.0 - (dist / raio_coerencia)
					soma += outra.andares * peso
					peso_total += peso

	if peso_total < 0.01:
		return c.andares

	var alvo := lerpf(float(c.andares), soma / peso_total, forca_coerencia)
	return clampi(roundi(alvo), andares_casa_min, andares_predio_max)


# ---------------------------------------------------------------------------
# FRENTE: lado cuja borda da quadra encosta mais em rua/calcada
# ---------------------------------------------------------------------------
func _detectar_frente(bb: Rect2i, q: Rect2i) -> Vector2i:
	var melhor := Vector2i.ZERO
	var melhor_n := -1
	var melhor_gap := 1 << 20

	for d in 4:
		var dv: Vector2i = DIRS[d]
		var n := 0
		var gap := 0
		if dv.x != 0:
			var borda_c := bb.end.x if dv.x > 0 else bb.position.x
			var borda_q := q.end.x if dv.x > 0 else q.position.x
			gap = absi(borda_q - borda_c)
			var x := borda_q if dv.x > 0 else borda_q - 1
			for z in range(bb.position.y, bb.end.y):
				if _e_via(x, z):
					n += 1
		else:
			var borda_c := bb.end.y if dv.y > 0 else bb.position.y
			var borda_q := q.end.y if dv.y > 0 else q.position.y
			gap = absi(borda_q - borda_c)
			var z := borda_q if dv.y > 0 else borda_q - 1
			for x in range(bb.position.x, bb.end.x):
				if _e_via(x, z):
					n += 1
		if n > melhor_n or (n == melhor_n and gap < melhor_gap):
			melhor_n = n
			melhor_gap = gap
			melhor = dv
	return melhor


func _e_via(x: int, z: int) -> bool:
	if x < 0 or z < 0 or x >= _larg or z >= _prof:
		return false
	var t := _tipos[x * _prof + z]
	return t == T_RUA or t == T_CALCADA or t == T_PONTE


func _porta_voltada_para_via(c: Construcao) -> bool:
	var dv := c.frente
	if dv == Vector2i.ZERO:
		return false
	if dv.x != 0:
		var x := c.bbox.end.x if dv.x > 0 else c.bbox.position.x - 1
		for z in range(c.bbox.position.y, c.bbox.end.y):
			if _e_via(x, z):
				return true
	else:
		var z := c.bbox.end.y if dv.y > 0 else c.bbox.position.y - 1
		for x in range(c.bbox.position.x, c.bbox.end.x):
			if _e_via(x, z):
				return true
	return false


func _criar_sinal_abrigo(pos: Vector3, normal: Vector3) -> void:
	var s := Global.tamanho_cubo
	var no := Node3D.new()
	no.name = "AbrigoSign"
	# No plano da parede, acima da porta, levemente afastado para evitar z-fighting.
	no.position = pos + normal * 0.03 + Vector3(0.0, porta_altura * s * 0.5 + 0.3, 0.0)

	var tex: Texture2D = sprite_abrigo
	if tex == null:
		var img := Image.create(128, 32, false, Image.FORMAT_RGBA8)
		img.fill(cor_abrigo_parede)
		tex = ImageTexture.create_from_image(img)

	var sprite := Sprite3D.new()
	sprite.texture = tex
	sprite.pixel_size = tamanho_sprite_abrigo
	# Sem billboard: fica fixo no plano da parede.
	sprite.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	no.add_child(sprite)

	var label := Label3D.new()
	label.text = texto_abrigo
	label.font_size = 48
	label.modulate = Color.BLACK
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	label.position = Vector3(0.0, 0.0, 0.03)
	no.add_child(label)

	if is_instance_valid(_raiz):
		_raiz.add_child(no)


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
			if _tipos[x * _prof + z] != T_QUADRA:
				return false
	return true


func _marcar_ocupado(r: Rect2i) -> void:
	for x in range(r.position.x, r.end.x):
		for z in range(r.position.y, r.end.y):
			if x >= 0 and z >= 0 and x < _larg and z < _prof:
				_ocupado[x * _prof + z] = 1


# Menor altura do terreno sob as caixas: a parede comeca ali e nunca sobra buraco.
func _altura_minima(caixas: Array[Rect2i]) -> int:
	var menor := 1 << 20
	for r in caixas:
		for x in range(r.position.x, r.end.x):
			for z in range(r.position.y, r.end.y):
				if x >= 0 and z >= 0 and x < _larg and z < _prof:
					menor = mini(menor, _mapa[x * _prof + z])
	if menor == 1 << 20:
		return 1
	return menor


# ---------------------------------------------------------------------------
# GEOMETRIA DE UMA CONSTRUCAO (pode rodar em thread: so usa dados locais)
# ---------------------------------------------------------------------------
func _gerar_geometria(c: Construcao, paredes: Dictionary, telhados: Dictionary, sprites: Dictionary) -> void:
	var s: float = Global.tamanho_cubo
	var altura_total: float = c.andares * blocos_por_andar * s
	var base_y: float = c.altura_base * s
	var topo_y: float = base_y + altura_total

	var cor_p: Color = Color.WHITE if c.idx_textura_parede >= 0 else c.cor_parede.srgb_to_linear()
	var cor_t: Color = Color.WHITE if c.idx_textura_telhado >= 0 else c.cor_telhado.srgb_to_linear()
	var ap := _acum(paredes, c.idx_textura_parede)
	var at := _acum(telhados, c.idx_textura_telhado)

	# Telhados (caixas nao se sobrepoem, entao nao ha z-fighting)
	for caixa in c.caixas:
		at.quad(
			Vector3(caixa.position.x * s, topo_y, caixa.position.y * s),
			Vector3(caixa.size.x * s, 0.0, 0.0),
			Vector3(0.0, 0.0, caixa.size.y * s),
			Vector3.UP, caixa.size.x, caixa.size.y, cor_t, false)

	# Paredes: so os trechos expostos (sem a parte que encosta em outra caixa)
	var segs: Array[Dictionary] = []
	for caixa in c.caixas:
		_segmentos_da_caixa(c, caixa, base_y, s, segs)

	for seg in segs:
		var comp: float = seg["comp"]
		ap.quad(seg["origem"], (seg["ao_longo"] as Vector3) * comp, Vector3(0.0, altura_total, 0.0),
			seg["normal"], comp / s, altura_total / s, cor_p, true)

	# Escolhe o trecho da porta: preferencia para a frente, depois o mais longo
	var minimo_porta := (porta_largura + margem_borda_sprite * 2.0) * s
	var seg_porta := -1
	var melhor_nota := -1.0
	for i in segs.size():
		var comp: float = segs[i]["comp"]
		if comp < minimo_porta:
			continue
		var nota := comp
		if (segs[i]["dir"] as Vector2i) == c.frente:
			nota += 1000.0
		if nota > melhor_nota:
			melhor_nota = nota
			seg_porta = i

	# Registra a posicao da porta (se houver) para uso como abrigo/interacao.
	if seg_porta >= 0:
		c.tem_porta = true
		var segp: Dictionary = segs[seg_porta]
		var compp: float = segp["comp"]
		var pwp: float = porta_largura * s
		var up: float = (compp - pwp) * 0.5
		var origem_p: Vector3 = segp["origem"]
		var ao_p: Vector3 = segp["ao_longo"]
		c.porta_mundo = origem_p + ao_p * (up + pwp * 0.5) + Vector3(0.0, 1.0, 0.0)

	var rng := RandomNumberGenerator.new()
	rng.seed = c.semente
	for i in segs.size():
		_decorar_segmento(segs[i], i == seg_porta, c.andares, rng, sprites, s)


# Trechos de parede expostos de uma caixa. Cada trecho:
# origem (ponto inicial no chao), ao_longo (unitario, esquerda->direita visto de fora),
# normal, comp (comprimento no mundo), dir (direcao da face).
func _segmentos_da_caixa(c: Construcao, caixa: Rect2i, base_y: float, s: float, saida: Array[Dictionary]) -> void:
	for d in 4:
		var dv: Vector2i = DIRS[d]
		var normal := Vector3(dv.x, 0.0, dv.y)
		var ao_longo := Vector3.UP.cross(normal)   # direita de quem olha a parede de fora
		var corre_em_z := dv.x != 0
		var a_ini := caixa.position.y if corre_em_z else caixa.position.x
		var a_fim := caixa.end.y if corre_em_z else caixa.end.x
		var ini := -1

		for k in range(a_ini, a_fim + 1):
			var exposto := false
			if k < a_fim:
				var vx := k
				var vz := k
				if corre_em_z:
					vx = caixa.end.x if dv.x > 0 else caixa.position.x - 1
				else:
					vz = caixa.end.y if dv.y > 0 else caixa.position.y - 1
				exposto = not _cel_na_construcao(c, vx, vz)

			if exposto:
				if ini < 0:
					ini = k
			elif ini >= 0:
				var origem: Vector3
				if corre_em_z:
					var xf: float = (caixa.end.x if dv.x > 0 else caixa.position.x) * s
					var zs: float = (ini if ao_longo.z > 0.0 else k) * s
					origem = Vector3(xf, base_y, zs)
				else:
					var zf: float = (caixa.end.y if dv.y > 0 else caixa.position.y) * s
					var xs: float = (ini if ao_longo.x > 0.0 else k) * s
					origem = Vector3(xs, base_y, zf)
				saida.append({
					"origem": origem,
					"ao_longo": ao_longo,
					"normal": normal,
					"comp": (k - ini) * s,
					"dir": dv,
				})
				ini = -1


func _cel_na_construcao(c: Construcao, x: int, z: int) -> bool:
	var p := Vector2i(x, z)
	for cx in c.caixas:
		if cx.has_point(p):
			return true
	return false


# ---------------------------------------------------------------------------
# DECORACOES (porta, janelas, detalhes) SEM SOBREPOSICAO
# ---------------------------------------------------------------------------
# Sistema de coordenadas da parede: u = ao longo (0..comp), y = altura (0..)
# `ocup` guarda os retangulos ja usados; todo sprite novo e testado contra ele.
func _decorar_segmento(seg: Dictionary, tem_porta: bool, andares: int,
		rng: RandomNumberGenerator, sprites: Dictionary, s: float) -> void:
	var comp: float = seg["comp"]
	var altura_andar := blocos_por_andar * s
	var margem := margem_borda_sprite * s
	var folga := folga_entre_sprites * s
	var ocup: Array[Rect2] = []

	# --- PORTA -----------------------------------------------------------------
	if tem_porta:
		var pw := porta_largura * s
		var ph := minf(porta_altura * s, altura_andar - 0.3 * s)
		var u := (comp - pw) * 0.5
		var idx := _escolher_idx(_idx_portas, rng)
		var cor := Color.WHITE if idx >= 0 else _cor_porta.srgb_to_linear()
		_sprite(sprites, seg, idx, cor, u, 0.0, pw, ph)
		ocup.append(Rect2(u, 0.0, pw, ph).grow(folga))

	# --- JANELAS (grade regular; pula o que colidir com algo) -------------------
	var jw := janela_largura * s
	var jh := janela_altura * s
	var util := comp - margem * 2.0
	var n := 0
	if util >= jw:
		n = mini(floori(util / (janela_espacamento * s)), floori(util / (jw + folga)))
	if n > 0:
		var passo := util / n
		for andar in andares:
			var y := andar * altura_andar + janela_offset_y * s
			y = minf(y, (andar + 1) * altura_andar - jh - 0.15 * s)
			y = maxf(y, andar * altura_andar + 0.1 * s)
			for j in n:
				var u := margem + (j + 0.5) * passo - jw * 0.5
				var r := Rect2(u, y, jw, jh)
				if _colide(ocup, r.grow(folga)):
					continue
				if rng.randf() > chance_janela:
					continue
				var idx := _escolher_idx(_idx_janelas, rng)
				var cor := Color.WHITE
				if idx < 0:
					cor = _cores_janela[rng.randi() % _cores_janela.size()].srgb_to_linear()
				_sprite(sprites, seg, idx, cor, u, y, jw, jh)
				ocup.append(r)

	# --- DETALHES EXTRAS (so em espaco livre) ----------------------------------
	var dw := detalhe_largura * s
	var dh := detalhe_altura * s
	if chance_detalhe > 0.0 and andares > 1 and detalhes_por_parede_max > 0 \
			and comp - margem * 2.0 > dw and altura_andar - dh > 0.4 * s:
		var colocados := 0
		for andar in range(1, andares):
			if colocados >= detalhes_por_parede_max:
				break
			if rng.randf() > chance_detalhe:
				continue
			for t in tentativas_detalhe:
				var u := rng.randf_range(margem, comp - margem - dw)
				var y := andar * altura_andar + rng.randf_range(0.2 * s, altura_andar - dh - 0.2 * s)
				var r := Rect2(u, y, dw, dh)
				if _colide(ocup, r.grow(folga)):
					continue
				var idx := _escolher_idx(_idx_detalhes, rng)
				var cor := Color.WHITE
				if idx < 0:
					cor = _cores_detalhe[rng.randi() % _cores_detalhe.size()].srgb_to_linear()
				_sprite(sprites, seg, idx, cor, u, y, dw, dh)
				ocup.append(r)
				colocados += 1
				break


func _colide(ocup: Array[Rect2], r: Rect2) -> bool:
	for o in ocup:
		if o.intersects(r):
			return true
	return false


func _escolher_idx(lista: Array[int], rng: RandomNumberGenerator) -> int:
	if lista.is_empty():
		return -1
	return lista[rng.randi() % lista.size()]


func _sprite(sprites: Dictionary, seg: Dictionary, idx_tex: int, cor: Color,
		u: float, y: float, largura: float, altura: float) -> void:
	var normal: Vector3 = seg["normal"]
	var ao_longo: Vector3 = seg["ao_longo"]
	var origem: Vector3 = seg["origem"]
	var p := origem + ao_longo * u + normal * recuo_sprite + Vector3(0.0, y, 0.0)
	_acum(sprites, idx_tex).quad(p, ao_longo * largura, Vector3(0.0, altura, 0.0),
		normal, 1.0, 1.0, cor, true)


func _acum(d: Dictionary, k: int) -> Acum:
	if not d.has(k):
		d[k] = Acum.new()
	return d[k]


# ---------------------------------------------------------------------------
# MATERIAIS (criados so na thread principal)
# ---------------------------------------------------------------------------
func _mat_predio(idx: int, telhado: bool) -> ShaderMaterial:
	var chave := idx * 2 + (1 if telhado else 0)
	if _mats_pred.has(chave):
		return _mats_pred[chave]

	var mat := ShaderMaterial.new()
	mat.shader = _shader_predio
	var tex: Texture2D = null
	if idx >= 0:
		var lista: Array[Texture2D] = texturas_telhado if telhado else texturas_parede
		if idx < lista.size():
			tex = lista[idx]
	if tex != null:
		mat.set_shader_parameter("textura_albedo", tex)
		mat.set_shader_parameter("usar_textura", true)
	else:
		mat.set_shader_parameter("usar_textura", false)

	_mats_pred[chave] = mat
	return mat


func _mat_sprite(idx: int) -> ShaderMaterial:
	if _mats_sprite.has(idx):
		return _mats_sprite[idx]

	var mat := ShaderMaterial.new()
	mat.shader = _shader_sprite
	if idx >= 0 and idx < _tex_sprites.size():
		mat.set_shader_parameter("textura", _tex_sprites[idx])
		mat.set_shader_parameter("usar_textura", true)
	else:
		mat.set_shader_parameter("usar_textura", false)

	_mats_sprite[idx] = mat
	return mat


# ---------------------------------------------------------------------------
# SPRITES: exports do usuario + placeholders (sem alterar os exports)
# ---------------------------------------------------------------------------
func _preparar_sprites() -> void:
	_tex_sprites.clear()
	_idx_portas.clear()
	_idx_janelas.clear()
	_idx_detalhes.clear()

	_adicionar_sprites(sprites_porta, _idx_portas)
	_adicionar_sprites(sprites_janela, _idx_janelas)
	_adicionar_sprites(sprites_detalhe, _idx_detalhes)

	if gerar_sprites_teste:
		if _idx_portas.is_empty():
			_idx_portas.append(_nova_tex(_criar_textura_porta()))
		if _idx_janelas.is_empty():
			_idx_janelas.append(_nova_tex(_criar_textura_janela_residencial()))
			_idx_janelas.append(_nova_tex(_criar_textura_janela_comercial()))
		if _idx_detalhes.is_empty():
			_idx_detalhes.append(_nova_tex(_criar_textura_ar_condicionado()))


func _adicionar_sprites(origem: Array[Texture2D], destino: Array[int]) -> void:
	for t in origem:
		if t != null:
			destino.append(_nova_tex(t))


func _nova_tex(t: Texture2D) -> int:
	_tex_sprites.append(t)
	return _tex_sprites.size() - 1


# ---------------------------------------------------------------------------
# TEXTURAS PLACEHOLDER (pixel art procedural)
# ---------------------------------------------------------------------------
func _finalizar(img: Image) -> ImageTexture:
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _criar_textura_porta() -> ImageTexture:
	var img := Image.create(16, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	# Moldura e fundo
	for x in 16:
		for y in 32:
			if x == 0 or x == 15 or y == 0:
				img.set_pixel(x, y, Color("3a2a1a"))
			elif x >= 1 and x <= 14 and y >= 1 and y <= 30:
				img.set_pixel(x, y, Color("6b4226"))
	# Paineis
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
	return _finalizar(img)


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
				img.set_pixel(x, y, Color("90c8e8"))
			elif x >= 9 and x <= 14 and y >= 1 and y <= 6:
				img.set_pixel(x, y, Color("88c0e0"))
			elif x >= 1 and x <= 6 and y >= 9 and y <= 14:
				img.set_pixel(x, y, Color("80b8d8"))
			elif x >= 9 and x <= 14 and y >= 9 and y <= 14:
				img.set_pixel(x, y, Color("78b0d0"))
	# Reflexo
	img.set_pixel(3, 3, Color("b0e0f8"))
	img.set_pixel(4, 3, Color("a8d8f0"))
	img.set_pixel(3, 4, Color("a8d8f0"))
	return _finalizar(img)


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
				img.set_pixel(x, y, Color("406888"))  # vidro fume
	img.set_pixel(2, 2, Color("6090b0"))
	img.set_pixel(3, 2, Color("5888a8"))
	img.set_pixel(2, 3, Color("5888a8"))
	img.set_pixel(3, 3, Color("5080a0"))
	return _finalizar(img)


func _criar_textura_ar_condicionado() -> ImageTexture:
	var img := Image.create(16, 12, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	for x in 16:
		for y in 12:
			if x == 0 or x == 15 or y == 0 or y == 11:
				img.set_pixel(x, y, Color("989898"))  # borda
			elif y >= 2 and y <= 9:
				if x % 2 == 0:
					img.set_pixel(x, y, Color("787878"))  # grade
				else:
					img.set_pixel(x, y, Color("b8b8b8"))
			else:
				img.set_pixel(x, y, Color("c0c0c0"))  # corpo
	img.set_pixel(7, 1, Color("4080a0"))
	img.set_pixel(8, 1, Color("4080a0"))
	return _finalizar(img)
