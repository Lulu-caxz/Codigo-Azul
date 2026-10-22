extends CanvasLayer

## Tela de contagem regressiva exibida durante a sincronizacao de inicio da rodada.
## O valor exibido e puxado de Global.tempo.

@onready var label_numero: Label = $CenterContainer/VBox/LabelNumero
@onready var label_texto: Label = $CenterContainer/VBox/LabelTexto

var _som_countdown: AudioStream
var _som_start: AudioStream
var _player_countdown: AudioStreamPlayer
var _player_start: AudioStreamPlayer

var _ultimo_numero: int = -1
var _tween: Tween


func _ready() -> void:
	layer = 20
	visible = false

	_som_countdown = load("res://sounds/countdown.mp3")
	_som_start = load("res://sounds/start.mp3")

	_player_countdown = AudioStreamPlayer.new()
	_player_countdown.volume_db = -6.0
	add_child(_player_countdown)

	_player_start = AudioStreamPlayer.new()
	_player_start.volume_db = -3.0
	add_child(_player_start)


func _process(_delta: float) -> void:
	if not visible:
		_ultimo_numero = -1
		return

	var numero := Global.tempo
	if numero != _ultimo_numero:
		# Toca o som de countdown toda vez que o numero desce.
		if _ultimo_numero != -1 and numero < _ultimo_numero:
			if _player_countdown and _som_countdown is AudioStream:
				_player_countdown.stream = _som_countdown
				_player_countdown.play()
		_ultimo_numero = numero
		label_numero.text = str(numero)
		_animar_numero()


func _animar_numero() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	label_numero.scale = Vector2(1.4, 1.4)
	label_numero.modulate.a = 0.0
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(label_numero, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_property(label_numero, "modulate:a", 1.0, 0.25)


func tocar_inicio() -> void:
	if _player_start and _som_start is AudioStream:
		_player_start.stream = _som_start
		_player_start.play()
