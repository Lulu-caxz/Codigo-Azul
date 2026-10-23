extends Node2D

const INFO = preload("res://scripts/informacoesMulheres.gd")

@onready var label_ref: Label = $Textos/Referencia

var _mulher: String
var _adesivo1: String
var _adesivo2: String
var _placa_info1_correta: int = 0
var _placa_info2_correta: int = 1

var _valvula_sprites: Array = []
var _botoes: Array = []
var _giradas: Array = [false, false, false, false]
var _historico: Array = []
var _bloqueado: bool = false

var _som_ui: AudioStreamPlayer


func _tocar_som(caminho: String) -> void:
	if _som_ui == null:
		_som_ui = AudioStreamPlayer.new()
		add_child(_som_ui)
	var s := load(caminho)
	if s is AudioStream:
		_som_ui.stream = s
		_som_ui.play()


func _ready() -> void:
	for i in 4:
		var v = get_node("Valvulas/Valvula%d" % (i + 1))
		var sp: Sprite2D = v.get_node("Sprite2D")
		_valvula_sprites.append(sp)

		var btn := Button.new()
		btn.name = "BotaoValvula"
		btn.flat = true
		btn.text = ""
		btn.size = Vector2(48, 48)
		btn.position = Vector2(-24, -24)
		btn.mouse_filter = Control.MOUSE_FILTER_STOP
		btn.focus_mode = Control.FOCUS_NONE
		v.add_child(btn)
		btn.pressed.connect(_girar_valvula.bind(i))
		_botoes.append(btn)

	_sorteiar()


func _girar_valvula(i: int) -> void:
	if _bloqueado:
		return
	if i < 0 or i >= 4:
		return
	if _giradas[i]:
		return

	_giradas[i] = true
	var sp: Sprite2D = _valvula_sprites[i]
	if sp.texture is AtlasTexture:
		var at := sp.texture as AtlasTexture
		at.region.position.x += 48.0

	_historico.append(i)

	if _historico.size() == 1:
		if i != _placa_info1_correta:
			_errar()
	elif _historico.size() == 2:
		if i != _placa_info2_correta:
			_errar()
		else:
			_acertar()
	else:
		_errar()


func _errar() -> void:
	if _bloqueado:
		return
	_bloqueado = true
	for btn in _botoes:
		if is_instance_valid(btn):
			btn.disabled = true

	Global.vidas = maxi(Global.vidas - 1, 0)
	_tocar_som("res://sounds/erro.mp3")
	if Banco != null and Banco.has_method("atualizar_vida"):
		await Banco.atualizar_vida(Global.vidas)
	if ConectSupa != null and ConectSupa.has_method("enviar_variavel"):
		ConectSupa.enviar_variavel({
			"tipo": "vida",
			"vidas": Global.vidas
		})

	# Bloqueia novas jogadas por 1 segundo antes de resetar.
	await get_tree().create_timer(1.0).timeout

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


func _sorteiar() -> void:
	var nomes: Array = INFO.InfoMulheres.keys()
	_mulher = nomes[randi() % nomes.size()]

	var adesivo_keys: Array = INFO.adesivos.keys()
	var idx1 := randi() % adesivo_keys.size()
	var idx2 := randi() % adesivo_keys.size()
	while idx2 == idx1:
		idx2 = randi() % adesivo_keys.size()
	_adesivo1 = String(adesivo_keys[idx1])
	_adesivo2 = String(adesivo_keys[idx2])

	_placa_info1_correta = randi() % 4
	_placa_info2_correta = randi() % 4
	while _placa_info2_correta == _placa_info1_correta:
		_placa_info2_correta = randi() % 4

	# Reset valvulas
	_historico.clear()
	for i in 4:
		_giradas[i] = false
		var sp: Sprite2D = _valvula_sprites[i]
		if sp.texture is AtlasTexture:
			var at := sp.texture as AtlasTexture
			at.region.position.x = 0.0

	# Pool de outras mulheres
	var outras1: Array = []
	var outras2: Array = []
	for n in nomes:
		if String(n) != _mulher:
			outras1.append(n)
			outras2.append(n)
	outras1.shuffle()
	outras2.shuffle()

	var valores1: Array = []
	var valores2: Array = []
	var u1 := 0
	var u2 := 0
	for j in 4:
		if j == _placa_info1_correta:
			valores1.append(_obter_valor(_mulher, _adesivo1))
		else:
			var m = outras1[u1 % outras1.size()]
			u1 += 1
			valores1.append(_obter_valor(String(m), _adesivo1))
	for j in 4:
		if j == _placa_info2_correta:
			valores2.append(_obter_valor(_mulher, _adesivo2))
		else:
			var m = outras2[u2 % outras2.size()]
			u2 += 1
			valores2.append(_obter_valor(String(m), _adesivo2))

	for j in 4:
		var placa = get_node("Textos/Placas/Placa%d" % (j + 1))
		placa.get_node("Info1").text = String(valores1[j])
		placa.get_node("Info2").text = String(valores2[j])

	var ad1: Sprite2D = get_node("Adesivos/1")
	if ad1.texture is AtlasTexture:
		(ad1.texture as AtlasTexture).region = INFO.adesivos[_adesivo1]
	var ad2: Sprite2D = get_node("Adesivos/2")
	if ad2.texture is AtlasTexture:
		(ad2.texture as AtlasTexture).region = INFO.adesivos[_adesivo2]

	label_ref.text = "Ref.: %s" % _mulher


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
