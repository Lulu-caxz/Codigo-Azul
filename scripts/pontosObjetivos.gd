class_name PontosObjetivos
extends Node2D

# CENTRAL: le `pontos_position` da sala no Supabase e desenha os objetivos no mapa 2D.
#
# Como usar: adicione este script a um Node2D FILHO do no do mapa 2D (o Node2D que
# desenha a textura do mapa). Assim as coordenadas dos marcadores sao as mesmas do mapa.
#
# Formato lido (o mesmo que a cidade grava):
#   pontos_position = [[x, y, z, "incompleto"|"completo", "tipo"], ...]
#   x, y, z = coordenadas GLOBAIS do mundo 3D. No mapa 2D so x e z importam.
#
# Conversao (mundo 3D -> mapa 2D):
#   pixel = (posicao_mundo - origem_mundo) / tamanho_cubo * tile_size
# O gerenciador de objetivos coloca cada ponto no CENTRO do bloco, entao o marcador
# cai exatamente no centro do tile correspondente.

signal pontos_atualizados(pontos: Array)

const PROJECT_REF: String = "ovkvgnnsxmpymcjclnzo"
const SUPABASE_KEY: String = "sb_publishable_3FDWeQxz2a8wEO-se44m-w_guLkTpR5"

# Posicoes dentro de cada entrada de pontos_position
const I_X := 0
const I_Y := 1
const I_Z := 2
const I_ESTADO := 3
const I_TIPO := 4

const COMPLETO := "completo"
const COR_PADRAO := Color("ffd23f")
const CORES := {
	"radar": Color("2ec4ff"),
	"bueiro": Color("c9c9c9"),
	"pluviometro": Color("4f7dff"),
}

@export var deslocamento_mapa: Vector2 = Vector2.ZERO

@export_group("Conversao mundo -> mapa 2D")
## Pixels de cada bloco no mapa 2D (TILE_SIZE do script do mapa).
@export var tile_size: float = 3.0
## Tamanho de um bloco no mundo 3D (Global.tamanho_cubo da cidade).
@export var tamanho_cubo: float = 1.0
## Posicao global (x, z) do Terreno no mundo 3D. Zero se ele fica na origem.
@export var origem_mundo: Vector2 = Vector2.ZERO

@export_group("Atualizacao")
## Segundos entre consultas ao Supabase.
@export_range(0.25, 10.0, 0.25) var intervalo_consulta: float = 1.0

@export_group("Aparencia")
## Sprite 2D de cada tipo (chave = nome do tipo, valor = Texture2D). Vazio = ponto simples.
@export var texturas_tipos: Dictionary = {}
## Lado do marcador, em pixels do mapa 2D.
@export var tamanho_marcador: float = 14.0
## Mostra tambem os objetivos ja concluidos (esmaecidos).
@export var mostrar_completos: bool = false
## Faz os marcadores pulsarem levemente.
@export var pulsar: bool = true
## Os marcadores usam o material (shader de sonar) do mapa. Desligado = sempre visiveis.
@export var usar_material_do_mapa: bool = false

var _http: HTTPRequest
var _pontos: Array[Dictionary] = []
var _marcadores: Array[Dictionary] = []
var _assinatura: String = ""
var _consultando: bool = false
var _pontos_simples: Dictionary = {}


func _ready() -> void:
	use_parent_material = usar_material_do_mapa
	set_process(pulsar)

	var central := get_tree().current_scene.find_child(
		"CentralSync",
		true,
		false
	)

	if central == null:
		push_error("PontosObjetivos: CentralSync não encontrado.")
		return

	central.dados_sala_atualizados.connect(
		_ao_dados_sala_atualizados
	)

	print("PontosObjetivos: conectado ao CentralSync.")

	# Solicita os dados imediatamente, sem depender da próxima consulta.
	await central.sincronizar_sala()

func _ao_dados_sala_atualizados(
	_posicao: Vector3,
	pontos: Array
) -> void:
	print("PontosObjetivos: recebidos ", pontos.size(), " objetivos.")

	_aplicar(pontos)

# -----------------------------------------------------------------------------
#  API PUBLICA (para a tela da central)
# -----------------------------------------------------------------------------
## Lista de dicionarios: {indice, tipo, completo, mundo: Vector3, mapa: Vector2}.
func pontos() -> Array:
	return _pontos.duplicate(true)


func pontos_incompletos() -> Array:
	var saida: Array = []
	for p in _pontos:
		if not p["completo"]:
			saida.append(p.duplicate(true))
	return saida


func mundo_para_mapa(x: float, z: float) -> Vector2:
	var posicao := Vector2(
		x - origem_mundo.x,
		z - origem_mundo.y
	) / tamanho_cubo * tile_size

	return posicao + deslocamento_mapa


## Inverso: posicao no mapa 2D -> (x, z) do mundo 3D.
func mapa_para_mundo(p: Vector2) -> Vector2:
	return p / tile_size * tamanho_cubo + origem_mundo


## Forca uma consulta agora (alem das periodicas).
func atualizar_agora() -> void:
	if _consultando or Global.salaID.is_empty():
		return
	_consultando = true

	var url: String = "https://%s.supabase.co/rest/v1/salas" % PROJECT_REF \
		+ "?id=eq." + Global.salaID.uri_encode() \
		+ "&select=pontos_position"
	var headers := PackedStringArray([
		"apikey: " + SUPABASE_KEY,
		"Authorization: Bearer " + SUPABASE_KEY,
		"Accept: application/json",
	])

	var erro := _http.request(url, headers, HTTPClient.METHOD_GET)
	if erro != OK:
		push_warning("Pontos: nao foi possivel consultar o Supabase (erro %d)." % erro)
		_consultando = false
		return

	var resposta = await _http.request_completed
	_consultando = false

	var resultado: int = resposta[0]
	var codigo: int = resposta[1]
	var texto: String = resposta[3].get_string_from_utf8()
	if resultado != HTTPRequest.RESULT_SUCCESS or codigo < 200 or codigo >= 300:
		push_warning("Pontos: consulta falhou (resultado %d, HTTP %d)." % [resultado, codigo])
		return

	var linhas = JSON.parse_string(texto)
	if not linhas is Array or linhas.is_empty():
		return

	var bruto = linhas[0].get("pontos_position")
	if bruto is String:          # caso a coluna seja texto
		bruto = JSON.parse_string(bruto)
	if bruto == null:
		bruto = []
	if not bruto is Array:
		push_warning("Pontos: pontos_position nao e uma lista.")
		return

	_aplicar(bruto)


# -----------------------------------------------------------------------------
#  INTERNO
# -----------------------------------------------------------------------------
func _loop_consulta() -> void:
	while is_inside_tree():
		await atualizar_agora()
		await get_tree().create_timer(intervalo_consulta).timeout


func _process(_delta: float) -> void:
	var k := 1.0 + 0.18 * sin(Time.get_ticks_msec() / 1000.0 * 4.0)
	for m in _marcadores:
		if not m["completo"]:
			var no := m["no"] as Sprite2D
			no.scale = Vector2.ONE * float(m["escala"]) * k


func _aplicar(bruto: Array) -> void:
	var assinatura := JSON.stringify(bruto)
	if assinatura == _assinatura:
		return   # nada mudou
	_assinatura = assinatura

	_pontos.clear()
	for i in bruto.size():
		var e = bruto[i]
		if not e is Array or e.size() < 5:
			continue
		var mundo := Vector3(float(e[I_X]), float(e[I_Y]), float(e[I_Z]))
		_pontos.append({
			"indice": i,
			"tipo": String(e[I_TIPO]),
			"completo": String(e[I_ESTADO]) == COMPLETO,
			"mundo": mundo,
			"mapa": mundo_para_mapa(mundo.x, mundo.z),
		})

	_reconstruir_marcadores()
	pontos_atualizados.emit(pontos())


func _reconstruir_marcadores() -> void:
	for m in _marcadores:
		(m["no"] as Node).queue_free()
	_marcadores.clear()

	for p in _pontos:
		var completo: bool = p["completo"]
		if completo and not mostrar_completos:
			continue

		var textura := _textura_do_tipo(String(p["tipo"]))
		var escala := tamanho_marcador / maxf(float(textura.get_width()), 1.0)

		var no := Sprite2D.new()
		no.texture = textura
		no.position = p["mapa"]
		no.scale = Vector2.ONE * escala
		no.z_index = 10
		no.use_parent_material = usar_material_do_mapa
		if completo:
			no.modulate = Color(0.55, 0.95, 0.65, 0.6)
		add_child(no)

		_marcadores.append({"no": no, "escala": escala, "completo": completo})


func _textura_do_tipo(tipo: String) -> Texture2D:
	var valor: Variant = texturas_tipos.get(tipo)
	if valor is Texture2D:
		return valor
	var cor: Color = CORES.get(tipo, COR_PADRAO)
	return _ponto_simples(cor)


# Ponto 16x16 (miolo colorido + contorno escuro), igual ao da cidade.
func _ponto_simples(cor: Color) -> ImageTexture:
	var chave := cor.to_html()
	if _pontos_simples.has(chave):
		return _pontos_simples[chave]

	var tam := 16
	var img := Image.create_empty(tam, tam, false, Image.FORMAT_RGBA8)
	var centro := (tam - 1) * 0.5
	for x in tam:
		for y in tam:
			var d := Vector2(x - centro, y - centro).length()
			if d <= 4.8:
				img.set_pixel(x, y, cor)
			elif d <= 6.8:
				img.set_pixel(x, y, Color(0.08, 0.08, 0.1, 1.0))

	var tex := ImageTexture.create_from_image(img)
	_pontos_simples[chave] = tex
	return tex
