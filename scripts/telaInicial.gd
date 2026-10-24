extends Control

signal solicitou_entrada(sala_id: String, papel: String)

const PROJECT_REF: String = "ovkvgnnsxmpymcjclnzo"
const SUPABASE_KEY: String = "sb_publishable_3FDWeQxz2a8wEO-se44m-w_guLkTpR5"

const FONTE: FontFile = preload("res://fonts/ByteBounce-PT-BR.ttf")
const TEXTURA_PLACA: Texture2D = preload("res://assets/minigames/bueiro/PlacaEscoamento.png")
const TEXTURA_ADA: Texture2D = preload("res://assets/players/AdaFrente.png")
const TEXTURA_GRACE: Texture2D = preload("res://assets/players/GraceFrente.png")

@onready var http: HTTPRequest = $HTTPRequestSalas
@onready var lista_salas: VBoxContainer = $VBoxContainer/ScrollContainer/ListaSalas
@onready var botao_criar_sala: Button = $Control/NinePatchRect2/BotaoCriarSala
@onready var botao_atualizar_sala = $VBoxContainer/AtualizarSalas
@onready var criador_sala = $Control/CriarSala
@onready var nome_sala_input = $Control/NinePatchRect/LineEdit
@onready var botao_tutorial: Button = $Control/NinePatchRect3/BotaoTutorial
@onready var _som_ui: AudioStreamPlayer

var salas_carregadas: Array = []
var criando_sala: bool = false


func _ready() -> void:
	http.request_completed.connect(_ao_receber_salas)
	botao_criar_sala.pressed.connect(_ao_clicar_criar_sala)
	botao_criar_sala.mouse_entered.connect(func():
		_tocar_som_ui("res://sounds/hover.mp3")
		_ao_mouse_entrou_criar_sala()
	)
	botao_criar_sala.mouse_exited.connect(func():
		_ao_mouse_saiu_criar_sala()
	)
	botao_atualizar_sala.pressed.connect(_on_botao_atualizar_pressed)
	criador_sala.sala_criada.connect(_ao_sala_criada)
	criador_sala.erro_ao_criar.connect(_ao_erro_criar_sala)
	botao_tutorial.pressed.connect(_ao_clicar_tutorial)
	botao_tutorial.mouse_entered.connect(func():
		_tocar_som_ui("res://sounds/hover.mp3")
	)
	atualizar_salas()

	nome_sala_input.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


func atualizar_salas() -> void:
	var url: String = (
        "https://%s.supabase.co/rest/v1/salas"
		+ "?select=id,nome,jogador_f_id,jogador_c_id,iniciado,criada_em"
		+ "&order=criada_em.desc"
	) % PROJECT_REF

	var headers := PackedStringArray([
		"apikey: " + SUPABASE_KEY,
		"Authorization: Bearer " + SUPABASE_KEY
	])

	var erro: Error = http.request(
		url,
		headers,
		HTTPClient.METHOD_GET
	)

	if erro != OK:
		push_error("Não foi possível consultar as salas: %s" % erro)


func _ao_receber_salas(
	resultado: int,
	codigo_http: int,
	_cabecalhos: PackedStringArray,
	corpo: PackedByteArray
) -> void:

	var texto: String = corpo.get_string_from_utf8()

	if resultado != HTTPRequest.RESULT_SUCCESS:
		push_error("Falha na conexão com o Supabase.")
		return

	if codigo_http < 200 or codigo_http >= 300:
		push_error("Erro HTTP: " + str(codigo_http))
		return

	var resposta = JSON.parse_string(texto)

	if not resposta is Array:
		push_error("A resposta não é uma lista de salas.")
		return

	salas_carregadas = resposta

	mostrar_salas()


func mostrar_salas() -> void:
	for filho in lista_salas.get_children():
		filho.queue_free()

	for sala in salas_carregadas:
		# Sala com os dois jogadores nao deve mais aparecer na lista.
		if _sala_cheia(sala):
			continue
		criar_card_sala(sala)


func _sala_cheia(sala: Dictionary) -> bool:
	var jogador_f_ocupado: bool = (
		sala.get("jogador_f_id") != null
		and not str(sala.get("jogador_f_id", "")).is_empty()
	)

	var jogador_c_ocupado: bool = (
		sala.get("jogador_c_id") != null
		and not str(sala.get("jogador_c_id", "")).is_empty()
	)

	return jogador_f_ocupado and jogador_c_ocupado



func criar_card_sala(sala: Dictionary) -> void:
	var card := NinePatchRect.new()
	card.texture = TEXTURA_PLACA
	card.patch_margin_left = 5
	card.patch_margin_top = 5
	card.patch_margin_right = 5
	card.patch_margin_bottom = 5
	card.custom_minimum_size = Vector2(300, 200)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Padding interno, ocupando todo o card
	var margem := MarginContainer.new()
	margem.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margem.add_theme_constant_override("margin_left", 14)
	margem.add_theme_constant_override("margin_right", 14)
	margem.add_theme_constant_override("margin_top", 8)
	margem.add_theme_constant_override("margin_bottom", 8)
	card.add_child(margem)

	# Conteúdo ocupa toda a área interna
	var conteudo := VBoxContainer.new()
	conteudo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	conteudo.size_flags_vertical = Control.SIZE_EXPAND_FILL
	conteudo.alignment = BoxContainer.ALIGNMENT_CENTER
	conteudo.add_theme_constant_override("separation", 4)
	margem.add_child(conteudo)

	# Título centralizado na largura inteira
	var titulo := Label.new()
	titulo.text = str(sala.get("nome", "Sala sem nome"))
	titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	titulo.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	titulo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titulo.add_theme_font_override("font", FONTE)
	titulo.add_theme_font_size_override("font_size", 55)
	titulo.add_theme_color_override(
		"font_color",
		Color(0.4117647, 0.41568628, 0.41568628, 1)
	)
	conteudo.add_child(titulo)

	# Linha dos jogadores centralizada
	var linha := HBoxContainer.new()
	linha.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	linha.size_flags_vertical = Control.SIZE_EXPAND_FILL
	linha.alignment = BoxContainer.ALIGNMENT_CENTER
	linha.add_theme_constant_override("separation", 24)
	conteudo.add_child(linha)

	var jogador_f_ocupado: bool = (
		sala.get("jogador_f_id") != null
		and not str(sala.get("jogador_f_id", "")).is_empty()
	)

	var jogador_c_ocupado: bool = (
		sala.get("jogador_c_id") != null
		and not str(sala.get("jogador_c_id", "")).is_empty()
	)

	var sala_iniciada: bool = sala.get("iniciado", false)

		# Botão da Ada — CIDADE
	var tex_ada_top := AtlasTexture.new()
	tex_ada_top.atlas = TEXTURA_ADA
	tex_ada_top.region = Rect2(0, 6, 48, 24)

	var botao_f := Button.new()
	botao_f.custom_minimum_size = Vector2(400, 80)
	botao_f.icon = tex_ada_top
	botao_f.expand_icon = true
	botao_f.text = "CIDADE"
	botao_f.alignment = HORIZONTAL_ALIGNMENT_CENTER
	botao_f.add_theme_font_override("font", FONTE)
	botao_f.add_theme_font_size_override("font_size", 48)
	botao_f.add_theme_color_override(
		"font_color",
		Color(0.4117647, 0.41568628, 0.41568628, 1)
	)
	botao_f.disabled = jogador_f_ocupado or sala_iniciada
	botao_f.pressed.connect(
		func(): _ao_clicar_entrar(str(sala.get("id", "")), "F")
	)
	linha.add_child(botao_f)

	# Botão da Grace — CENTRAL
	var tex_grace_top := AtlasTexture.new()
	tex_grace_top.atlas = TEXTURA_GRACE
	tex_grace_top.region = Rect2(0, 6, 48, 24)

	var botao_c := Button.new()
	botao_c.custom_minimum_size = Vector2(400, 80)
	botao_c.icon = tex_grace_top
	botao_c.expand_icon = true
	botao_c.text = "CENTRAL"
	botao_c.alignment = HORIZONTAL_ALIGNMENT_CENTER
	botao_c.add_theme_font_override("font", FONTE)
	botao_c.add_theme_font_size_override("font_size", 48)
	botao_c.add_theme_color_override(
		"font_color",
		Color(0.4117647, 0.41568628, 0.41568628, 1)
	)
	botao_c.disabled = jogador_c_ocupado or sala_iniciada
	botao_c.pressed.connect(
		func(): _ao_clicar_entrar(str(sala.get("id", "")), "C")
	)
	linha.add_child(botao_c)

	lista_salas.add_child(card)


func _ao_clicar_entrar(id_sala: String, papel: String) -> void:
	print("Solicitando entrada na sala: ", id_sala)
	print("Papel escolhido: Player ", papel)

	var sucesso: bool = await criador_sala.entrar_na_sala(
		id_sala,
		papel
	)

	if not sucesso:
		push_error("Não foi possível entrar na sala.")
		atualizar_salas()
		return

	# Só define a sala depois de confirmar a entrada.
	Global.salaID = id_sala
	Global.funcao = papel

	solicitou_entrada.emit(id_sala, papel)

	var cena := get_tree().change_scene_to_file(
		"res://scenes/SalaDeEspera.tscn"
	)

	if cena != OK:
		push_error("Erro ao trocar de cena: " + str(cena))

func _ao_clicar_criar_sala() -> void:
	criando_sala = true
	botao_criar_sala.modulate = Color(0.223, 0.223, 0.223, 1.0)
	if nome_sala_input.text == "":
		criador_sala.criar_sala("Nova sala")
	else:
		criador_sala.criar_sala(nome_sala_input.text)


func _ao_sala_criada() -> void:
	criando_sala = false
	botao_criar_sala.modulate = Color.WHITE
	atualizar_salas()


func _ao_erro_criar_sala(_mensagem: String) -> void:
	criando_sala = false
	botao_criar_sala.modulate = Color.WHITE


func _ao_mouse_entrou_criar_sala() -> void:
	if not criando_sala:
		botao_criar_sala.modulate = Color(0.6, 0.6, 0.6, 1.0)


func _ao_mouse_saiu_criar_sala() -> void:
	if not criando_sala:
		botao_criar_sala.modulate = Color.WHITE

func _tocar_som_ui(caminho: String) -> void:
	if _som_ui == null:
		_som_ui = AudioStreamPlayer.new()
		add_child(_som_ui)
	var s := load(caminho)
	if s is AudioStream:
		_som_ui.stream = s
		_som_ui.play()


func _ao_clicar_tutorial() -> void:
	_tocar_som_ui("res://sounds/clicar.mp3")
	await Transicao.mudar_cena("res://scenes/tutorial.tscn", 0.8)


func _on_botao_atualizar_pressed() -> void:
	atualizar_salas()
