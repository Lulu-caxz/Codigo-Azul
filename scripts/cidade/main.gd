extends Node3D

@onready var camera: Camera3D = $Camera3D

const SPEED: float = 20.0
var sensitivity: float = 0.003
var mapa_cena: PackedScene = preload("res://scenes/cidade/mapa.tscn")

func _ready() -> void:
	# Captura o rato automaticamente para poderes rodar a câmara
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	var mapa_instancia = mapa_cena.instantiate()
	mapa_instancia.name = "MapaGerado"
	add_child(mapa_instancia)

# Lê o movimento do rato
func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		# Roda o corpo principal no eixo Y (esquerda/direita)
		camera.rotation.y -= event.relative.x * sensitivity
		# Roda apenas a câmara no eixo X (cima/baixo) e limita para não dar a volta completa
		camera.rotation.x -= event.relative.y * sensitivity
		camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-89), deg_to_rad(89))
	
	# Pressiona ESC (ui_cancel) para libertar o rato caso precises de mexer no editor
	if event.is_action_pressed("ui_cancel"):
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _process(delta: float) -> void:
	var mudanca = Vector3.ZERO
	
	if Input.is_action_pressed("ui_up"):
		mudanca.z -= 1
	if Input.is_action_pressed("ui_down"):
		mudanca.z += 1
	if Input.is_action_pressed("ui_left"):
		mudanca.x -= 1
	if Input.is_action_pressed("ui_right"):
		mudanca.x += 1
	if Input.is_action_pressed("ctrl"): # Certifique-se de que a ação "ctrl" existe no Input Map
		mudanca.y -= 1
	if Input.is_action_pressed("ui_accept"):
		mudanca.y += 1
		
	if mudanca != Vector3.ZERO:
		mudanca = mudanca.normalized()
		# ALTERAÇÃO AQUI: Usa a base da CÂMERA para mover na direção que ela está olhando
		var direcao = (camera.global_transform.basis * mudanca).normalized()
		camera.position += direcao * SPEED * delta
