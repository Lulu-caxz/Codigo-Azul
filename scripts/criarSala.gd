extends Node

signal sala_criada(dados: Dictionary)
signal erro_ao_criar(mensagem: String)

const PROJECT_REF: String = "ovkvgnnsxmpymcjclnzo"
const SUPABASE_KEY: String = "sb_publishable_3FDWeQxz2a8wEO-se44m-w_guLkTpR5"

@onready var http: HTTPRequest = $HTTPRequest


func _ready() -> void:
	randomize()
	http.request_completed.connect(_ao_receber_resposta)


func criar_sala(nome: String = "Nova sala") -> void:
	var url: String = (
        "https://%s.supabase.co/rest/v1/salas"
		% PROJECT_REF
	)

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
		"iniciado": false
	}

	var headers: PackedStringArray = [
		"Content-Type: application/json",
		"apikey: " + SUPABASE_KEY,
		"Authorization: Bearer " + SUPABASE_KEY,
        "Prefer: return=representation"
	]

	var corpo: String = JSON.stringify(dados)

	var resultado: Error = http.request(
		url,
		headers,
		HTTPClient.METHOD_POST,
		corpo
	)

	if resultado != OK:
		erro_ao_criar.emit(
			"Não foi possível iniciar a requisição: %s" % resultado
		)


func _ao_receber_resposta(
	resultado: int,
	codigo_http: int,
	_cabecalhos: PackedStringArray,
	corpo: PackedByteArray
) -> void:
	var texto: String = corpo.get_string_from_utf8()

	if resultado != HTTPRequest.RESULT_SUCCESS:
		erro_ao_criar.emit("Erro de conexão com o Supabase.")
		return

	if codigo_http < 200 or codigo_http >= 300:
		erro_ao_criar.emit(
			"Supabase retornou HTTP %d: %s" % [codigo_http, texto]
		)
		return

	var resposta = JSON.parse_string(texto)

	if resposta is Array and not resposta.is_empty():
		var sala: Dictionary = resposta[0]
		print("Sala criada! ID: ", sala.get("id"))
		sala_criada.emit(sala)
	else:
		erro_ao_criar.emit("Resposta inesperada: " + texto)
