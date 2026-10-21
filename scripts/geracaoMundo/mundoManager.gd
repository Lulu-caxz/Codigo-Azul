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


func _ready() -> void:
	# Deixamos a cena principal comandar o início ou iniciamos no próximo frame
	gerar_mundo()


func gerar_mundo() -> void:
	# 1. Geração lógica (matrizes de altura, ruas, quadras e planejamento de prédios)
	terreno.gerar_alturas()
	ruas.gerar_ruas()
	quadras.gerar_quadras()
	predios.gerar_predios()

	# Avisa que já podemos calcular o ponto_de_nascimento() e posicionar a câmera do player
	dados_prontos.emit()
	await get_tree().process_frame

	# 2. Geração pesada das malhas 3D (Terreno + Chunks de Prédios ao redor do Player)
	await terreno.gerar_malha()
	await predios.aguardar_chunks_iniciais()

	# 3. Se também quiser esperar salvar no banco antes de tirar a tela preta, mantenha o await aqui:
	await atualizar_mapa_backend()

	# Agora sim, 100% carregado e renderizado!
	mundo_pronto.emit()


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
