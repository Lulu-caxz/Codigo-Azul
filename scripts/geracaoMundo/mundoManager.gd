extends Node3D

const PROJECT_REF: String = "ovkvgnnsxmpymcjclnzo"
const SUPABASE_KEY: String = "sb_publishable_3FDWeQxz2a8wEO-se44m-w_guLkTpR5"

@onready var terreno = $Terreno
@onready var ruas = $Ruas
@onready var quadras = $Quadras
@onready var predios = $Predios
@onready var http_mapa: HTTPRequest = $HTTPRequest


func _ready() -> void:
	gerar_mundo()


func gerar_mundo() -> void:
	terreno.gerar_alturas()
	ruas.gerar_ruas()
	quadras.gerar_quadras()
	predios.gerar_predios()

	await terreno.gerar_malha()

	# Atualiza o mapa da sala no Supabase.
	await atualizar_mapa_backend()


func atualizar_mapa_backend() -> void:
	print("dsvsvsvsddddddddddddddddddddddddddddd",Global.salaID)
	if Global.salaID.is_empty():
		push_error("ID da sala não definido.")
		return

	var url: String = (
		"https://%s.supabase.co/rest/v1/salas" % PROJECT_REF
		+ "?id=eq." + Global.salaID.uri_encode()
	)

	var headers := PackedStringArray([
		"Content-Type: application/json",
		"apikey: " + SUPABASE_KEY,
		"Authorization: Bearer " + SUPABASE_KEY,
		"Prefer: return=representation"
	])

	# PackedInt32Array não é convertido diretamente para JSON.
	var mapa_json: Array = Array(Global.mapa)

	var corpo: String = JSON.stringify({
		"mapa": mapa_json
	})

	var erro := http_mapa.request(
		url,
		headers,
		HTTPClient.METHOD_PATCH,
		corpo
	)

	if erro != OK:
		push_error("Não foi possível enviar o mapa.")
		return

	var resposta = await http_mapa.request_completed
	var resultado: int = resposta[0]
	var codigo_http: int = resposta[1]
	var texto: String = resposta[3].get_string_from_utf8()

	if resultado != HTTPRequest.RESULT_SUCCESS:
		push_error("Falha de conexão ao atualizar o mapa.")
		return

	if codigo_http < 200 or codigo_http >= 300:
		push_error("Erro HTTP ao atualizar o mapa: " + str(codigo_http))
		print(texto)
		return

	var dados = JSON.parse_string(texto)

	if dados is Array and not dados.is_empty():
		print("Mapa atualizado no backend!")
		print("Quantidade de valores: ", Global.mapa.size())
	else:
		push_error("Nenhuma sala foi atualizada. Verifique o ID e as permissões.")
