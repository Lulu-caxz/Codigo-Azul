extends Node3D

signal dados_prontos # Emitido quando alturas/ruas estão calculadas (para já posicionar o player)
signal mundo_pronto  # Emitido quando TODAS as malhas 3D (terreno + prédios) terminaram de carregar

const PROJECT_REF: String = "ovkvgnnsxmpymcjclnzo"
const SUPABASE_KEY: String = "sb_publishable_3FDWeQxz2a8wEO-se44m-w_guLkTpR5"

@onready var terreno = $Terreno
@onready var ruas = $Ruas
@onready var quadras = $Quadras
@onready var predios = $Predios
@onready var http_mapa: HTTPRequest = $HTTPRequest

var geracao_iniciada: bool = false
var atualizando_mapa: bool = false


func _ready() -> void:
	print(
		"MUNDO MANAGER CRIADO | Instância: ",
		get_instance_id(),
		" | Sala: ",
		Global.salaID
	)


	terreno.terreno_pronto.connect(mundo_pronto_func)
	gerar_mundo()


func gerar_mundo() -> void:
	if geracao_iniciada:
		print("Geração ignorada: o mundo já foi gerado.")
		return

	if Global.salaID.is_empty():
		push_error("Não é possível gerar o mundo sem ID da sala.")
		return

	geracao_iniciada = true

	print("Iniciando geração. Sala: ", Global.salaID)
	terreno.gerar_alturas()
	ruas.gerar_ruas()
	quadras.gerar_quadras()
	predios.gerar_predios()

	# Dados lógicos prontos: o main adiciona o player e troca a câmera.
	dados_prontos.emit()

	# Espera 1 frame: o teleportar() é deferido e a câmera do player
	# precisa estar ativa, pois o streaming de prédios usa a câmera atual.
	await get_tree().process_frame
	await predios.aguardar_chunks_iniciais()

	terreno.gerar_malha()

func mundo_pronto_func() -> void:
	if atualizando_mapa:
		print("Atualização ignorada: já existe uma requisição em andamento.")
		return

	if Global.salaID.is_empty():
		push_error("Não é possível atualizar o mapa sem ID da sala.")
		return

	atualizando_mapa = true

	print("Mundo pronto. Sala: ", Global.salaID)

	mundo_pronto.emit()
	await atualizar_mapa_backend()

	atualizando_mapa = false

# Ponto de nascimento (posicao global), apenas apos o mundo estar pronto
func ponto_de_nascimento() -> Vector3:
	var cx = Global.largura >> 1
	var cz = Global.profundidade >> 1
	var melhor := Vector2i(cx, cz)
	var melhor_d := INF

	for pref in [4, -1]: # 4 = rua; -1 = qualquer bloco que nao seja agua
		for x in Global.largura:
			for z in Global.profundidade:
				var t = Global.tipos[x * Global.profundidade + z]
				if (pref == 4 and t != 4) or (pref == -1 and t == 0):
					continue
				var d := Vector2(x - cx, z - cz).length_squared()
				if d < melhor_d:
					melhor_d = d
					melhor = Vector2i(x, z)
		if melhor_d < INF:
			break

	var s = Global.tamanho_cubo
	return terreno.global_position + Vector3(
		(melhor.x + 0.5) * s,
		Global.altura_em(melhor.x, melhor.y) * s + 2.0,
		(melhor.y + 0.5) * s
	)


func atualizar_mapa_backend() -> void:

	var url: String = (
		"https://%s.supabase.co/rest/v1/salas" % PROJECT_REF
		+ "?id=eq." + Global.salaID.uri_encode()
		+ "&select=id"
	)

	var headers := PackedStringArray([
		"Content-Type: application/json",
		"apikey: " + SUPABASE_KEY,
		"Authorization: Bearer " + SUPABASE_KEY,
		"Prefer: return=representation"
	])

	var mapa_json: Array = Array(Global.tipos)
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

	print("Código HTTP: ", codigo_http)
	print("Resposta do Supabase: ", texto)
	print("ID usado na atualização: ", Global.salaID)

	if dados is Array and not dados.is_empty():
		print("Mapa atualizado no backend!")
		print("Quantidade de valores: ", Global.tipos.size())
	elif dados is Array and dados.is_empty():
		push_error(
			"Nenhuma linha foi retornada pelo PATCH. "
			+ "Verifique o ID e as políticas RLS."
		)
	else:
		push_error("Resposta inesperada do Supabase.")
