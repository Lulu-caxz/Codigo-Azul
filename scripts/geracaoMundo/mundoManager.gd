extends Node3D

signal dados_prontos # Emitido quando alturas/ruas estão calculadas (para já posicionar o player)
signal mundo_pronto  # Emitido quando TODAS as malhas 3D (terreno + prédios) terminaram de carregar

const PROJECT_REF: String = "ovkvgnnsxmpymcjclnzo"
const SUPABASE_KEY: String = "sb_publishable_3FDWeQxz2a8wEO-se44m-w_guLkTpR5"

@onready var terreno = $Terreno
@onready var ruas = $Ruas
@onready var quadras = $Quadras
@onready var predios = $Predios
@onready var bordas: GeracaoBordas = _obter_no_bordas()
@onready var http_mapa: HTTPRequest = $HTTPRequest
@onready var objetivos = get_node_or_null("Pontos")

func _obter_no_bordas() -> GeracaoBordas:
	var b = get_node_or_null("Bordas")
	if b is GeracaoBordas:
		return b
	# Procura por qualquer filho que tenha a classe GeracaoBordas (mesmo com outro nome como "Node3D")
	for filho in get_children():
		if filho is GeracaoBordas:
			return filho
	return null

var geracao_iniciada: bool = false
var atualizando_mapa: bool = false

var rng_eventos := RandomNumberGenerator.new()
var indice_evento: int = 0

func _ready() -> void:
	print(
		"MUNDO MANAGER CRIADO | Instância: ",
		get_instance_id(),
		" | Sala: ",
		Global.salaID
	)

	if objetivos == null:
		objetivos = load("res://scripts/geracaoMundo/pontos.gd").new()
		objetivos.name = "Pontos"
		add_child(objetivos)
	
	if bordas == null:
		bordas = GeracaoBordas.new()
		bordas.name = "Bordas"
		add_child(bordas)
	
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
	if bordas:
		bordas.gerar_bordas()

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

func gerar_eventos(numero_rodada: int = 1) -> void:
	Global.eventos.clear()
	rng_eventos.randomize()

	if objetivos == null:
		push_error("Não foi possível gerar eventos: objetivos não encontrados.")
		return

	var duracao: int = objetivos.duracao_timer_backend()
	Global.duracao_partida = duracao

	if duracao < 80:
		push_error(
			"A duração da partida precisa ser de pelo menos 80 segundos " +
			"para respeitar os limites dos eventos."
		)
		return

	var rodada: int = maxi(numero_rodada, 1)

	# Rodada 1: 2 blackouts + 1 chuva. A cada rodada seguinte alterna-se
	# um blackout (rodadas pares) e uma chuva (rodadas ímpares).
	var total_blackouts: int = 2 + floori(float(rodada) / 2.0)
	var total_chuvas: int = 1 + floori(float(rodada - 1) / 2.0)

	var usados: Dictionary = {}

	# A chuva tem a janela menor (o granizo cai 30 s depois do aviso), por isso
	# ela reserva os segundos primeiro.
	var segundos_chuvas: Array[int] = _sortear_segundos_unicos(
		total_chuvas, 20, duracao - 60, usados
	)
	var segundos_blackouts: Array[int] = _sortear_segundos_unicos(
		total_blackouts, 20, duracao - 30, usados
	)

	for segundo in segundos_blackouts:
		Global.eventos.append(["blackout", segundo])
	for segundo in segundos_chuvas:
		Global.eventos.append(["chuvaGranizo", segundo])

	# Organiza os eventos pelo horário salvo.
	Global.eventos.sort_custom(
		func(a: Array, b: Array) -> bool:
			return int(a[1]) < int(b[1])
	)

	indice_evento = 0

	print("Eventos da rodada %d: %d blackouts e %d chuvas -> %s" % [
		rodada, segundos_blackouts.size(), segundos_chuvas.size(), Global.eventos
	])

	if segundos_blackouts.size() < total_blackouts or segundos_chuvas.size() < total_chuvas:
		push_warning(
			"Não há segundos livres suficientes para todos os eventos da rodada %d." % rodada
		)


# Sorteia horários distintos dentro da janela, ignorando os já usados na rodada.
func _sortear_segundos_unicos(
	quantidade: int,
	minimo: int,
	maximo: int,
	usados: Dictionary
) -> Array[int]:
	var sorteados: Array[int] = []
	if quantidade <= 0 or maximo < minimo:
		return sorteados

	var disponiveis: Array[int] = []
	for segundo in range(minimo, maximo + 1):
		if not usados.has(segundo):
			disponiveis.append(segundo)

	for i in range(disponiveis.size() - 1, 0, -1):
		var j: int = rng_eventos.randi_range(0, i)
		var troca: int = disponiveis[i]
		disponiveis[i] = disponiveis[j]
		disponiveis[j] = troca

	for i in range(mini(quantidade, disponiveis.size())):
		var segundo: int = disponiveis[i]
		sorteados.append(segundo)
		usados[segundo] = true

	sorteados.sort()
	return sorteados

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

	# Mapa gerado
	var mapa_json: Array = Array(Global.tipos)

	# Posição inicial do jogador F.
	var nascimento: Vector3 = ponto_de_nascimento()

	var jogador_f_position: Array = [
		nascimento.x,
		nascimento.y,
		nascimento.z,
		Global.vidas
	]

	# Este PATCH escreve apenas campos que o gerenciador de objetivos NAO
	# escreve. Rodada, timer, pontos, eventos e abrigo saem juntos pelo
	# GerenciadorObjetivos, em um unico PATCH atomico.
	var corpo: String = JSON.stringify({
		"mapa": mapa_json,
		"jogador_f_position": jogador_f_position
	})

	var erro := http_mapa.request(
		url,
		headers,
		HTTPClient.METHOD_PATCH,
		corpo
	)

	if erro != OK:
		push_error("Não foi possível enviar os dados do mundo.")
		return

	var resposta = await http_mapa.request_completed
	var resultado: int = resposta[0]
	var codigo_http: int = resposta[1]
	var texto: String = resposta[3].get_string_from_utf8()

	if resultado != HTTPRequest.RESULT_SUCCESS:
		push_error("Falha de conexão ao atualizar o mundo.")
		return

	if codigo_http < 200 or codigo_http >= 300:
		push_error("Erro HTTP ao atualizar o mundo: " + str(codigo_http))
		print(texto)
		return

	var dados = JSON.parse_string(texto)

	print("Código HTTP: ", codigo_http)
	print("Resposta do Supabase: ", texto)
	print("ID usado na atualização: ", Global.salaID)

	if dados is Array and not dados.is_empty():
		print("Mapa e posição inicial publicados no backend.")
		print("Quantidade de valores do mapa: ", mapa_json.size())
		print("Rodada, timer, objetivos e abrigo são publicados pelo GerenciadorObjetivos.")
	elif dados is Array and dados.is_empty():
		push_error(
			"Nenhuma sala foi atualizada. "
			+ "Verifique o ID da sala e as políticas RLS."
		)
	else:
		push_error("Resposta inesperada do Supabase.")
