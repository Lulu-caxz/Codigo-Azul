
extends Node2D

const PROJECT_REF: String = "ovkvgnnsxmpymcjclnzo"
const SUPABASE_KEY: String = "sb_publishable_3FDWeQxz2a8wEO-se44m-w_guLkTpR5"

const MAP_WIDTH: int = 320
const MAP_HEIGHT: int = 180
const TILE_SIZE: int = 4

@onready var http: HTTPRequest = $HTTPRequest

var mapa: Array = []
var textura_mapa: ImageTexture

var cores: Array[Color] = [
	Color.CORNFLOWER_BLUE,  # 0 - Água
	Color.SANDY_BROWN,      # 1 - Areia
	Color.FOREST_GREEN,     # 2 - Grama
	Color.DARK_GRAY,        # 3 - Pedra
	Color("4a4a50"),        # 4 - Rua
	Color("8b6b4a"),        # 5 - Ponte
	Color("b0a898"),        # 6 - Calçada
	Color("a09888")         # 7 - Quadra
]


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	await carregar_mapa()


func carregar_mapa() -> void:
	if Global.salaID.is_empty():
		push_error("O ID da sala não foi definido.")
		return

	var url: String = (
		"https://%s.supabase.co/rest/v1/salas" % PROJECT_REF
		+ "?id=eq." + Global.salaID.uri_encode()
		+ "&select=mapa"
	)

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
		push_error("Não foi possível solicitar o mapa.")
		return

	var resposta = await http.request_completed

	var resultado: int = resposta[0]
	var codigo_http: int = resposta[1]
	var texto: String = resposta[3].get_string_from_utf8()

	if resultado != HTTPRequest.RESULT_SUCCESS:
		push_error("Falha de conexão ao buscar o mapa.")
		return

	if codigo_http < 200 or codigo_http >= 300:
		push_error("Erro HTTP ao buscar mapa: " + str(codigo_http))
		print(texto)
		return

	var dados = JSON.parse_string(texto)

	if not dados is Array or dados.is_empty():
		push_error("Nenhuma sala encontrada no banco de dados.")
		return

	mapa = dados[0].get("mapa", [])

	if not mapa is Array:
		push_error("O campo mapa não é um array.")
		return

	if mapa.size() != MAP_WIDTH * MAP_HEIGHT:
		push_error(
			"Quantidade incorreta de blocos: "
			+ str(mapa.size())
			+ ". Esperado: "
			+ str(MAP_WIDTH * MAP_HEIGHT)
		)
		carregar_mapa()
		return

	construir_mapa()


func construir_mapa() -> void:
	var imagem := Image.create(
		MAP_WIDTH,
		MAP_HEIGHT,
		false,
		Image.FORMAT_RGBA8
	)

	for x in range(MAP_WIDTH):
		for y in range(MAP_HEIGHT):
			# Preserva a ordem usada pelo gerador:
			# índice = x * profundidade + z
			var indice: int = x * MAP_HEIGHT + y
			var valor: int = int(mapa[indice])
			
			if valor == 7 or valor == 1:
				imagem.set_pixel(x, y, cor_do_bloco(2))
			else:
				imagem.set_pixel(x, y, cor_do_bloco(valor))

	textura_mapa = ImageTexture.create_from_image(imagem)

	queue_redraw()

	print("Mapa 2D carregado: ", MAP_WIDTH, " x ", MAP_HEIGHT)


func cor_do_bloco(valor: int) -> Color:
	if valor >= 0 and valor < cores.size():
		return cores[valor]

	return Color.MAGENTA


func _draw() -> void:
	if textura_mapa == null:
		return

	var tamanho := Vector2(
		MAP_WIDTH * TILE_SIZE,
		MAP_HEIGHT * TILE_SIZE
	)

	draw_texture_rect(
		textura_mapa,
		Rect2(Vector2.ZERO, tamanho),
		false
	)
