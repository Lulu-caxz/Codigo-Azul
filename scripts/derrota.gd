extends Node2D

const CENA_INICIAL := "res://scenes/TelaInicial.tscn"

@onready var _botao_voltar: Button = $UI/CenterContainer/VBox/Placa/BotaoVoltar

var _saindo := false


func _ready() -> void:
	# A Cidade pode estar com o mouse capturado quando a partida termina.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_botao_voltar.pressed.connect(_ao_voltar)
	_botao_voltar.grab_focus()


func _ao_voltar() -> void:
	if _saindo:
		return
	_saindo = true
	_botao_voltar.disabled = true
	await Transicao.mudar_cena(CENA_INICIAL, 0.6)
