class_name HudObjetivos
extends CanvasLayer

# HUD minimo, criado pelo GerenciadorObjetivos (criar_hud = true).
# So reage aos sinais do gerenciador; nao guarda estado do jogo.

var _g: GerenciadorObjetivos
var _rodada: Label
var _progresso: Label
var _tempo: Label
var _dica: Label
var _aviso: Label
var _aviso_ate_ms := 0


func _ready() -> void:
	layer = 10

	var raiz := Control.new()
	raiz.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(raiz)
	raiz.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var caixa := VBoxContainer.new()
	caixa.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caixa.position = Vector2(20, 16)
	raiz.add_child(caixa)
	_rodada = _criar_rotulo(caixa, 26)
	_progresso = _criar_rotulo(caixa, 22)
	_tempo = _criar_rotulo(caixa, 22)

	_dica = _criar_rotulo(raiz, 24)
	_dica.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_dica.offset_top = -110.0
	_dica.offset_bottom = -70.0
	_dica.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dica.visible = false

	_aviso = _criar_rotulo(raiz, 32)
	_aviso.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_aviso.offset_top = 90.0
	_aviso.offset_bottom = 140.0
	_aviso.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_aviso.visible = false

	_rodada.text = "Preparando..."


func conectar(gerenciador: GerenciadorObjetivos) -> void:
	_g = gerenciador
	_g.rodada_preparada.connect(_ao_rodada_preparada)
	_g.progresso_mudou.connect(_ao_progresso)
	_g.contagem_inicio_atualizada.connect(_ao_contagem)
	_g.tempo_atualizado.connect(_ao_tempo)
	_g.alvo_proximo_mudou.connect(_ao_alvo)
	_g.rodada_concluida.connect(_ao_rodada_concluida)
	_g.rodada_perdida.connect(_ao_rodada_perdida)
	_g.geracao_falhou.connect(_ao_falha)


func _process(_delta: float) -> void:
	if _aviso.visible and _aviso_ate_ms > 0 and Time.get_ticks_msec() >= _aviso_ate_ms:
		_aviso.visible = false


func _criar_rotulo(pai: Node, tamanho: int) -> Label:
	var r := Label.new()
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_theme_font_size_override("font_size", tamanho)
	r.add_theme_constant_override("outline_size", 6)
	r.add_theme_color_override("font_outline_color", Color.BLACK)
	pai.add_child(r)
	return r


func _mostrar_aviso(texto: String, segundos: float) -> void:
	_aviso.text = texto
	_aviso.visible = true
	_aviso_ate_ms = 0 if segundos <= 0.0 else Time.get_ticks_msec() + int(segundos * 1000.0)


func _ao_rodada_preparada(numero: int, exigidos: int) -> void:
	_rodada.text = "Rodada %d" % numero
	_ao_progresso(0, exigidos)
	_aviso.visible = false


func _ao_progresso(concluidos: int, exigidos: int) -> void:
	_progresso.text = "Objetivos: %d/%d" % [concluidos, exigidos]


func _ao_contagem(segundos: int) -> void:
	_tempo.text = "Comeca em %ds" % segundos


@warning_ignore("integer_division")
func _ao_tempo(segundos: int) -> void:
	_tempo.text = "Tempo: %d:%02d" % [segundos / 60, segundos % 60]


func _ao_alvo(tipo: String) -> void:
	_dica.visible = not tipo.is_empty()
	if not tipo.is_empty():
		_dica.text = "[%s] Interagir: %s" % [_g.tecla_interacao(), tipo]


func _ao_rodada_concluida(numero: int) -> void:
	_mostrar_aviso("Rodada %d concluida!" % numero, 3.0)


func _ao_rodada_perdida(_numero: int, restantes: int) -> void:
	_tempo.text = "Tempo: 0:00"
	_mostrar_aviso("Tempo esgotado! Faltaram %d objetivo(s)." % restantes, 0.0)


func _ao_falha(motivo: String) -> void:
	_mostrar_aviso("Objetivos indisponiveis: " + motivo, 0.0)
