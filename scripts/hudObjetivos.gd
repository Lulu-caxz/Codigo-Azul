class_name HudObjetivos
extends CanvasLayer

## Interface visual (HUD) moderna para o sistema de objetivos e rodadas.
## Os componentes visuais estao definidos na cena hud_objetivos.tscn.

@onready var label_rodada: Label = %LabelRodada
@onready var label_titulo_tempo: Label = %LabelTituloTempo
@onready var label_tempo: Label = %LabelTempo
@onready var label_progresso: Label = %LabelProgresso
@onready var barra_progresso: ProgressBar = %BarraProgresso

@onready var prompt_container: Control = %PromptContainer
@onready var card_prompt: Control = %CardPrompt
@onready var label_tecla: Label = %LabelTecla
@onready var label_acao: Label = %LabelAcao

@onready var banner_container: Control = %BannerContainer
@onready var card_banner: PanelContainer = %CardBanner
@onready var label_aviso: Label = %LabelAviso

var _gerenciador: GerenciadorObjetivos
var _tween_prompt: Tween
var _tween_banner: Tween
var _tween_barra: Tween


func _ready() -> void:
	prompt_container.visible = false
	prompt_container.modulate.a = 0.0

	banner_container.visible = false
	banner_container.modulate.a = 0.0


## Vincula este HUD ao GerenciadorObjetivos e escuta seus sinais.
func conectar(gerenciador: GerenciadorObjetivos) -> void:
	if _gerenciador == gerenciador:
		return

	_gerenciador = gerenciador
	_gerenciador.rodada_preparada.connect(_ao_rodada_preparada)
	_gerenciador.progresso_mudou.connect(_ao_progresso)
	_gerenciador.contagem_inicio_atualizada.connect(_ao_contagem)
	_gerenciador.tempo_atualizado.connect(_ao_tempo)
	_gerenciador.alvo_proximo_mudou.connect(_ao_alvo)
	_gerenciador.rodada_concluida.connect(_ao_rodada_concluida)
	_gerenciador.rodada_perdida.connect(_ao_rodada_perdida)
	_gerenciador.geracao_falhou.connect(_ao_falha)

	if _gerenciador.tecla_interacao():
		label_tecla.text = _gerenciador.tecla_interacao()


# -----------------------------------------------------------------------------
#  REACAO AOS SINAIS DO GERENCIADOR
# -----------------------------------------------------------------------------
func _ao_rodada_preparada(numero: int, exigidos: int) -> void:
	label_rodada.text = "RODADA %d" % numero

	label_titulo_tempo.text = "COMEÇA EM"
	barra_progresso.max_value = maxf(float(exigidos), 1.0)
	barra_progresso.value = 0.0
	label_progresso.text = "0 / %d" % exigidos

	_esconder_banner()


func _ao_contagem(segundos: int) -> void:
	label_titulo_tempo.text = "COMEÇA EM"
	label_tempo.text = "%ds" % segundos


@warning_ignore("integer_division")
func _ao_tempo(segundos: int) -> void:
	label_titulo_tempo.text = "TEMPO RESTANTE"
	label_tempo.text = "%02d:%02d" % [segundos / 60, segundos % 60]
	
	Global.tempo = segundos
	
	if segundos <= 15:
		# Alerta de tempo acabando: texto avermelhado
		label_tempo.modulate = Color(1.0, 0.35, 0.35)
	else:
		label_tempo.modulate = Color.WHITE


func _ao_progresso(concluidos: int, exigidos: int) -> void:
	label_progresso.text = "%d / %d" % [concluidos, exigidos]

	if _tween_barra and _tween_barra.is_valid():
		_tween_barra.kill()
	_tween_barra = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_tween_barra.tween_property(barra_progresso, "value", float(concluidos), 0.3)


func _ao_alvo(tipo: String) -> void:
	if tipo.is_empty():
		_animar_prompt(false)
		return

	if _gerenciador:
		label_tecla.text = _gerenciador.tecla_interacao()

	label_acao.text = "Colocar %s" % tipo.capitalize()
	_animar_prompt(true)


func _ao_rodada_concluida(numero: int) -> void:
	_mostrar_banner("Rodada %d Concluída!" % numero, 3.0, Color(0.3, 0.85, 0.5))


func _ao_rodada_perdida(_numero: int, restantes: int) -> void:
	label_tempo.text = "00:00"
	label_tempo.modulate = Color(1.0, 0.3, 0.3)
	_mostrar_banner("Tempo esgotado! Faltaram %d objetivo(s)." % restantes, 4.0, Color(0.9, 0.3, 0.3))


func _ao_falha(motivo: String) -> void:
	_mostrar_banner("Objetivos indisponíveis: %s" % motivo, 5.0, Color(0.9, 0.3, 0.3))


# -----------------------------------------------------------------------------
#  ANIMACAO E ESTILO VISUAL
# -----------------------------------------------------------------------------

func _animar_prompt(mostrar: bool) -> void:
	if _tween_prompt and _tween_prompt.is_valid():
		_tween_prompt.kill()

	_tween_prompt = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

	if mostrar:
		prompt_container.visible = true
		_tween_prompt.tween_property(prompt_container, "modulate:a", 1.0, 0.2)
	else:
		_tween_prompt.tween_property(prompt_container, "modulate:a", 0.0, 0.15)
		_tween_prompt.tween_callback(func(): prompt_container.visible = false)


func _mostrar_banner(texto: String, duracao: float, cor_borda: Color) -> void:
	if _tween_banner and _tween_banner.is_valid():
		_tween_banner.kill()

	label_aviso.text = texto
	banner_container.visible = true
	banner_container.modulate.a = 0.0
	banner_container.scale = Vector2(0.95, 0.95)

	# Atualiza a cor de destaque da borda do banner
	var estilo: StyleBoxFlat = card_banner.get_theme_stylebox("panel") as StyleBoxFlat
	if estilo:
		estilo = estilo.duplicate() as StyleBoxFlat
		estilo.border_color = cor_borda
		card_banner.add_theme_stylebox_override("panel", estilo)

	_tween_banner = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	_tween_banner.parallel().tween_property(banner_container, "modulate:a", 1.0, 0.25)
	_tween_banner.parallel().tween_property(banner_container, "scale", Vector2.ONE, 0.25)

	if duracao > 0.0:
		_tween_banner.tween_interval(duracao)
		_tween_banner.tween_property(banner_container, "modulate:a", 0.0, 0.3)
		_tween_banner.tween_callback(func(): banner_container.visible = false)


func _esconder_banner() -> void:
	if _tween_banner and _tween_banner.is_valid():
		_tween_banner.kill()
	banner_container.visible = false
	banner_container.modulate.a = 0.0
