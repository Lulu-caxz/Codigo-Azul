extends Node2D

const INFO = preload("res://scripts/informacoesMulheres.gd")
const FONTE = preload("res://fonts/ByteBounce-PT-BR.ttf")

const ALTURAS_DICAS: Array[float] = [430.0, 570.0, 710.0, 850.0]
const POSICAO_REPOUSO := Vector2(795.0, 623.0)
# Distancia entre o centro do sprite e o centro do copo (topo do pluviometro).
const OFFSET_COPO := 387.5

@onready var pluviometro: Sprite2D = $Pluviometro
@onready var label_ref: Label = $Textos/Referencia
@onready var adesivo: Sprite2D = $Adesivos/Adesivo

var _mulher: String
var _categoria: String
var _valor_correto: String
var _valores: Array[String] = []
var _botoes: Array[Button] = []
var _bloqueado: bool = false
var _som_ui: AudioStreamPlayer
var _linha_altura: Line2D


func _tocar_som(caminho: String, volume_db: float = 0.0) -> void:
	if _som_ui == null:
		_som_ui = AudioStreamPlayer.new()
		add_child(_som_ui)
	var s := load(caminho)
	if s is AudioStream:
		_som_ui.stream = s
		_som_ui.volume_db = volume_db
		_som_ui.play()


func _ready() -> void:
	_criar_linha_altura()
	_criar_botoes()
	_sorteiar()


func _criar_linha_altura() -> void:
	_linha_altura = Line2D.new()
	_linha_altura.name = "LinhaAltura"
	_linha_altura.points = PackedVector2Array([Vector2.ZERO, Vector2(270, 0)])
	_linha_altura.width = 4.0
	_linha_altura.default_color = Color(0.36, 0.55, 0.82, 0.65)
	_linha_altura.visible = false
	add_child(_linha_altura)


func _criar_botoes() -> void:
	for i in ALTURAS_DICAS.size():
		var btn := Button.new()
		btn.name = "Dica%d" % (i + 1)
		btn.text = "..."
		btn.size = Vector2(530, 88)
		btn.position = Vector2(1360, ALTURAS_DICAS[i] - 44.0)
		btn.focus_mode = Control.FOCUS_NONE
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		btn.add_theme_font_override("font", FONTE)
		btn.add_theme_font_size_override("font_size", 44)
		btn.add_theme_color_override("font_color", Color(0.12, 0.16, 0.25))
		btn.add_theme_color_override("font_hover_color", Color(0.08, 0.12, 0.2))
		btn.add_theme_color_override("font_pressed_color", Color(0.08, 0.12, 0.2))
		btn.add_theme_color_override("font_disabled_color", Color(0.12, 0.16, 0.25, 0.55))
		btn.add_theme_stylebox_override("normal", _criar_estilo(Color(0.78, 0.86, 0.95), Color(0.3, 0.47, 0.68)))
		btn.add_theme_stylebox_override("hover", _criar_estilo(Color(0.68, 0.8, 0.93), Color(0.24, 0.4, 0.6)))
		btn.add_theme_stylebox_override("pressed", _criar_estilo(Color(0.57, 0.72, 0.89), Color(0.2, 0.34, 0.52)))
		btn.add_theme_stylebox_override("disabled", _criar_estilo(Color(0.78, 0.86, 0.95, 0.6), Color(0.3, 0.47, 0.68, 0.4)))
		btn.pressed.connect(_escolher_dica.bind(i))
		add_child(btn)
		_botoes.append(btn)


func _criar_estilo(fundo: Color, borda: Color) -> StyleBoxFlat:
	var estilo := StyleBoxFlat.new()
	estilo.bg_color = fundo
	estilo.border_color = borda
	estilo.set_border_width_all(4)
	estilo.set_corner_radius_all(10)
	estilo.content_margin_left = 18.0
	estilo.content_margin_right = 18.0
	return estilo


func _sorteiar() -> void:
	var nomes: Array = INFO.InfoMulheres.keys()
	_mulher = String(nomes[randi() % nomes.size()])

	var categorias: Array = INFO.adesivos.keys()
	_categoria = String(categorias[randi() % categorias.size()])
	_valor_correto = _obter_valor(_mulher, _categoria)

	var outras: Array = []
	for n in nomes:
		if String(n) != _mulher:
			outras.append(String(n))
	outras.shuffle()

	_valores.clear()
	_valores.append(_valor_correto)
	for i in 3:
		_valores.append(_obter_valor(outras[i % outras.size()], _categoria))
	_valores.shuffle()

	for i in _botoes.size():
		_botoes[i].text = _valores[i]

	if adesivo != null and adesivo.texture is AtlasTexture:
		(adesivo.texture as AtlasTexture).region = INFO.adesivos[_categoria]

	label_ref.text = "Ref.: %s" % _mulher
	pluviometro.position = POSICAO_REPOUSO
	_linha_altura.visible = false


func _escolher_dica(i: int) -> void:
	if _bloqueado:
		return
	_bloqueado = true
	for btn in _botoes:
		btn.disabled = true

	_tocar_som("res://sounds/clicar.mp3", -10.0)

	var altura := ALTURAS_DICAS[i]
	_linha_altura.position = Vector2(1070.0, altura)
	_linha_altura.visible = true

	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(pluviometro, "position:y", altura + OFFSET_COPO, 0.6)
	await tw.finished

	if _valores[i] == _valor_correto:
		_acertar()
	else:
		await _errar()


func _errar() -> void:
	Global.vidas = maxi(Global.vidas - 1, 0)
	_tocar_som("res://sounds/erro.mp3")
	if Banco != null and Banco.has_method("atualizar_vida"):
		await Banco.atualizar_vida(Global.vidas)
	if ConectSupa != null and ConectSupa.has_method("enviar_variavel"):
		ConectSupa.enviar_variavel({
			"tipo": "vida",
			"vidas": Global.vidas
		})

	await get_tree().create_timer(1.0).timeout

	_linha_altura.visible = false
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(pluviometro, "position:y", POSICAO_REPOUSO.y, 0.4)
	await tw.finished

	_sorteiar()
	_bloqueado = false
	for btn in _botoes:
		if is_instance_valid(btn):
			btn.disabled = false


func _acertar() -> void:
	var ger = get_tree().current_scene.find_child("Pontos", true, false)
	if ger != null and ger.get("_indice_minigame_atual") != null and ger._indice_minigame_atual >= 0:
		ger.concluir_objetivo(ger._indice_minigame_atual)
		ger._indice_minigame_atual = -1
		var jogador_node = ger._obter_jogador()
		if jogador_node != null and jogador_node.has_method("set_physics_process"):
			jogador_node.set_physics_process(true)
		var hud = ger.get_node_or_null("HudObjetivos")
		if hud != null:
			hud.visible = true
	queue_free()


func _obter_valor(mulher: String, categoria: String) -> String:
	var infos: Dictionary = INFO.InfoMulheres[mulher]
	var k := categoria
	if not infos.has(k):
		k = categoria.to_lower()
	if not infos.has(k):
		for key in infos.keys():
			if String(key).to_lower() == categoria.to_lower():
				k = String(key)
				break
	return str(infos.get(k, ""))
