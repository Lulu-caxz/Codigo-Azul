extends Node

signal sala_criada()
signal erro_ao_criar(mensagem: String)
signal entrada_concluida(sucesso: bool)

const PROJECT_REF: String = "ovkvgnnsxmpymcjclnzo"
const SUPABASE_KEY: String = "sb_publishable_3FDWeQxz2a8wEO-se44m-w_guLkTpR5"

@onready var http: HTTPRequest = $HTTPRequest

var operacao_atual: String = ""
var jogador_id: String = ""


func _ready() -> void:
	randomize()
	http.request_completed.connect(_ao_receber_resposta)


func criar_sala(nome: String = "Nova sala") -> void:
	var url: String = "https://%s.supabase.co/rest/v1/salas" % PROJECT_REF

	var seed_mapa: int = randi_range(0, 2147483647)

	var dados: Dictionary = {
		"nome": nome,
		"largura": 100,
		"profundidade": 100,
		"tamanho_cubo": 0.5,
		"altura_maxima": 5.0,
		"seed": seed_mapa,
		"mapa": [],
		"jogador_f_id": null,
		"jogador_c_id": null,
		"iniciado": false,
		"eventos": Global.eventos,
		"duracao_timer": Global.tempo,
	}

	var headers := PackedStringArray([
		"Content-Type: application/json",
		"apikey: " + SUPABASE_KEY,
		"Authorization: Bearer " + SUPABASE_KEY,
		"Prefer: return=representation"
	])

	operacao_atual = "criar"

	var resultado := http.request(
		url,
		headers,
		HTTPClient.METHOD_POST,
		JSON.stringify(dados)
	)

	if resultado != OK:
		operacao_atual = ""
		erro_ao_criar.emit("Não foi possível iniciar a requisição: %s" % resultado)


func entrar_na_sala(id_sala: String, papel: String) -> bool:
	if papel != "F" and papel != "C":
		push_error("Papel inválido: " + papel)
		return false

	var campo: String
	if papel == "F":
		campo = "jogador_f_id"
	else:
		campo = "jogador_c_id"

	# Consultar a sala antes de tentar entrar.
	var url_consulta: String = (
		"https://%s.supabase.co/rest/v1/salas" % PROJECT_REF
		+ "?select=id," + campo + ",iniciado"
		+ "&id=eq." + id_sala.uri_encode()
	)

	var headers := PackedStringArray([
		"apikey: " + SUPABASE_KEY,
		"Authorization: Bearer " + SUPABASE_KEY
	])

	var http_consulta := HTTPRequest.new()
	add_child(http_consulta)

	var erro := http_consulta.request(
		url_consulta,
		headers,
		HTTPClient.METHOD_GET
	)

	if erro != OK:
		http_consulta.queue_free()
		push_error("Não foi possível consultar a sala.")
		return false

	var resposta_http = await http_consulta.request_completed
	http_consulta.queue_free()

	var resultado: int = resposta_http[0]
	var codigo_http: int = resposta_http[1]
	var corpo: PackedByteArray = resposta_http[3]
	var texto: String = corpo.get_string_from_utf8()

	if resultado != HTTPRequest.RESULT_SUCCESS:
		push_error("Falha de conexão ao consultar a sala.")
		return false

	if codigo_http < 200 or codigo_http >= 300:
		push_error("Erro HTTP ao consultar sala: " + str(codigo_http))
		print(texto)
		return false

	var dados = JSON.parse_string(texto)

	if not dados is Array or dados.is_empty():
		push_error("Sala não encontrada.")
		return false

	var sala: Dictionary = dados[0]

	if sala.get("iniciado", false):
		print("A partida já foi iniciada.")
		return false

	var jogador_atual = sala.get(campo)

	if jogador_atual != null and str(jogador_atual) != "":
		print("A vaga do Player ", papel, " já está ocupada.")
		return false

	# A vaga parece livre; agora tentar ocupá-la no servidor.
	var crypto := Crypto.new()
	jogador_id = crypto.generate_random_bytes(16).hex_encode()

	var url_atualizacao: String = (
		"https://%s.supabase.co/rest/v1/salas" % PROJECT_REF
		+ "?id=eq." + id_sala.uri_encode()
		+ "&" + campo + "=is.null"
		+ "&iniciado=eq.false"
	)

	var headers_patch := PackedStringArray([
		"Content-Type: application/json",
		"apikey: " + SUPABASE_KEY,
		"Authorization: Bearer " + SUPABASE_KEY,
		"Prefer: return=representation"
	])

	operacao_atual = "entrar"

	var erro_patch := http.request(
		url_atualizacao,
		headers_patch,
		HTTPClient.METHOD_PATCH,
		JSON.stringify({campo: jogador_id})
	)

	if erro_patch != OK:
		operacao_atual = ""
		push_error("Não foi possível iniciar a entrada na sala.")
		return false

	return await entrada_concluida


func _ao_receber_resposta(
	resultado: int,
	codigo_http: int,
	_cabecalhos: PackedStringArray,
	corpo: PackedByteArray
) -> void:
	var texto: String = corpo.get_string_from_utf8()
	var operacao := operacao_atual
	operacao_atual = ""

	if resultado != HTTPRequest.RESULT_SUCCESS:
		erro_ao_criar.emit("Erro de conexão com o Supabase.")
		if operacao == "entrar":
			entrada_concluida.emit(false)
		return

	if codigo_http < 200 or codigo_http >= 300:
		erro_ao_criar.emit(
			"Supabase retornou HTTP %d: %s" % [codigo_http, texto]
		)
		if operacao == "entrar":
			entrada_concluida.emit(false)
		return

	var resposta = JSON.parse_string(texto)

	if operacao == "criar":
		if resposta is Array and not resposta.is_empty():
			sala_criada.emit()
		else:
			erro_ao_criar.emit("Resposta inesperada: " + texto)

	elif operacao == "entrar":
		if codigo_http < 200 or codigo_http >= 300:
			push_error("O Supabase recusou a entrada.")
			entrada_concluida.emit(false)
			return

		if resposta is Array and not resposta.is_empty():
			entrada_concluida.emit(true)
		else:
			print("Nenhuma linha foi atualizada.")
			print("Verifique o ID da sala, a vaga e as políticas RLS.")
			entrada_concluida.emit(false)
