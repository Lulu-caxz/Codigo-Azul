
extends Node2D

const PROJECT_REF: String = "ovkvgnnsxmpymcjclnzo"
const SUPABASE_KEY: String = "sb_publishable_3FDWeQxz2a8wEO-se44m-w_guLkTpR5"

const MAP_WIDTH: int = 320
const MAP_HEIGHT: int = 180
const TILE_SIZE: int = 3

const SONAR_SHADER = preload("res://shaders/sonar.gdshader")

const TEXTURA_JOGADOR: Texture2D = preload("res://assets/pin-player.png")

@onready var http: HTTPRequest = $HTTPRequest

var mapa: Array = []
var textura_mapa: ImageTexture
@export var posicao_mapa: Vector2 = Vector2.ZERO

var marcador_jogador: Sprite2D

var cores: Array[Color] = [
	Color.CORNFLOWER_BLUE,  # 0 - Água
	Color.SANDY_BROWN,      # 1 - Areia
	Color.FOREST_GREEN,     # 2 - Grama
	Color.DARK_GRAY,        # 3 - Pedra
	Color("4a4a50"),        # 4 - Rua
	Color("8b6b4a"),        # 5 - Ponte
	Color("b0a898"),        # 6 - Calçada
	Color("a09888")         # 7 - Quadra
]


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	var material_sonar := ShaderMaterial.new()
	material_sonar.shader = SONAR_SHADER

	material_sonar.set_shader_parameter(
		"proporcao",
		float(MAP_WIDTH) / float(MAP_HEIGHT)
	)

	material = material_sonar

	await carregar_mapa()
	
	_criar_marcador_jogador()
	_configurar_ui()

	var central := get_tree().current_scene.find_child(
		"CentralSync",
		true,
		false
	)

	if central == null:
		push_error("Mapa: nó CentralSync não encontrado.")
	else:
		central.dados_sala_atualizados.connect(
			_ao_dados_sala_atualizados
		)
		central.timer_atualizado.connect(
			_ao_timer_atualizado
		)

		print("Mapa: conectado ao CentralSync.")

	# Evita mostrar 60s iniciais antes da primeira sincronizacao.
	var visor_label := get_node_or_null("UI/Visor/Label")
	if visor_label != null:
		visor_label.text = "--"


func carregar_mapa() -> void:
	if Global.salaID.is_empty():
		push_error("O ID da sala não foi definido.")
		return

	var url: String = (
		"https://%s.supabase.co/rest/v1/salas" % PROJECT_REF
		+ "?id=eq." + Global.salaID.uri_encode()
		+ "&select=mapa"
	)

	var headers := PackedStringArray([
		"apikey: " + SUPABASE_KEY,
		"Authorization: Bearer " + SUPABASE_KEY,
		"Accept: application/json"
	])

	var erro := http.request(
		url,
		headers,
		HTTPClient.METHOD_GET
	)

	if erro != OK:
		push_error("Não foi possível solicitar o mapa.")
		return

	var resposta = await http.request_completed

	var resultado: int = resposta[0]
	var codigo_http: int = resposta[1]
	var texto: String = resposta[3].get_string_from_utf8()

	if resultado != HTTPRequest.RESULT_SUCCESS:
		push_error("Falha de conexão ao buscar o mapa.")
		return

	if codigo_http < 200 or codigo_http >= 300:
		push_error("Erro HTTP ao buscar mapa: " + str(codigo_http))
		print(texto)
		return

	var dados = JSON.parse_string(texto)

	if not dados is Array or dados.is_empty():
		push_error("Nenhuma sala encontrada no banco de dados.")
		return

	mapa = dados[0].get("mapa", [])

	if not mapa is Array:
		push_error("O campo mapa não é um array.")
		return

	if mapa.size() != MAP_WIDTH * MAP_HEIGHT:
		push_error(
			"Quantidade incorreta de blocos: "
			+ str(mapa.size())
			+ ". Esperado: "
			+ str(MAP_WIDTH * MAP_HEIGHT)
		)
		await get_tree().create_timer(1.0).timeout
		carregar_mapa()
		return

	construir_mapa()


func construir_mapa() -> void:
	var imagem := Image.create(
		MAP_WIDTH,
		MAP_HEIGHT,
		false,
		Image.FORMAT_RGBA8
	)

	for x in range(MAP_WIDTH):
		for y in range(MAP_HEIGHT):
			# Preserva a ordem usada pelo gerador:
			# índice = x * profundidade + z
			var indice: int = x * MAP_HEIGHT + y
			var valor: int = int(mapa[indice])
			
			if valor == 7 or valor == 1:
				imagem.set_pixel(x, y, cor_do_bloco(2))
			else:
				imagem.set_pixel(x, y, cor_do_bloco(valor))

	textura_mapa = ImageTexture.create_from_image(imagem)

	queue_redraw()

	print("Mapa 2D carregado: ", MAP_WIDTH, " x ", MAP_HEIGHT)


func cor_do_bloco(valor: int) -> Color:
	if valor >= 0 and valor < cores.size():
		return cores[valor]

	return Color.MAGENTA


func _draw() -> void:
	if textura_mapa == null:
		return

	var tamanho := Vector2(
		MAP_WIDTH * TILE_SIZE,
		MAP_HEIGHT * TILE_SIZE
	)

	draw_texture_rect(
		textura_mapa,
		Rect2(posicao_mapa, tamanho),
		false
	)

func _criar_marcador_jogador() -> void:
	marcador_jogador = Sprite2D.new()
	marcador_jogador.name = "MarcadorJogador"
	marcador_jogador.texture = TEXTURA_JOGADOR
	marcador_jogador.z_index = 20
	marcador_jogador.use_parent_material = false
	marcador_jogador.visible = false

	# Ajuste o tamanho da imagem no mapa.
	marcador_jogador.scale = Vector2(1.5, 1.5)

	add_child(marcador_jogador)


func _ao_dados_sala_atualizados(
	posicao: Vector3,
	_pontos: Array
) -> void:
	var posicao_mapaa := Vector2(
		posicao.x,
		posicao.z
	) / 1.0 * TILE_SIZE

	marcador_jogador.position = posicao_mapaa + posicao_mapa
	marcador_jogador.visible = true


func _ao_timer_atualizado(segundos: int, iniciado: bool) -> void:
	var visor_label := get_node_or_null("UI/Visor/Label")
	if visor_label == null:
		return
	if not iniciado:
		visor_label.text = "%ds" % segundos
	else:
		visor_label.text = "%02d:%02d" % [segundos / 60, segundos % 60]


func _configurar_ui() -> void:
	# Botao gerador: troca para o sprite "pressionado".
	var gerador := get_node_or_null("UI/Gerador") as Button
	if gerador != null:
		var tex_normal := AtlasTexture.new()
		tex_normal.atlas = preload("res://assets/central/botao_gerador.png")
		tex_normal.region = Rect2(0, 0, 103, 34)
		var tex_pressed := AtlasTexture.new()
		tex_pressed.atlas = preload("res://assets/central/botao_gerador.png")
		tex_pressed.region = Rect2(103, 0, 103, 34)
		gerador.icon = tex_normal
		gerador.button_down.connect(func():
			gerador.icon = tex_pressed
			_tocar_som_ui("res://sounds/clicar.mp3")
		)
		gerador.button_up.connect(func(): gerador.icon = tex_normal)

	# Post-its: hover move para a direita; clique abre ampliado.
	var postits := get_node_or_null("UI/PostIts")
	if postits != null:
		for p in postits.get_children():
			_configurar_postit(p)

	# Popup de post-it ampliado.
	_popup_postit = PanelContainer.new()
	_popup_postit.visible = false
	_popup_postit.position = Vector2(300, 200)
	_popup_postit.custom_minimum_size = Vector2(200, 120)
	var label := Label.new()
	label.name = "Texto"
	label.text = "Texto do post-it"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_popup_postit.add_child(label)
	add_child(_popup_postit)


func _configurar_postit(p: Node) -> void:
	var ctrl := p as Control
	if ctrl == null:
		return
	ctrl.mouse_filter = Control.MOUSE_FILTER_STOP
	# Ajusta a area clicavel para cobrir o sprite.
	ctrl.custom_minimum_size = Vector2(54, 34)
	ctrl.size = Vector2(54, 34)

	var original_pos: Vector2 = ctrl.position
	var tween: Tween

	ctrl.mouse_entered.connect(func():
		if tween and tween.is_valid():
			tween.kill()
		tween = create_tween()
		tween.tween_property(ctrl, "position", original_pos + Vector2(8, 0), 0.05)
		_tocar_som_ui("res://sounds/hover.mp3")
	)
	ctrl.mouse_exited.connect(func():
		if tween and tween.is_valid():
			tween.kill()
		tween = create_tween()
		tween.tween_property(ctrl, "position", original_pos, 0.05)
	)
	ctrl.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var idx := 0
			var sprite := ctrl.get_node_or_null("Sprite2D") as Sprite2D
			if sprite != null and sprite.texture is AtlasTexture:
				var at := sprite.texture as AtlasTexture
				idx = int(at.region.position.x / 54.0)
			_abrir_postit(idx)
	)


var _popup_postit: PanelContainer
var _postit_aberto: Node2D
var _ignorar_clique_postit: bool = false
var _som_ui: AudioStreamPlayer


func _tocar_som_ui(caminho: String) -> void:
	if _som_ui == null:
		_som_ui = AudioStreamPlayer.new()
		add_child(_som_ui)
	var s := load(caminho)
	if s is AudioStream:
		_som_ui.stream = s
		_som_ui.play()


func _abrir_postit(idx: int) -> void:
	if _postit_aberto != null:
		_postit_aberto.queue_free()
		_postit_aberto = null

	var cena := preload("res://scenes/central/post_it_aberto.tscn")
	var no := cena.instantiate() as Node2D
	if no == null:
		return

	var sprite := no.get_node_or_null("Sprite2D") as Sprite2D
	if sprite != null:
		var tex := AtlasTexture.new()
		tex.atlas = preload("res://assets/central/postIt_aberto.png")
		tex.region = Rect2(idx * 52, 0, 52, 33)
		sprite.texture = tex


	no.position = get_viewport_rect().size * 0.5
	no.z_index = 100
	add_child(no)
	_postit_aberto = no
	_ignorar_clique_postit = true
	_tocar_som_ui("res://sounds/abrirPostIt.mp3")


func _input(event: InputEvent) -> void:
	if _postit_aberto == null:
		return
	if _ignorar_clique_postit:
		_ignorar_clique_postit = false
		return
	if event is InputEventMouseButton and event.pressed:
		_postit_aberto.queue_free()
		_postit_aberto = null


func _process(_delta: float) -> void:
	# Atualiza a barra de vida conforme Global.vidas.
	var barra := get_node_or_null("UI/BarraDeVida") as AnimatedSprite2D
	if barra != null:
		var v := clampi(Global.vidas, 0, 5)
		barra.animation = str(v)
