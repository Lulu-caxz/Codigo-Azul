extends CanvasLayer

@onready var color_rect: ColorRect = $ColorRect
@onready var texto: Label = $Label

func _ready() -> void:
	color_rect.visible = false
	color_rect.modulate.a = 0.0
	
	texto.visible = false
	# Ignora o mouse quando invisível para não bloquear cliques no jogo
	color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE 

# ==========================================
# 1. TRANSIÇÃO SIMPLES DE CENA
# ==========================================
func mudar_cena(caminho_cena: String, duracao: float = 0.5) -> void:
	await fade_out(duracao)
	get_tree().change_scene_to_file(caminho_cena)
	await fade_in(duracao)

# ==========================================
# 2. CARREGAMENTO ASSÍNCRONO / PESADO
# ==========================================
func iniciar_carregamento(duracao: float = 0.5) -> void:
	await fade_out(duracao)
	texto.visible = true

func finalizar_carregamento(duracao: float = 0.8, frames_estabilizacao: int = 12) -> void:
	# Quadros de aquecimento (warm-up) para a GPU compilar shaders
	# e a física estabilizar sem engasgar a animação de clarear a tela
	for i in frames_estabilizacao:
		await get_tree().process_frame
	
	texto.visible = false
	await fade_in(duracao)

# ==========================================
# FUNÇÕES AUXILIARES DE ANIMAÇÃO
# ==========================================
func fade_out(duracao: float) -> void:
	color_rect.visible = true
	color_rect.mouse_filter = Control.MOUSE_FILTER_STOP # Bloqueia a tela
	
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_IN_OUT)
	
	# Se você usa o Shader de transição, troque a linha abaixo por:
	# tween.tween_property(color_rect.material, "shader_parameter/progresso", 1.0, duracao)
	tween.tween_property(color_rect, "modulate:a", 1.0, duracao)
	
	await tween.finished

func fade_in(duracao: float) -> void:
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_IN_OUT)
	
	# Se você usa o Shader de transição, troque a linha abaixo por:
	# tween.tween_property(color_rect.material, "shader_parameter/progresso", 0.0, duracao)
	tween.tween_property(color_rect, "modulate:a", 0.0, duracao)
	
	await tween.finished
	
	color_rect.visible = false
	color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE # Libera a tela
