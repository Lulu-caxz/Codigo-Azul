
extends Node

signal dados_sala_atualizados(posicao: Vector3, pontos: Array)
signal timer_atualizado(segundos: int, iniciado: bool)

const PROJECT_REF: String = "ovkvgnnsxmpymcjclnzo"
const SUPABASE_KEY: String = "sb_publishable_3FDWeQxz2a8wEO-se44m-w_guLkTpR5"

const INTERVALO_CONSULTA: float = 1.0

var http: HTTPRequest

var posicao_jogador: Vector3 = Vector3.ZERO
var inicio_unix: float = 0.0
var duracao_timer: float = 0.0

var _consultando: bool = false
var _ultimo_segundo: int = -1
var _ultimo_estado_iniciado: bool = false


func _ready() -> void:
	http = HTTPRequest.new()
	http.name = "HTTPSincronizacaoCentral"
	add_child(http)

	print("Central: iniciando sincronização com o Supabase.")

	_loop_sincronizacao()


func _loop_sincronizacao() -> void:
	while is_inside_tree():
		await sincronizar_sala()

		if not is_inside_tree():
			break

		await get_tree().create_timer(INTERVALO_CONSULTA).timeout


func sincronizar_sala() -> void:
	if _consultando:
		return

	if Global.salaID.is_empty():
		push_warning("Central: Global.salaID ainda não foi definido.")
		return

	_consultando = true

	var url: String = "https://%s.supabase.co/rest/v1/salas" % PROJECT_REF
	url += "?id=eq." + Global.salaID.uri_encode()
	url += "&select=inicio_timer,duracao_timer,jogador_f_position,pontos_position"

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
		_consultando = false
		push_error("Central: não foi possível solicitar os dados.")
		return

	var resposta = await http.request_completed
	_consultando = false

	var resultado: int = resposta[0]
	var codigo: int = resposta[1]
	var texto: String = resposta[3].get_string_from_utf8()

	if resultado != HTTPRequest.RESULT_SUCCESS:
		push_error("Central: falha de conexão com o Supabase.")
		return

	if codigo < 200 or codigo >= 300:
		push_error("Central: erro HTTP %d: %s" % [codigo, texto])
		return

	var dados = JSON.parse_string(texto)

	if not dados is Array or dados.is_empty():
		push_warning("Central: sala não encontrada no Supabase.")
		return

	var sala: Dictionary = dados[0]

	# 1. Sincroniza o horário de início e a duração.
	var inicio_recebido = sala.get("inicio_timer", null)
	var duracao_recebida = sala.get("duracao_timer", 0)

	if inicio_recebido != null:
		inicio_unix = _converter_data_iso(String(inicio_recebido))

	duracao_timer = float(duracao_recebida)

	# 2. Atualiza os objetivos locais.
	var pontos = sala.get("pontos_position", [])

	if pontos is String:
		pontos = JSON.parse_string(pontos)

	if pontos is Array:
		Global.pontos_position = pontos.duplicate(true)

	# 3. Atualiza a posição do jogador.
	var posicao = sala.get("jogador_f_position", null)

	if posicao is String:
		posicao = JSON.parse_string(posicao)

	if posicao is Array and posicao.size() >= 3:
		posicao_jogador = Vector3(
			float(posicao[0]),
			float(posicao[1]),
			float(posicao[2])
		)

	# 4. Atualiza o tempo restante usando o relógio do sistema
	# e o horário de início recebido do banco.
	_atualizar_timer()

	# A Central e seus marcadores recebem os dados sincronizados.
	dados_sala_atualizados.emit(
		posicao_jogador,
		Global.pontos_position.duplicate(true)
	)


func _atualizar_timer() -> void:
	if inicio_unix <= 0.0:
		return

	var agora: float = Time.get_unix_time_from_system()
	var segundos: int
	var iniciado: bool = agora >= inicio_unix

	if not iniciado:
		# Antes do início: conta até o horário programado.
		segundos = ceili(inicio_unix - agora)
	else:
		# Depois do início: conta o tempo restante da rodada.
		segundos = maxi(
			0,
			ceili(inicio_unix + duracao_timer - agora)
		)

	# Atualiza a variável global que a interface pode consultar.
	Global.tempo = segundos

	if (
		segundos != _ultimo_segundo
		or iniciado != _ultimo_estado_iniciado
	):
		_ultimo_segundo = segundos
		_ultimo_estado_iniciado = iniciado

		timer_atualizado.emit(segundos, iniciado)

		if iniciado:
			print("Central: rodada iniciada. Tempo restante: ", segundos)
		else:
			print("Central: início da rodada em ", segundos, " segundos.")


func _converter_data_iso(valor: String) -> float:
	if valor.is_empty():
		return 0.0

	# Exemplo recebido:
	# 2026-10-22T15:30:00+00:00
	# Mantém a parte da data e hora para converter em Unix.
	if valor.length() < 19:
		return 0.0

	var data_hora: String = valor.substr(0, 19).replace("T", " ")

	return float(Time.get_unix_time_from_datetime_string(data_hora))
