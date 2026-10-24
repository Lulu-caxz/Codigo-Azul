extends Node2D

const PROJECT_REF: String = "ovkvgnnsxmpymcjclnzo"
const SUPABASE_KEY: String = "sb_publishable_3FDWeQxz2a8wEO-se44m-w_guLkTpR5"

const FONTE: FontFile = preload("res://fonts/ByteBounce-PT-BR.ttf")
const COR_TEXTO := Color(0.4117647, 0.41568628, 0.41568628, 1)

const LARGURA_POSICAO := 110.0
const LARGURA_JOGADOR := 300.0
const LARGURA_PARTIDAS := 230.0

@onready var http: HTTPRequest = $HTTPRequest
@onready var cabecalho: HBoxContainer = $Cabecalho
@onready var lista: VBoxContainer = $ScrollContainer/Lista
@onready var status: Label = $Status
@onready var botao_voltar: Button = $VOLTAR

var _som_ui: AudioStreamPlayer


func _ready() -> void:
	http.request_completed.connect(_ao_receber_resposta)
	botao_voltar.pressed.connect(func():
		_tocar_som_ui("res://sounds/clicar.mp3")
		await Transicao.mudar_cena("res://scenes/TelaInicial.tscn", 0.8)
	)
	botao_voltar.mouse_entered.connect(func(): _tocar_som_ui("res://sounds/hover.mp3"))

	_criar_cabecalho()
	_carregar_ranking()


func _tocar_som_ui(caminho: String) -> void:
	if _som_ui == null:
		_som_ui = AudioStreamPlayer.new()
		add_child(_som_ui)
	var s := load(caminho)
	if s is AudioStream:
		_som_ui.stream = s
		_som_ui.play()


func _criar_cabecalho() -> void:
	_adicionar_label(cabecalho, "Pos.", LARGURA_POSICAO, 34, HORIZONTAL_ALIGNMENT_CENTER, false)
	_adicionar_label(cabecalho, "Sala", 0.0, 34, HORIZONTAL_ALIGNMENT_LEFT, true)
	_adicionar_label(cabecalho, "Jogador F", LARGURA_JOGADOR, 34, HORIZONTAL_ALIGNMENT_LEFT, false)
	_adicionar_label(cabecalho, "Jogador C", LARGURA_JOGADOR, 34, HORIZONTAL_ALIGNMENT_LEFT, false)
	_adicionar_label(cabecalho, "Partidas", LARGURA_PARTIDAS, 34, HORIZONTAL_ALIGNMENT_RIGHT, false)


func _carregar_ranking() -> void:
	status.visible = true
	status.text = "Carregando ranking..."

	var url: String = (
		"https://%s.supabase.co/rest/v1/salas" % PROJECT_REF
		+ "?select=id,nome,jogador_f_nome,jogador_c_nome,rodada_atual,criada_em"
		+ "&order=criada_em.asc"
	)

	var headers := PackedStringArray([
		"apikey: " + SUPABASE_KEY,
		"Authorization: Bearer " + SUPABASE_KEY
	])

	var erro: Error = http.request(url, headers, HTTPClient.METHOD_GET)

	if erro != OK:
		_mostrar_erro("Não foi possível consultar o ranking.")


func _ao_receber_resposta(
	resultado: int,
	codigo_http: int,
	_cabecalhos: PackedStringArray,
	corpo: PackedByteArray
) -> void:
	var texto: String = corpo.get_string_from_utf8()

	if resultado != HTTPRequest.RESULT_SUCCESS:
		_mostrar_erro("Falha na conexão com o Supabase.")
		return

	if codigo_http < 200 or codigo_http >= 300:
		_mostrar_erro("Erro ao carregar o ranking (HTTP %d)." % codigo_http)
		return

	var dados = JSON.parse_string(texto)

	if not dados is Array:
		_mostrar_erro("A resposta do servidor não é uma lista de salas.")
		return

	_mostrar_salas(dados)


func _mostrar_erro(mensagem: String) -> void:
	status.visible = true
	status.text = mensagem


func _mostrar_salas(salas: Array) -> void:
	for filho in lista.get_children():
		filho.queue_free()

	status.visible = false

	if salas.is_empty():
		_mostrar_erro("Nenhuma sala encontrada.")
		return

	salas.sort_custom(_comparar_salas)

	var posicao := 0
	for sala in salas:
		if not (sala is Dictionary):
			continue
		posicao += 1
		_adicionar_linha(posicao, sala)


func _comparar_salas(a, b) -> bool:
	var rodadas_a := _rodadas(a)
	var rodadas_b := _rodadas(b)
	if rodadas_a == rodadas_b:
		return str(a.get("criada_em", "")) < str(b.get("criada_em", ""))
	return rodadas_a > rodadas_b


func _adicionar_linha(posicao: int, sala: Dictionary) -> void:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(0, 92)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var estilo := StyleBoxFlat.new()
	estilo.bg_color = Color(0.8, 0.86, 0.94, 0.92)
	estilo.border_color = Color(0.3, 0.47, 0.68, 0.95)
	estilo.set_border_width_all(3)
	estilo.set_corner_radius_all(8)
	card.add_theme_stylebox_override("panel", estilo)

	var margem := MarginContainer.new()
	margem.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margem.add_theme_constant_override("margin_left", 20)
	margem.add_theme_constant_override("margin_right", 20)
	margem.add_theme_constant_override("margin_top", 4)
	margem.add_theme_constant_override("margin_bottom", 4)
	card.add_child(margem)

	var linha := HBoxContainer.new()
	linha.add_theme_constant_override("separation", 16)
	margem.add_child(linha)

	_adicionar_label(linha, "#%d" % posicao, LARGURA_POSICAO, 44, HORIZONTAL_ALIGNMENT_CENTER, false)
	_adicionar_label(linha, _nome_sala(sala), 0.0, 40, HORIZONTAL_ALIGNMENT_LEFT, true)
	_adicionar_label(linha, "F: " + _nome_jogador(sala, "jogador_f_nome"), LARGURA_JOGADOR, 32, HORIZONTAL_ALIGNMENT_LEFT, false)
	_adicionar_label(linha, "C: " + _nome_jogador(sala, "jogador_c_nome"), LARGURA_JOGADOR, 32, HORIZONTAL_ALIGNMENT_LEFT, false)
	_adicionar_label(linha, _texto_partidas(_rodadas(sala)), LARGURA_PARTIDAS, 38, HORIZONTAL_ALIGNMENT_RIGHT, false)

	lista.add_child(card)


func _adicionar_label(
	container: BoxContainer,
	texto: String,
	largura: float,
	tamanho: int,
	alinhamento: int,
	expandir: bool
) -> void:
	var label := Label.new()
	label.text = texto
	label.horizontal_alignment = alinhamento
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.add_theme_font_override("font", FONTE)
	label.add_theme_font_size_override("font_size", tamanho)
	label.add_theme_color_override("font_color", COR_TEXTO)
	if expandir:
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		label.custom_minimum_size = Vector2(largura, 0)
	container.add_child(label)


func _nome_sala(sala: Dictionary) -> String:
	var nome = sala.get("nome", "")
	if nome == null or str(nome).strip_edges().is_empty():
		return "Sala sem nome"
	return str(nome)


func _nome_jogador(sala: Dictionary, campo: String) -> String:
	var nome = sala.get(campo, "")
	if nome == null or str(nome).strip_edges().is_empty():
		return "—"
	return str(nome)


func _rodadas(sala: Dictionary) -> int:
	var valor = sala.get("rodada_atual", 0)
	return int(valor) if valor != null else 0


func _texto_partidas(quantidade: int) -> String:
	if quantidade == 1:
		return "1 partida"
	return "%d partidas" % quantidade
