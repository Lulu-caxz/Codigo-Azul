extends CharacterBody3D

@export var velocidade: float = 5.0
## Altura maxima de degrau que o personagem sobe sozinho (0 = desliga).
@export var altura_degrau: float = 1.05
## Quanto maior, mais rapido a camera alcanca o jogador.
@export var suavidade_camera: float = 8.0
## Abaixo desta altura o jogador e considerado "caido do mundo".
@export var altura_queda: float = -30.0

@onready var sprite: AnimatedSprite3D = $AnimatedSprite3D

@export var camera: Camera3D


var _offset_camera := Vector3.ZERO
var _olhando := "baixo"
var _ultimo_chao := Vector3.ZERO


func _ready() -> void:
	
	
	floor_snap_length = 1.1   # cola no chao ao descer degraus

	# A camera usa a posicao que voce deixou no editor como distancia do jogador,
	# mas passa a seguir suavemente (nao sacode nos degraus).
	_offset_camera = camera.position + Vector3(0,6,6)
	camera.top_level = true
	camera.global_position = global_position + _offset_camera

	_ultimo_chao = global_position


# Coloca o jogador num ponto e leva a camera junto, sem "voar" ate la.
func teleportar(destino: Vector3) -> void:
	global_position = destino
	velocity = Vector3.ZERO
	_ultimo_chao = destino
	camera.global_position = destino + _offset_camera


func _physics_process(delta: float) -> void:
	var entrada := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var direcao := Vector3(entrada.x, 0.0, entrada.y)

	velocity.x = direcao.x * velocidade
	velocity.z = direcao.z * velocidade

	if is_on_floor():
		velocity.y = 0.0
		_ultimo_chao = global_position
	else:
		velocity += get_gravity() * delta

	if altura_degrau > 0.0 and is_on_floor() and direcao != Vector3.ZERO:
		_subir_degrau(direcao * velocidade * delta)

	move_and_slide()
	_atualizar_animacao(entrada)

	if global_position.y < altura_queda:
		teleportar(_ultimo_chao + Vector3.UP)


func _process(delta: float) -> void:
	# suavizacao independente do framerate
	var t := 1.0 - exp(-suavidade_camera * delta)
	camera.global_position = camera.global_position.lerp(global_position + _offset_camera, t)


# Se o movimento bate numa parede de ate `altura_degrau`, sobe em cima dela
func _subir_degrau(mov: Vector3) -> void:
	if not test_move(global_transform, mov):
		return
	var subida := Vector3.UP * altura_degrau
	if test_move(global_transform, subida):
		return   # teto baixo
	var elevado := global_transform.translated(subida)
	if not test_move(elevado, mov):
		global_position.y += altura_degrau


func _atualizar_animacao(entrada: Vector2) -> void:
	if entrada.length() > 0.1:
		if absf(entrada.x) > absf(entrada.y):
			_olhando = "direita" if entrada.x > 0.0 else "esquerda"
		else:
			_olhando = "baixo" if entrada.y > 0.0 else "cima"
		_tocar(_olhando)
	else:
		# usa idle_<direcao> se existir; senao o "idle" simples
		var idle := "idle_" + _olhando
		_tocar(idle if sprite.sprite_frames.has_animation(idle) else "idle")


func _tocar(nome: String) -> void:
	if sprite.animation != nome or not sprite.is_playing():
		sprite.play(nome)
