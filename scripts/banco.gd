extends Node

const PROJECT_REF: String = "ovkvgnnsxmpymcjclnzo"
const SUPABASE_KEY: String = "sb_publishable_3FDWeQxz2a8wEO-se44m-w_guLkTpR5"

var http: HTTPRequest


func _ready() -> void:
	http = HTTPRequest.new()
	http.name = "HTTPBanco"
	add_child(http)


func atualizar_vida(vidas: int) -> void:
	if Global.salaID.is_empty():
		return

	# 1. Lê a posição atual para não perder o marcador do jogador.
	var url_get := "https://%s.supabase.co/rest/v1/salas" % PROJECT_REF
	url_get += "?id=eq." + Global.salaID.uri_encode()
	url_get += "&select=jogador_f_position"

	var headers_get := PackedStringArray([
		"apikey: " + SUPABASE_KEY,
		"Authorization: Bearer " + SUPABASE_KEY,
		"Accept: application/json"
	])

	http.request(url_get, headers_get, HTTPClient.METHOD_GET)
	var resp = await http.request_completed

	var posicao_atual: Array = [0.0, 0.0, 0.0]
	var texto: String = resp[3].get_string_from_utf8()
	var dados = JSON.parse_string(texto)
	if dados is Array and not dados.is_empty():
		var sala: Dictionary = dados[0]
		var pos = sala.get("jogador_f_position", null)
		if pos is String:
			pos = JSON.parse_string(pos)
		if pos is Array and pos.size() >= 3:
			posicao_atual = [float(pos[0]), float(pos[1]), float(pos[2])]

	# 2. Grava a posição preservando o marcador e anexa a vida no 4º elemento.
	posicao_atual.append(vidas)

	var url_patch := "https://%s.supabase.co/rest/v1/salas" % PROJECT_REF
	url_patch += "?id=eq." + Global.salaID.uri_encode()

	var headers_patch := PackedStringArray([
		"Content-Type: application/json",
		"apikey: " + SUPABASE_KEY,
		"Authorization: Bearer " + SUPABASE_KEY,
		"Prefer: return=representation"
	])

	http.request(url_patch, headers_patch, HTTPClient.METHOD_PATCH, JSON.stringify({"jogador_f_position": posicao_atual}))
	await http.request_completed