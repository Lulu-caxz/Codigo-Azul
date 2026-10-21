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
	
	await Transicao.iniciar_carregamento(0.0)

	# 1. Trava a tela no preto absoluto antes de qualquer processamento pesado
	await get_tree().process_frame
	await get_tree().process_frame

	# 2. Instancia o mundo e o player (com física pausada para não cair no vazio)
	mundo = MUNDO_CENA.instantiate()
	mundo.name = "MundoManager"

	player = PLAYER_CENA.instantiate()
	player.name = "Player"
	player.set_physics_process(false)

	# 3. Assim que a matriz lógica do mapa estiver pronta, posiciona o player e a câmera
	mundo.dados_prontos.connect(func():
		mundo.add_child(player)
		player.teleportar(mundo.ponto_de_nascimento())
		var cam_p: Camera3D = player.get_node_or_null("Camera3D")
		if cam_p:
			camera_teste.current = false
			cam_p.current = true
	, CONNECT_ONE_SHOT)

	add_child(mundo)

	await mundo.mundo_pronto
	
	await Transicao.finalizar_carregamento(1.0)
	player.set_physics_process(true)


	for i in 10:
		await get_tree().process_frame

	player.teleportar(player.global_position)
	await get_tree().process_frame




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
