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

var _passos: Array[AudioStream] = []
var _passo_player: AudioStreamPlayer
var _distancia_passo: float = 0.0
var _ultimo_passo: int = -1

var DISTANCIA_PASSO: float = 2

const PROJECT_REF: String = "ovkvgnnsxmpymcjclnzo"
const SUPABASE_KEY: String = "sb_publishable_3FDWeQxz2a8wEO-se44m-w_guLkTpR5"

var _gerenciador_objetivos: GerenciadorObjetivos
var _terreno: Node3D
var _http_posicao: HTTPRequest
var _atualizando_posicao: bool = false
var _jogo_iniciado: bool = false

func _ready() -> void:
	
	DISTANCIA_PASSO = log(velocidade) + 1
	sprite.speed_scale = velocidade/5
	floor_snap_length = 1.1   # cola no chao ao descer degraus
	
	# A camera usa a posicao que voce deixou no editor como distancia do jogador,
	# mas passa a seguir suavemente (nao sacode nos degraus).
	_offset_camera = camera.position + Vector3(0,6,6)
	camera.top_level = true
	camera.global_position = global_position + _offset_camera

	_ultimo_chao = global_position

	var s := load("res://sounds/passo.mp3")
	if s is AudioStream:
		_passos.append(s)
	_passo_player = AudioStreamPlayer.new()
	_passo_player.name = "PassoPlayer"
	_passo_player.volume_db = -5.0
	add_child(_passo_player)
	
	_http_posicao = HTTPRequest.new()
	_http_posicao.name = "HTTPPosicaoJogador"
	add_child(_http_posicao)

	var mundo := get_tree().current_scene
	if mundo != null:
		_gerenciador_objetivos = mundo.find_child(
			"Pontos",
			true,
			false
		) as GerenciadorObjetivos
		_terreno = mundo.find_child(
			"Terreno",
			true,
			false
		) as Node3D

	if _gerenciador_objetivos == null:
		push_warning("Player: GerenciadorObjetivos não encontrado.")
		return

	if not _gerenciador_objetivos.tempo_de_jogo_iniciado.is_connected(
		_ao_tempo_de_jogo_iniciado
	):
		_gerenciador_objetivos.tempo_de_jogo_iniciado.connect(
			_ao_tempo_de_jogo_iniciado
		)

func _ao_tempo_de_jogo_iniciado() -> void:
	_jogo_iniciado = true
	if _atualizando_posicao:
		return

	_atualizando_posicao = true
	_atualizar_posicao_periodicamente()


func _atualizar_posicao_periodicamente() -> void:
	while is_inside_tree() and _gerenciador_objetivos != null:
		if _gerenciador_objetivos.estado != GerenciadorObjetivos.Estado.RODADA_ATIVA:
			break

		await enviar_posicao_backend()

		if not is_inside_tree():
			break

		if _gerenciador_objetivos.estado != GerenciadorObjetivos.Estado.RODADA_ATIVA:
			break

		await get_tree().create_timer(1.0).timeout

	_atualizando_posicao = false


func enviar_posicao_backend() -> void:
	if not is_inside_tree() or Global.salaID.is_empty():
		return

	var posicao := [
		global_position.x,
		global_position.y,
		global_position.z
	]

	var url := "https://%s.supabase.co/rest/v1/salas" % PROJECT_REF
	url += "?id=eq." + Global.salaID.uri_encode() + "&select=id"

	var headers := PackedStringArray([
		"Content-Type: application/json",
		"apikey: " + SUPABASE_KEY,
		"Authorization: Bearer " + SUPABASE_KEY,
		"Prefer: return=representation"
	])

	var corpo := {
		"jogador_f_position": posicao + [Global.vidas]
	}

	var erro := _http_posicao.request(
		url,
		headers,
		HTTPClient.METHOD_PATCH,
		JSON.stringify(corpo)
	)

	if erro != OK:
		push_error("Player: falha ao iniciar envio da posição: %d" % erro)
		return

	var resposta = await _http_posicao.request_completed
	var resultado: int = resposta[0]
	var codigo: int = resposta[1]
	var texto: String = resposta[3].get_string_from_utf8()

	if resultado != HTTPRequest.RESULT_SUCCESS:
		push_error("Player: erro de conexão ao enviar posição.")
		return

	if codigo < 200 or codigo >= 300:
		push_error("Player: erro HTTP %d ao atualizar posição: %s" % [codigo, texto])


# Coloca o jogador num ponto e leva a camera junto, sem "voar" ate la.
func teleportar(destino: Vector3) -> void:
	global_position = destino
	velocity = Vector3.ZERO
	_ultimo_chao = destino
	camera.global_position = destino + _offset_camera


func _physics_process(delta: float) -> void:
	# So permite movimento apos o inicio da rodada (fim da contagem).
	if _gerenciador_objetivos != null:
		if _gerenciador_objetivos.estado == GerenciadorObjetivos.Estado.PREPARANDO_RODADA:
			_jogo_iniciado = false
	if not _jogo_iniciado:
		velocity = Vector3.ZERO
		move_and_slide()
		_atualizar_animacao(Vector2.ZERO)
		if global_position.y < altura_queda:
			teleportar(_ultimo_chao + Vector3.UP)
		return

	var entrada := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var direcao := Vector3(entrada.x, 0.0, entrada.y)

	# Ajusta a velocidade conforme o tipo de bloco sob o jogador.
	var mult_vel := 1.0
	if _terreno != null:
		var local := _terreno.to_local(global_position)
		var s = Global.tamanho_cubo
		var x := floori(local.x / s)
		var z := floori(local.z / s)
		if x >= 0 and z >= 0 and x < Global.largura and z < Global.profundidade:
			var tipo_bloco := int(Global.tipos[x * Global.profundidade + z])
			if tipo_bloco == 2 or tipo_bloco == 1:          # grama -> 1/3 da velocidade
				mult_vel = 1.0 / 3.0
				sprite.speed_scale = (velocidade/5)/3
			else: 
				sprite.speed_scale = (velocidade/5)

	velocity.x = direcao.x * velocidade * mult_vel
	velocity.z = direcao.z * velocidade * mult_vel

	if is_on_floor():
		velocity.y = 0.0
		_ultimo_chao = global_position
	else:
		velocity += get_gravity() * delta

	if altura_degrau > 0.0 and is_on_floor() and direcao != Vector3.ZERO and mult_vel > 0.0:
		_subir_degrau(direcao * velocidade * mult_vel * delta)

	move_and_slide()
	_atualizar_animacao(entrada)

	var movendo := entrada.length() > 0.1
	if movendo and is_on_floor() and not _passos.is_empty():
		var vel_horizontal := Vector2(velocity.x, velocity.z).length()
		_distancia_passo += vel_horizontal * delta
		if _distancia_passo >= DISTANCIA_PASSO:
			_distancia_passo = fmod(_distancia_passo, DISTANCIA_PASSO)
			var idx := randi() % _passos.size()
			if _passos.size() > 1 and idx == _ultimo_passo:
				idx = (idx + 1 + randi() % (_passos.size() - 1)) % _passos.size()
			_ultimo_passo = idx
			_passo_player.stream = _passos[idx]
			# Alterna aleatoriamente o pitch a cada passo para variar o som.
			_passo_player.pitch_scale = randf_range(0.85, 1.15)
			_passo_player.play()
	else:
		_distancia_passo = 0.0

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
