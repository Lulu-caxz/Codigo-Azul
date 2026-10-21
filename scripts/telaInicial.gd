extends Control

signal solicitou_entrada(sala_id: String, papel: String)

const PROJECT_REF: String = "ovkvgnnsxmpymcjclnzo"
const SUPABASE_KEY: String = "sb_publishable_3FDWeQxz2a8wEO-se44m-w_guLkTpR5"

@onready var http: HTTPRequest = $HTTPRequestSalas
@onready var lista_salas: VBoxContainer = $VBoxContainer/ScrollContainer/ListaSalas
@onready var botao_criar_sala: Button = $Control/BotaoCriarSala
@onready var botao_atualizar_sala = $VBoxContainer/AtualizarSalas
@onready var criador_sala = $Control/CriarSala
@onready var nome_sala_input = $Control/LineEdit

var salas_carregadas: Array = []


func _ready() -> void:
	http.request_completed.connect(_ao_receber_salas)
	botao_criar_sala.pressed.connect(_ao_clicar_criar_sala)
	botao_atualizar_sala.pressed.connect(_on_botao_atualizar_pressed)
	atualizar_salas()


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
		criar_card_sala(sala)

func criar_card_sala(sala: Dictionary) -> void:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(300, 90)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var conteudo := VBoxContainer.new()
	conteudo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_child(conteudo)

	var titulo := Label.new()
	titulo.text = str(sala.get("nome", "Sala sem nome"))
	titulo.add_theme_font_size_override("font_size", 34)
	conteudo.add_child(titulo)

	var linha := HBoxContainer.new()
	linha.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	conteudo.add_child(linha)

	var jogador_f_ocupado: bool = (
		not str(sala.get("jogador_f_id", "")).is_empty()
		and sala.get("jogador_f_id") != null
	)

	var jogador_c_ocupado: bool = (
		not str(sala.get("jogador_c_id", "")).is_empty()
		and sala.get("jogador_c_id") != null
	)

	var sala_iniciada: bool = sala.get("iniciado", false)

	var botao_f := Button.new()
	botao_f.text = "Player F"
	botao_f.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	botao_f.add_theme_font_size_override("font_size", 34)
	botao_f.disabled = jogador_f_ocupado or sala_iniciada
	botao_f.pressed.connect(
		func(): _ao_clicar_entrar(str(sala.get("id", "")), "F")
	)
	linha.add_child(botao_f)

	var botao_c := Button.new()
	botao_c.text = "Player C"
	botao_c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	botao_c.add_theme_font_size_override("font_size", 34)
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
	criador_sala.sala_criada.connect(_on_botao_atualizar_pressed)
	if nome_sala_input.text == "":
		criador_sala.criar_sala("Nova sala")
	else:
		criador_sala.criar_sala(nome_sala_input.text)

func _on_botao_atualizar_pressed() -> void:
	atualizar_salas()
