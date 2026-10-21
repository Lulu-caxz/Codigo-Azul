
extends Node3D

const MUNDO_CENA: PackedScene = preload("res://scenes/cidade/mapa.tscn")
const PLAYER_CENA: PackedScene = preload("res://scenes/cidade/player.tscn")

@onready var camera_teste: Camera3D = $Camera3D

var mundo: Node3D
var player: CharacterBody3D
var modo_camera_teste: bool = false


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	camera_teste.current = true

	# Instancia o mundo. O próprio MundoManager inicia a geração.
	mundo = MUNDO_CENA.instantiate()
	mundo.name = "MundoManager"
	add_child(mundo)

	# Aguarda a geração do mundo terminar.
	await mundo.mundo_pronto

	# Cria o personagem dentro do mundo gerado.
	player = PLAYER_CENA.instantiate()
	player.name = "Player"
	mundo.add_child(player)

	# Posição provisória de nascimento.
	player.teleportar(mundo.ponto_de_nascimento())

	# Começa no modo de jogo, com a câmera do jogador.
	var camera_player: Camera3D = player.get_node_or_null("Camera3D")
	if camera_player:
		camera_teste.current = false
		camera_player.current = true

	print("Mundo pronto e jogador criado!")


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		modo_camera_teste = false
		alternar_camera()


	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F1:
			modo_camera_teste = not modo_camera_teste
			alternar_camera()


func alternar_camera() -> void:
	if not is_instance_valid(player):
		return

	var camera_player: Camera3D = player.get_node_or_null("Camera3D")

	if camera_player == null:
		push_warning("O Player não possui um nó Camera3D.")
		return

	camera_teste.current = modo_camera_teste
	camera_player.current = not modo_camera_teste

	if modo_camera_teste:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
