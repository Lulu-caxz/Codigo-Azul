extends Node2D

const INFO = preload("res://scripts/informacoesMulheres.gd")

@onready var label_ref: Label = $Referencia
@onready var input: LineEdit = $Input
@onready var botao_confirmar: Button = $Confirmar
@onready var adesivo_sprite: Sprite2D = $Sprite2D
@onready var btn_sair: Button = $Sair

var _saindo: bool = false
var _mulher: String
var _info_key: String
var _valor_correto: String
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
	# Botao confirmar: troca sprite para pressionado.
	var tex_normal := AtlasTexture.new()
	tex_normal.atlas = preload("res://assets/minigames/ConfirmarBotao.png")
	tex_normal.region = Rect2(0, 0, 112, 32)
	var tex_pressed := AtlasTexture.new()
	tex_pressed.atlas = preload("res://assets/minigames/ConfirmarBotao.png")
	tex_pressed.region = Rect2(0, 32, 112, 32)
	botao_confirmar.icon = tex_normal
	botao_confirmar.button_down.connect(func(): botao_confirmar.icon = tex_pressed)
	botao_confirmar.button_up.connect(func(): botao_confirmar.icon = tex_normal)
	botao_confirmar.pressed.connect(_verificar)

	btn_sair.pressed.connect(_sair_do_minigame)
	btn_sair.mouse_entered.connect(func(): _tocar_som("res://sounds/hover.mp3"))

	_sorteiar()


func _sorteiar() -> void:
	var nomes: Array = INFO.InfoMulheres.keys()
	_mulher = nomes[randi() % nomes.size()]
	var infos: Dictionary = INFO.InfoMulheres[_mulher]
	var keys: Array = infos.keys()
	_info_key = keys[randi() % keys.size()]
	_valor_correto = str(infos[_info_key])

	# Mostra apenas o nome da mulher; a categoria e indicada pelo adesivo.
	label_ref.text = "Ref.: %s" % _mulher

	# Atualiza o atlas texture do sprite adesivo conforme a chave sorteada.
	if adesivo_sprite != null and adesivo_sprite.texture is AtlasTexture:
		var at := adesivo_sprite.texture as AtlasTexture
		var chave_adesivo := _info_key.capitalize()
		if INFO.adesivos.has(chave_adesivo):
			at.region = INFO.adesivos[chave_adesivo]


func _verificar() -> void:
	if _saindo:
		return
	var resposta := _normalizar(input.text)
	var correto := _normalizar(_valor_correto)
	if resposta == correto:
		# Acertou: conclui o objetivo e fecha o minigame.
		var ger = get_tree().current_scene.find_child("Pontos", true, false)
		if ger != null and ger.get("_indice_minigame_atual") != null and ger._indice_minigame_atual >= 0:
			ger.concluir_objetivo(ger._indice_minigame_atual)
			ger._indice_minigame_atual = -1
			# Reabilita movimento do jogador.
			var jogador_node = ger._obter_jogador()
			if jogador_node != null and jogador_node.has_method("set_physics_process"):
				jogador_node.set_physics_process(true)
			# Mostra o HUD novamente.
			var hud = ger.get_node_or_null("HudObjetivos")
			if hud != null:
				hud.visible = true
		queue_free()
	else:
		# Errou: perde uma vida.
		Global.vidas = maxi(Global.vidas - 1, 0)
		_tocar_som("res://sounds/erro.mp3")
		# Atualiza o backend via script externo de banco.
		if Banco != null and Banco.has_method("atualizar_vida"):
			await Banco.atualizar_vida(Global.vidas)
		if _saindo or not is_inside_tree() or is_queued_for_deletion():
			return
		# Aviso em tempo real (complementar).
		if ConectSupa != null and ConectSupa.has_method("enviar_variavel"):
			ConectSupa.enviar_variavel({
				"tipo": "vida",
				"vidas": Global.vidas
			})
		_sorteiar()


func _sair_do_minigame() -> void:
	if _saindo:
		return
	_saindo = true
	btn_sair.disabled = true

	# O clique continua tocando depois que a cena do minigame for liberada.
	var som := AudioStreamPlayer.new()
	var s := load("res://sounds/clicar.mp3")
	if s is AudioStream:
		som.stream = s
		som.volume_db = -10.0
		som.finished.connect(som.queue_free)
		get_parent().add_child(som)
		som.play()

	_restaurar_jogo()
	queue_free()


func _restaurar_jogo() -> void:
	var ger = get_tree().current_scene.find_child("Pontos", true, false)
	if ger == null:
		return
	if ger.get("_indice_minigame_atual") != null:
		ger._indice_minigame_atual = -1
	if ger.get("_minigame_aberto") != null:
		ger._minigame_aberto = null
	var jogador_node = ger._obter_jogador()
	if jogador_node != null and jogador_node.has_method("set_physics_process"):
		jogador_node.set_physics_process(true)
	var hud = ger.get_node_or_null("HudObjetivos")
	if hud != null:
		hud.visible = true


func _normalizar(texto: String) -> String:
	var t := texto.strip_edges().to_lower()
	# Remove acentos basicos.
	t = t.replace("á", "a").replace("à", "a").replace("â", "a").replace("ã", "a")
	t = t.replace("é", "e").replace("ê", "e")
	t = t.replace("í", "i")
	t = t.replace("ó", "o").replace("ô", "o").replace("õ", "o")
	t = t.replace("ú", "u")
	t = t.replace("ç", "c")
	t = t.replace(" ", "")
	# Aceita "6" quando o valor correto for "06" (mes/dia).
	if t.is_valid_int():
		t = str(int(t))
	return t


# A sincronização com o banco é feita pelo script do jogador (player.gd).
