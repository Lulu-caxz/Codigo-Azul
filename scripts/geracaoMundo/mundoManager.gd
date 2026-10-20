extends Node3D

@onready var terreno = $Terreno
@onready var ruas = $Ruas
@onready var quadras = $Quadras
@onready var predios = $Predios


func _ready() -> void:
	gerar_mundo()


func gerar_mundo() -> void:
	# 1) alturas + tipos (sincrono) -> Global.mapa / Global.tipos
	terreno.gerar_alturas()

	# 2) ruas alteram Global.mapa / Global.tipos (ruas e pontes viram parte do terreno)
	ruas.gerar_ruas()

	quadras.gerar_quadras()   # use ruas.quarteiroes (Array[Rect2i], em celulas)
	#predios.gerar_predios()

	# 3) malha + colisao ja com as ruas (assincrono). Crie o jogador depois disso.
	await terreno.gerar_malha()
	
	print(Global.salaID)
