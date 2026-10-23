
extends Node

const PROJECT_REF: String = "ovkvgnnsxmpymcjclnzo"
const SUPABASE_KEY: String = "sb_publishable_3FDWeQxz2a8wEO-se44m-w_guLkTpR5"

const INTERVALO_CONSULTA: float = 2.0

@onready var http: HTTPRequest = $HTTPRequest

var verificando: bool = false
var mudando_cena: bool = false


func _ready() -> void:
	if Global.salaID.is_empty():
		push_error("ID da sala não foi informado.")
		return

	print("Sala de espera iniciada.")
	print("ID da sala: ", Global.salaID)
	print("Papel: ", Global.funcao)

	# Começa a verificar a sala.
	verificar_sala_periodicamente()


func verificar_sala_periodicamente() -> void:
	while is_inside_tree() and not mudando_cena:
		await verificar_sala()

		if mudando_cena:
			break

		await get_tree().create_timer(
			INTERVALO_CONSULTA
		).timeout


func requisitar(
	url: String,
	metodo: HTTPClient.Method,
	corpo: String = ""
) -> Dictionary:
	var headers := PackedStringArray([
		"apikey: " + SUPABASE_KEY,
		"Authorization: Bearer " + SUPABASE_KEY,
		"Content-Type: application/json",
		"Prefer: return=representation"
	])

	var erro := http.request(url, headers, metodo, corpo)

	if erro != OK:
		push_error("Não foi possível iniciar a requisição HTTP.")
		return {}

	var resposta_http = await http.request_completed

	return {
		"resultado": resposta_http[0],
		"codigo": resposta_http[1],
		"corpo": resposta_http[3].get_string_from_utf8()
	}


func verificar_sala() -> void:
	if verificando or mudando_cena:
		return

	verificando = true

	var url: String = (
		"https://%s.supabase.co/rest/v1/salas" % PROJECT_REF
		+ "?select=id,jogador_f_id,jogador_c_id,iniciado"
		+ "&id=eq." + Global.salaID.uri_encode()
	)

	var resposta := await requisitar(
		url,
		HTTPClient.METHOD_GET
	)

	if resposta.is_empty():
		verificando = false
		return

	if resposta["resultado"] != HTTPRequest.RESULT_SUCCESS:
		push_error("Erro de conexão ao consultar a sala.")
		verificando = false
		return

	if resposta["codigo"] < 200 or resposta["codigo"] >= 300:
		push_error("Erro HTTP ao consultar a sala: " + str(resposta["codigo"]))
		print(resposta["corpo"])
		verificando = false
		return

	var dados = JSON.parse_string(resposta["corpo"])

	if not dados is Array or dados.is_empty():
		push_error("A sala não foi encontrada.")
		verificando = false
		return

	var sala: Dictionary = dados[0]

	if sala.get("iniciado", false):
		print("A partida já foi iniciada.")
		mudando_cena = true
		verificando = false
		ir_para_jogo()
		return

	var jogador_f = sala.get("jogador_f_id")
	var jogador_c = sala.get("jogador_c_id")

	var f_presente: bool = (
		jogador_f != null and str(jogador_f) != ""
	)

	var c_presente: bool = (
		jogador_c != null and str(jogador_c) != ""
	)

	if f_presente and c_presente:
		print("Os dois jogadores entraram!")
		await iniciar_partida()
	else:
		print("Aguardando o outro jogador...")

	verificando = false


func iniciar_partida() -> void:
	var url: String = (
		"https://%s.supabase.co/rest/v1/salas" % PROJECT_REF
		+ "?id=eq." + Global.salaID.uri_encode()
		+ "&iniciado=eq.false"
		+ "&jogador_f_id=not.is.null"
		+ "&jogador_c_id=not.is.null"
	)

	var resposta := await requisitar(
		url,
		HTTPClient.METHOD_PATCH,
		JSON.stringify({
			"iniciado": true,
			"partida_perdida": false
		})
	)

	if resposta.is_empty():
		return

	if resposta["resultado"] != HTTPRequest.RESULT_SUCCESS:
		push_error("Falha ao iniciar a partida.")
		return

	if resposta["codigo"] < 200 or resposta["codigo"] >= 300:
		push_error("Erro HTTP ao iniciar a partida: " + str(resposta["codigo"]))
		print(resposta["corpo"])
		return

	var dados = JSON.parse_string(resposta["corpo"])

	if dados is Array and not dados.is_empty():
		print("Partida marcada como iniciada!")
		mudando_cena = true
		ir_para_jogo()
	else:
		# Outro jogador pode ter iniciado a partida primeiro.
		# A próxima consulta verificará o estado atualizado.
		print("Aguardando confirmação do início da partida.")


func ir_para_jogo() -> void:
	# Global.vidas vive no autoload e pode ter ficado em 0 na partida anterior
	# deste mesmo processo. Toda partida nova comeca com a vida cheia.
	Global.vidas = 5
	var erro
	if Global.funcao == "F":
		erro = get_tree().change_scene_to_file("res://scenes/cidade/main.tscn")
	else:
		erro = get_tree().change_scene_to_file("res://scenes/central/Main.tscn")

	if erro != OK:
		mudando_cena = false
		push_error("Não foi possível abrir a cena principal: " + str(erro))
