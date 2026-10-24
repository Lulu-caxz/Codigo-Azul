extends Node2D

@onready var telas: Array[Control] = [
	$Tela1,
	$Tela2,
	$Tela3,
	$Tela4,
	$Tela5,
	$Tela6,
	$Tela7
]

@onready var btn_voltar: Button = $VOLTAR
@onready var btn_anterior: Button = $VoltarPagina
@onready var btn_proximo: Button = $PassarPagina

var indice_atual: int = 0

@onready var _som_ui: AudioStreamPlayer

func _tocar_som_ui(caminho: String) -> void:
	if _som_ui == null:
		_som_ui = AudioStreamPlayer.new()
		add_child(_som_ui)
	var s := load(caminho)
	if s is AudioStream:
		_som_ui.stream = s
		_som_ui.play()

func _ready() -> void:
	_atualizar_telas()

	btn_anterior.pressed.connect(func():
		_tocar_som_ui("res://sounds/clicar.mp3")
		_ir_para_anterior()
	)
	btn_proximo.pressed.connect(func():
		_tocar_som_ui("res://sounds/clicar.mp3")
		_ir_para_proximo()
	)
	btn_voltar.pressed.connect(func():
		_tocar_som_ui("res://sounds/clicar.mp3")
		_voltar_para_tela_inicial()
	)

	btn_anterior.mouse_entered.connect(func(): _tocar_som_ui("res://sounds/hover.mp3"))
	btn_proximo.mouse_entered.connect(func(): _tocar_som_ui("res://sounds/hover.mp3"))
	btn_voltar.mouse_entered.connect(func(): _tocar_som_ui("res://sounds/hover.mp3"))

	# Inicialmente, o botão de voltar à página está desabilitado (na 1ª página)
	_atualizar_botoes_navegacao()

func _atualizar_telas() -> void:
	for i in range(telas.size()):
		if i == indice_atual:
			telas[i].visible = true
		else:
			telas[i].visible = false

func _ir_para_anterior() -> void:
	if indice_atual > 0:
		indice_atual -= 1
		_atualizar_telas()
		_atualizar_botoes_navegacao()

func _ir_para_proximo() -> void:
	if indice_atual < telas.size() - 1:
		indice_atual += 1
		_atualizar_telas()
		_atualizar_botoes_navegacao()

func _atualizar_botoes_navegacao() -> void:
	btn_anterior.disabled = (indice_atual == 0)
	btn_proximo.disabled = (indice_atual == telas.size() - 1)

func _voltar_para_tela_inicial() -> void:
	# Usa a transição global para voltar à TelaInicial com transição suave
	await Transicao.mudar_cena("res://scenes/TelaInicial.tscn", 0.8)
