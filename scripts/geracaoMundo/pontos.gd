class_name GerenciadorObjetivos
extends Node3D

# =============================================================================
#  GERENCIADOR DE OBJETIVOS E RODADAS
# =============================================================================
# Filho do MundoManager (criado por ele em _ready, ver alteracoes no mundo_manager.gd).
#
#  * Global.pontos_position e a UNICA fonte de verdade dos objetivos ativos:
#        [x, y, z, "incompleto"|"completo", "tipo"]   (x, y, z = coordenadas GLOBAIS)
#    As instancias 3D (_nos) sao so a parte visual, com o mesmo indice da lista.
#
#  * dados_prontos -> calcula os candidatos (calcadas) e ja preenche
#                     Global.pontos_position da rodada 1, ANTES do PATCH do mundo_manager.
#  * mundo_pronto  -> instancia os objetivos e inicia a contagem (inicio_timer do backend).
#  * Interacao     -> tecla da acao "interagir" (padrao E) perto de um objetivo incompleto.
#
# Estados: AGUARDANDO_MUNDO -> PREPARANDO_RODADA (contagem ate o inicio) -> RODADA_ATIVA
#          -> RODADA_CONCLUIDA (-> proxima rodada)  |  RODADA_PERDIDA (nao avanca sozinho)
#
# Para adicionar um tipo novo: coloque-o em pesos_tipos e (opcional) uma cena em cenas_tipos.
# =============================================================================

signal tempo_de_jogo_iniciado
signal estado_mudou(novo: int, anterior: int)
signal rodada_preparada(numero: int, exigidos: int)
signal progresso_mudou(concluidos: int, exigidos: int)
signal objetivo_concluido(indice: int, tipo: String)
signal contagem_inicio_atualizada(segundos: int)
signal tempo_atualizado(segundos: int)
signal rodada_concluida(numero: int)
signal rodada_perdida(numero: int, restantes: int)
signal alvo_proximo_mudou(tipo: String)   # "" quando nao ha objetivo ao alcance
signal geracao_falhou(motivo: String)

enum Estado { AGUARDANDO_MUNDO, PREPARANDO_RODADA, RODADA_ATIVA, RODADA_CONCLUIDA, RODADA_PERDIDA }

# Posicoes dentro de cada entrada de pontos_position
const I_X := 0
const I_Y := 1
const I_Z := 2
const I_ESTADO := 3
const I_TIPO := 4

const INCOMPLETO := "incompleto"
const COMPLETO := "completo"

# Tipos de bloco (iguais aos de Global.tipos)
const T_RUA := 4
const T_PONTE := 5
const T_CALCADA := 6
const T_QUADRA := 7

const DIRS4 := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

const MAX_TENTATIVAS_ENVIO := 3
const INTERVALO_RETENTATIVA := 5.0

# -----------------------------------------------------------------------------
#  CONFIGURACOES
# -----------------------------------------------------------------------------
@export_group("Rodadas")
## Objetivos da rodada 1.
@export_range(1, 100) var objetivos_iniciais: int = 5
## Objetivos somados a cada rodada seguinte (5, 8, 11, 14, 17...).
@export_range(0, 50) var objetivos_adicionais_por_rodada: int = 3
## Duracao de cada rodada, em segundos (o mesmo valor vai para duracao_timer no backend).
@export_range(5.0, 3600.0, 1.0) var duracao_rodada: float = Global.duracao_partida
## Segundos entre preparar uma rodada e o cronometro comecar (igual ao +10 s do backend).
var atraso_inicio_rodada: int = 5
## Pausa depois de concluir uma rodada, antes de preparar a proxima.
@export_range(0.0, 30.0, 0.5) var pausa_apos_conclusao: float = 3.0

@export_group("Tipos de objetivo")
## Peso de sorteio de cada tipo. Chave = nome do tipo. Peso 0 desliga o tipo.
@export var pesos_tipos: Dictionary = {"bueiro": 1.0, "pluviometro": 1.0, "antena": 1.0}
## Sprite 2D de cada tipo (chave = nome do tipo, valor = Texture2D).
## Sem textura, usa um ponto simples colorido gerado por codigo.
@export var texturas_tipos: Dictionary = {}
## SpriteFrames (animacao) de cada tipo para o objeto colocado (chave = tipo, valor = SpriteFrames).
@export var frames_tipos: Dictionary = {}
## Tamanho individual de cada tipo (chave = tipo, valor = float). Se ausente, usa tamanho_sprite.
@export var tamanhos_tipos: Dictionary = {}

@export_group("Sprite na cidade")
## Largura do sprite no mundo (unidades).
@export_range(0.1, 5.0, 0.05) var tamanho_sprite: float = 0.8
## Altura do centro do sprite acima da calcada.
@export_range(0.0, 5.0, 0.05) var altura_sprite: float = 0.8
## Some quando o objetivo e concluido (desligado = fica verde e menor).
@export var ocultar_ao_completar: bool = true

@export_group("Posicionamento")
## Distancia minima desejada entre objetivos (unidades do mundo).
@export_range(1.0, 200.0, 0.5) var distancia_min_entre_objetivos: float = 28.0
## Se faltar espaco, a distancia minima vai diminuindo ate este piso (nunca abaixo de 1).
@export_range(1.0, 100.0, 0.5) var distancia_min_piso: float = 6.0
## Descarta calcadas a ate N celulas de uma quadra (onde ficam os predios). 0 = sem filtro.
@export_range(0, 4) var margem_quadra_celulas: int = 1
## Se o filtro acima deixar menos candidatos que isso, ele e relaxado para 0.
@export var candidatos_minimos: int = 30
## So usa calcadas alcancaveis a pe a partir do ponto de nascimento (rua/ponte/calcada).
@export var exigir_acessibilidade: bool = true
## Maior degrau (em blocos) entre celulas vizinhas que o jogador consegue subir.
@export_range(0, 4) var degrau_max_acessivel: int = 1
## Candidatos sorteados por objetivo; vence o mais distante dos ja escolhidos.
@export_range(1, 200) var tentativas_por_ponto: int = 40
## Usa Global.seed para sortear (mesma semente + rodada = mesmo resultado). Desligado = aleatorio.
@export var usar_semente_do_mundo: bool = false

@export_group("Interacao")
## Acao de input para concluir objetivos. Se nao existir no InputMap, e criada com a tecla E.
@export var acao_interagir: StringName = &"interagir"
## Alcance horizontal da interacao (unidades do mundo).
@export_range(0.5, 20.0, 0.1) var raio_interacao: float = 3.0
## Diferenca vertical maxima entre o jogador e o objetivo.
@export_range(0.5, 20.0, 0.1) var tolerancia_vertical: float = 3.5
## Nome do no do jogador dentro do MundoManager (main.gd usa "Player").
@export var nome_no_jogador: String = "Player"

@export_group("Interface (HUD)")
## Cena com a interface grafica moderna do HUD.
@export var cena_hud: PackedScene = preload("res://scenes/cidade/hud.tscn")
## Se falso, nao instancia a interface visual.
@export var criar_hud: bool = true

@export_group("Ligacao")
@export var no_mundo: NodePath = ^".."
@export var no_terreno: NodePath = ^"../Terreno"

@export_group("Backend")
## Publica no Supabase a fotografia completa da rodada (identificador, estado,
## timer, objetivos, eventos e abrigo) a cada mudanca.
@export var sincronizar_backend: bool = true

@export_group("Minigame")
## Caminho da cena do minigame da antena.
@export var caminho_minigame_antena: String = "res://scenes/minigames/mini_game_antena.tscn"
## Caminho da cena do minigame do bueiro.
@export var caminho_minigame_bueiro: String = "res://scenes/minigames/mini_game_bueiro.tscn"
## Caminho da cena do minigame do pluviometro.
@export var caminho_minigame_pluviometro: String = "res://scenes/minigames/mini_game_pluviometro.tscn"

@export_group("Chuva de granizo")
## Duracao da chuva, em segundos.
@export_range(1.0, 60.0, 0.5) var duracao_chuva: float = 8.0
## Intervalo entre perdas de vida enquanto o jogador esta fora do abrigo.
@export_range(0.5, 10.0, 0.5) var intervalo_dano_chuva: float = 2.0

@export_group("Depuracao")
@export var imprimir_relatorio: bool = true
## F9 conclui todos os objetivos da rodada (para testar a progressao).
@export var depuracao_atalhos: bool = false

# -----------------------------------------------------------------------------
#  ESTADO
# -----------------------------------------------------------------------------
var rodada_atual: int = 0
var estado: Estado = Estado.AGUARDANDO_MUNDO
## Instante (unix, segundos) em que o cronometro da rodada atual comeca.
var inicio_unix: float = 0.0
## Motivo da ultima derrota: "tempo" ou "vidas" (lido pelo HUD).
var motivo_derrota: String = ""

var _eventos_executados: Array[int] = []
var _duracao_atual: float = 0.0
var _fim_pausa_unix: float = 0.0
var _dados_prontos := false
var _mundo_pronto := false
var _limpando := false
var _ultimo_segundo := -1
var _alvo_atual := -1
var _alvo_tipo_atual := ""

var _mundo: Node
var _terreno: Node3D
var _container: Node3D
var _jogador: Node3D
var _nos: Array[Node3D] = []

var _abrigo_porta: Vector3 = Vector3.ZERO
var _abrigo_centro: Vector3 = Vector3.ZERO
var _abrigo_carregado: bool = false
var _indice_minigame_atual: int = -1
var _minigame_aberto: Node = null
var _dentro_abrigo: bool = false
var _chuva_ativa: bool = false
var _aviso_chuva_visivel: bool = false
var _efeito_chuva: CanvasLayer
var _particulas_chuva: GPUParticles2D

var _rng := RandomNumberGenerator.new()
var _cand_idx := PackedInt32Array()    # indice x * profundidade + z de cada candidato
var _cand_xz := PackedVector2Array()   # centro do candidato (unidades locais do terreno)

var _http: HTTPRequest
var _contagem: CanvasLayer
var _enviando := false
var _reenviar := false
var _retry_agendado := false
var _ultima_rodada_publicada := -1
var _projeto_ref := ""
var _chave := ""
var _derrota_iniciada := false
var _perdida_publicada := false
var _tipos_sem_cena_avisados: Dictionary = {}

# --- Som de objetivo concluido ---
var _som_concluido: AudioStream
var _som_player: AudioStreamPlayer

func _criar_contagem() -> void:
	var cena_contagem := load("res://scenes/cidade/contagem.tscn")
	if cena_contagem is PackedScene:
		_contagem = cena_contagem.instantiate() as CanvasLayer
		if _contagem != null:
			add_child(_contagem)
			_contagem.visible = false


func _criar_hud() -> void:
	if not criar_hud:
		return

	# Reutiliza HUD ja existente na arvore se houver
	var hud_existente = get_node_or_null("HudObjetivos")
	if hud_existente != null:
		if hud_existente.has_method("conectar"):
			hud_existente.conectar(self)
	else:
		if cena_hud != null:
			var hud = cena_hud.instantiate()
			hud.name = "HudObjetivos"
			add_child(hud)
			if hud.has_method("conectar"):
				hud.conectar(self)
		else:
			push_warning("Objetivos: Nenhuma cena de HUD configurada em cena_hud.")

	pass

func _ready() -> void:
	_mundo = get_node_or_null(no_mundo)
	_terreno = get_node_or_null(no_terreno) as Node3D

	if _mundo == null or _terreno == null:
		push_error("Objetivos: nao encontrei o mundo ou o terreno.")
		set_process(false)
		return


	_container = Node3D.new()
	_container.name = "InstanciasObjetivos"
	add_child(_container)

	_garantir_acao_interagir()
	_carregar_credenciais()

	_http = HTTPRequest.new()
	_http.name = "HTTPObjetivos"
	_http.timeout = 10.0
	add_child(_http)

	_som_concluido = load("res://sounds/objetivoConcluido.mp3")
	_som_player = AudioStreamPlayer.new()
	_som_player.name = "SomObjetivoConcluido"
	_som_player.volume_db = -4.0
	add_child(_som_player)

	_mundo.dados_prontos.connect(_ao_dados_prontos)
	_mundo.mundo_pronto.connect(_ao_mundo_pronto)


func _exit_tree() -> void:
	_limpando = true


# -----------------------------------------------------------------------------
#  API PUBLICA
# -----------------------------------------------------------------------------
func objetivos_da_rodada(numero: int) -> int:
	return maxi(objetivos_iniciais + objetivos_adicionais_por_rodada * (numero - 1), 0)


## Gancho para a duracao variar por rodada no futuro.
func duracao_da_rodada(_numero: int) -> float:
	return duracao_rodada


func exigidos() -> int:
	return Global.pontos_position.size()


func concluidos() -> int:
	var n := 0
	for d in Global.pontos_position:
		if d[I_ESTADO] == COMPLETO:
			n += 1
	return n


func restantes() -> int:
	return exigidos() - concluidos()


func tempo_restante() -> float:
	match estado:
		Estado.RODADA_ATIVA:
			return maxf(inicio_unix + _duracao_atual - _agora(), 0.0)
		Estado.PREPARANDO_RODADA:
			return _duracao_atual
	return 0.0


func nome_estado(valor: int) -> String:
	return String(Estado.keys()[valor])


## Estado publicado em `salas.estado_rodada`. PREPARANDO_RODADA conta como
## "ativa": a Central usa inicio_timer para saber se ainda e contagem regressiva.
func estado_backend() -> String:
	match estado:
		Estado.RODADA_CONCLUIDA:
			return "concluida"
		Estado.RODADA_PERDIDA:
			return "perdida"
		Estado.AGUARDANDO_MUNDO:
			return "aguardando"
		_:
			return "ativa"


func tecla_interacao() -> String:
	for ev in InputMap.action_get_events(acao_interagir):
		if ev is InputEventKey:
			var k: int = ev.physical_keycode if ev.physical_keycode != KEY_NONE else ev.keycode
			return OS.get_keycode_string(k)
	return "?"


## Usados pelo mundo_manager no PATCH inicial, para backend e jogo terem o mesmo relogio.
func inicio_timer_iso() -> String:
	var unix := int(inicio_unix)
	if unix <= 0:
		unix = int(_agora()) + atraso_inicio_rodada
	return _unix_para_iso(unix)


func duracao_timer_backend() -> int:
	return int(round(_duracao_atual if _duracao_atual > 0.0 else duracao_rodada))


## Conclui o objetivo de indice dado. Retorna true so na primeira conclusao valida.
func concluir_objetivo(indice: int) -> bool:
	if estado != Estado.RODADA_ATIVA:
		return false
	if indice < 0 or indice >= Global.pontos_position.size():
		return false
	if _agora() >= inicio_unix + _duracao_atual:
		_perder_rodada()
		return false

	var dados: Array = Global.pontos_position[indice]
	if dados[I_ESTADO] == COMPLETO:
		return false
	dados[I_ESTADO] = COMPLETO   # a lista interna e a mesma de Global.pontos_position

	if indice < _nos.size() and is_instance_valid(_nos[indice]) and _nos[indice].has_method("marcar_completo"):
		_nos[indice].call("marcar_completo")

	# Toca o som de objetivo concluido.
	if _som_player != null and _som_concluido is AudioStream:
		_som_player.stream = _som_concluido
		_som_player.play()

	objetivo_concluido.emit(indice, String(dados[I_TIPO]))
	progresso_mudou.emit(concluidos(), exigidos())
	_enviar_backend()

	if restantes() <= 0:
		_concluir_rodada()
	return true


## Troca os objetivos e inicia a contagem de uma rodada (mundo nao e recriado).
func preparar_rodada(numero: int) -> bool:
	if not _dados_prontos or not _mundo_pronto:
		push_warning("Objetivos: o mundo ainda nao esta pronto.")
		return false
	_limpar_instancias()
	if not _planejar_rodada(maxi(numero, 1)):
		_falhar("Nao foi possivel posicionar objetivos na rodada %d." % numero)
		_mudar_estado(Estado.AGUARDANDO_MUNDO)
		return false
	_instanciar_objetivos()
	_iniciar_contagem(true)
	return true


## Ganchos para a futura tela de derrota.
func reiniciar_rodada_atual() -> bool:
	return preparar_rodada(maxi(rodada_atual, 1))


func reiniciar_do_comeco() -> bool:
	return preparar_rodada(1)


# -----------------------------------------------------------------------------
#  SINAIS DO MUNDO
# -----------------------------------------------------------------------------
func _ao_dados_prontos() -> void:
	_resetar_estado()
	if not _calcular_candidatos():
		_falhar("Nenhuma calcada valida foi encontrada no mapa.")
		return
	_dados_prontos = true
	if not _planejar_rodada(1):
		_falhar("Nao foi possivel posicionar objetivos na rodada 1.")


func _ao_mundo_pronto() -> void:
	if not _dados_prontos or Global.pontos_position.is_empty():
		return
	_mundo_pronto = true
	_instanciar_objetivos()

	# Localiza o abrigo gerado nas construcoes.
	var predios = _mundo.find_child("Predios", true, false)
	if predios != null:
		_abrigo_porta = predios.abrigo_porta_pos
		_abrigo_centro = predios.abrigo_posicao
		_abrigo_carregado = _abrigo_porta != Vector3.ZERO

	# Cria a tela de contagem antes de iniciar (para cobrir a transicao).
	_criar_contagem()

	# A partir daqui a Cidade e a unica responsavel por publicar a rodada.
	_iniciar_contagem(true)
	await get_tree().create_timer(1).timeout
	_criar_hud()


func _resetar_estado() -> void:
	_limpar_instancias()
	Global.pontos_position = []
	rodada_atual = 0
	inicio_unix = 0.0
	_duracao_atual = 0.0
	_dados_prontos = false
	_mundo_pronto = false
	_alvo_atual = -1
	_mudar_estado(Estado.AGUARDANDO_MUNDO)


func _falhar(motivo: String) -> void:
	push_error("Objetivos: " + motivo)
	geracao_falhou.emit(motivo)


# -----------------------------------------------------------------------------
#  LOOP: CRONOMETRO, INICIO, PAUSA E ALVO PROXIMO
# -----------------------------------------------------------------------------
func _process(_delta: float) -> void:
	var agora := _agora()

	# A vida chega a zero pelos minigames (Global.vidas). A derrota por tempo
	# continua sendo detectada dentro de RODADA_ATIVA, mais abaixo.
	if _deve_perder_por_vidas():
		_perder_rodada("vidas")
		return

	if _chuva_ativa:
		_atualizar_aviso_chuva()

	match estado:
		Estado.PREPARANDO_RODADA:
			var falta := inicio_unix - agora
			if falta <= 0.0:
				_mudar_estado(Estado.RODADA_ATIVA)
				tempo_de_jogo_iniciado.emit()
				if is_instance_valid(_contagem):
					_contagem.tocar_inicio()
					_contagem.visible = false
			else:
				var seg := ceili(falta)
				if seg != _ultimo_segundo:
					_ultimo_segundo = seg
					contagem_inicio_atualizada.emit(seg)
				# Puxa o tempo da variavel global para a tela de contagem.
				Global.tempo = seg
				if is_instance_valid(_contagem):
					_contagem.visible = true
		Estado.RODADA_ATIVA:
			var restante := inicio_unix + _duracao_atual - agora
			if restante <= 0.0:
				_perder_rodada()
				return
			
			_processar_eventos(agora)
			
			var seg := ceili(restante)
			if seg != _ultimo_segundo:
				_ultimo_segundo = seg
				tempo_atualizado.emit(seg)
			_atualizar_alvo()
			Global.tempo = seg
			if is_instance_valid(_contagem):
				_contagem.visible = false
		Estado.RODADA_CONCLUIDA:
			if agora >= _fim_pausa_unix:
				preparar_rodada(rodada_atual + 1)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var tecla := event as InputEventKey

		if depuracao_atalhos and tecla.pressed \
		and not tecla.echo and tecla.keycode == KEY_F9:
			for i in Global.pontos_position.size():
				concluir_objetivo(i)
			return

	if not event.is_action_pressed(acao_interagir):
		return

	# Enquanto um minigame estiver aberto, E nao interage com o mundo.
	if is_instance_valid(_minigame_aberto):
		return

	if estado != Estado.RODADA_ATIVA:
		return

	var jogador := _obter_jogador()
	if jogador == null:
		return

	# Abrigo: E entra e E sai (o jogador fica invisivel e parado enquanto esta dentro).
	if _dentro_abrigo:
		_sair_do_abrigo()
		get_viewport().set_input_as_handled()
		return

	if _abrigo_carregado and _jogador_perto_abrigo():
		if imprimir_relatorio:
			print("Objetivos: jogador entrou no abrigo.")
		_entrar_no_abrigo()
		get_viewport().set_input_as_handled()
		return

	var indice := _indice_alvo()
	if indice < 0:
		return

	# Minigames: ao interagir, abre a cena correspondente (o objetivo so
	# conclui quando o jogador acerta).
	var tipo := String(Global.pontos_position[indice][I_TIPO])
	var caminho_minigame := ""
	match tipo:
		"antena":
			caminho_minigame = caminho_minigame_antena
		"bueiro":
			caminho_minigame = caminho_minigame_bueiro
		"pluviometro":
			caminho_minigame = caminho_minigame_pluviometro

	if not caminho_minigame.is_empty() and _abrir_minigame(caminho_minigame, indice):
		get_viewport().set_input_as_handled()
		return

	if concluir_objetivo(indice):
		if imprimir_relatorio:
			print("Objetivos: objetivo %d concluido com sucesso." % indice)
		get_viewport().set_input_as_handled()


func _abrir_minigame(caminho: String, indice: int) -> bool:
	var cena = load(caminho)
	if cena == null or not (cena is PackedScene):
		return false

	_indice_minigame_atual = indice

	var jogador_node = _obter_jogador()
	if jogador_node != null and jogador_node.has_method("set_physics_process"):
		jogador_node.set_physics_process(false)

	var hud = get_node_or_null("HudObjetivos")
	if hud != null:
		hud.visible = false

	var instancia = (cena as PackedScene).instantiate()
	_minigame_aberto = instancia
	add_child(instancia)
	return true


func _mudar_estado(novo: Estado) -> void:
	var anterior := estado
	estado = novo
	_ultimo_segundo = -1
	if anterior == Estado.RODADA_ATIVA and novo != Estado.RODADA_ATIVA:
		_alvo_atual = -1
		_alvo_tipo_atual = ""
		alvo_proximo_mudou.emit("")
	if novo != anterior:
		estado_mudou.emit(novo, anterior)

func _iniciar_contagem(enviar_backend: bool) -> void:
	_eventos_executados.clear()
	motivo_derrota = ""
	_duracao_atual = duracao_da_rodada(rodada_atual)
	if _mundo != null and _mundo.has_method("gerar_eventos"):
		_mundo.call("gerar_eventos", rodada_atual)
	else:
		push_error("Objetivos: não foi possível gerar os eventos da rodada %d." % rodada_atual)
	inicio_unix = float(int(_agora())) + float(atraso_inicio_rodada)
	_mudar_estado(Estado.PREPARANDO_RODADA)
	rodada_preparada.emit(rodada_atual, exigidos())
	progresso_mudou.emit(concluidos(), exigidos())
	if imprimir_relatorio:
		print("Objetivos: rodada %d preparada com %d objetivos (candidatos: %d). Cronometro comeca em %d s." % [
			rodada_atual, exigidos(), _cand_idx.size(), atraso_inicio_rodada])
	if enviar_backend:
		if imprimir_relatorio:
			print("Objetivos: publicando rodada %d no backend (estado=%s)." % [
				rodada_atual, estado_backend()])
		_enviar_backend()


func _concluir_rodada() -> void:
	_fim_pausa_unix = _agora() + pausa_apos_conclusao
	_mudar_estado(Estado.RODADA_CONCLUIDA)
	rodada_concluida.emit(rodada_atual)
	_enviar_backend()
	if imprimir_relatorio:
		print("Objetivos: rodada %d concluida e estado publicado." % rodada_atual)


func _deve_perder_por_vidas() -> bool:
	if _derrota_iniciada or Global.vidas > 0:
		return false
	return estado == Estado.PREPARANDO_RODADA or estado == Estado.RODADA_ATIVA


func _perder_rodada(motivo: String = "tempo") -> void:
	if _derrota_iniciada:
		return
	if estado != Estado.RODADA_ATIVA and estado != Estado.PREPARANDO_RODADA:
		return

	_derrota_iniciada = true
	motivo_derrota = motivo
	_mudar_estado(Estado.RODADA_PERDIDA)   # nao avanca sozinho
	rodada_perdida.emit(rodada_atual, restantes())

	var publicando := _pode_publicar_rodada()
	_enviar_backend()
	if imprimir_relatorio:
		print("Objetivos: rodada %d perdida (%s, faltaram %d); estado publicado." % [
			rodada_atual, motivo, restantes()])

	# Mantem o banner do HUD por alguns segundos antes de abrir a derrota.
	await get_tree().create_timer(3.0).timeout
	if not is_inside_tree():
		return

	# Se o PATCH da derrota ainda nao voltou, espera mais um pouco: a Central
	# so abre a tela de derrota depois de ler `partida_perdida` no banco.
	if publicando and not _perdida_publicada:
		await _aguardar_publicacao_perdida(3.0)
	if not is_inside_tree():
		return

	Transicao.mudar_cena("res://scenes/derrota.tscn", 0.8)


func _atualizar_alvo() -> void:
	var tipo := ""
	if _dentro_abrigo:
		tipo = "abrigo_sair"
	elif _abrigo_carregado and _jogador_perto_abrigo():
		tipo = "abrigo"
	else:
		var i := _indice_alvo()
		if i >= 0:
			tipo = String(Global.pontos_position[i][I_TIPO])

	if tipo == _alvo_tipo_atual:
		return
	_alvo_tipo_atual = tipo
	alvo_proximo_mudou.emit(tipo)


func _obter_jogador() -> Node3D:
	if is_instance_valid(_jogador) and _jogador.is_inside_tree():
		return _jogador

	# Primeiro, tenta encontrar diretamente no mundo.
	_jogador = _mundo.get_node_or_null(
		NodePath(nome_no_jogador)
	) as Node3D

	# Depois, procura recursivamente na hierarquia do mundo.
	if _jogador == null:
		_jogador = _mundo.find_child(
			nome_no_jogador,
			true,
			false
		) as Node3D

	# Por último, tenta pelo grupo.
	if _jogador == null:
		_jogador = get_tree().get_first_node_in_group(
			"player"
		) as Node3D

	if _jogador == null:
		push_warning("Objetivos: jogador nao encontrado!")

	return _jogador


## Esconde o jogador e trava o movimento (ele ficou "dentro" do abrigo).
func _entrar_no_abrigo() -> void:
	if _dentro_abrigo:
		return
	_dentro_abrigo = true
	var jogador := _obter_jogador()
	if jogador != null:
		jogador.call("entrar_no_abrigo")


## Volta a mostrar o jogador e libera o movimento.
func _sair_do_abrigo() -> void:
	if not _dentro_abrigo:
		return
	_dentro_abrigo = false
	var jogador := _obter_jogador()
	if jogador != null:
		jogador.call("sair_do_abrigo")


func _jogador_perto_abrigo() -> bool:
	if not _abrigo_carregado:
		return false
	var jogador := _obter_jogador()
	if jogador == null:
		return false
	var p := jogador.global_position
	if absf(p.y - _abrigo_porta.y) > tolerancia_vertical:
		return false
	var dx := p.x - _abrigo_porta.x
	var dz := p.z - _abrigo_porta.z
	return (dx * dx + dz * dz) <= raio_interacao * raio_interacao


# Objetivo incompleto mais proximo dentro do alcance, ou -1.
func _indice_alvo() -> int:
	var jogador := _obter_jogador()
	if jogador == null:
		return -1
	var p := jogador.global_position
	var melhor := -1
	var melhor_d2 := raio_interacao * raio_interacao
	for i in Global.pontos_position.size():
		var d: Array = Global.pontos_position[i]
		if d[I_ESTADO] == COMPLETO:
			continue
		if absf(p.y - float(d[I_Y])) > tolerancia_vertical:
			continue
		var dx := p.x - float(d[I_X])
		var dz := p.z - float(d[I_Z])
		var d2 := dx * dx + dz * dz
		if d2 <= melhor_d2:
			melhor_d2 = d2
			melhor = i
	return melhor


# -----------------------------------------------------------------------------
#  PLANEJAMENTO DA RODADA (so dados: preenche Global.pontos_position)
# -----------------------------------------------------------------------------
func _planejar_rodada(numero: int) -> bool:
	rodada_atual = numero
	Global.pontos_position = []
	if usar_semente_do_mundo:
		_rng.seed = Global.seed + 424243 + numero * 7919
	else:
		_rng.randomize()

	var pedidos := objetivos_da_rodada(numero)
	var escolhidos := _selecionar_posicoes(pedidos)
	if escolhidos.size() < pedidos:
		push_warning("Objetivos: rodada %d pediu %d, mas so ha espaco valido para %d." % [
			numero, pedidos, escolhidos.size()])

	var lista: Array = []
	for c in escolhidos:
		var pos := _celula_para_mundo(_cand_idx[c])
		lista.append([pos.x, pos.y, pos.z, INCOMPLETO, _sortear_tipo()])
	Global.pontos_position = lista
	return not lista.is_empty()


# Celula do mapa -> posicao GLOBAL na superficie do bloco (centro do bloco, topo = altura * tamanho).
@warning_ignore("integer_division")
func _celula_para_mundo(idx: int) -> Vector3:
	var x = idx / Global.profundidade
	var z = idx % Global.profundidade
	var s = Global.tamanho_cubo
	var local := Vector3((x + 0.5) * s, Global.altura_em(x, z) * s, (z + 0.5) * s)
	return _terreno.to_global(local)


func _sortear_tipo() -> String:
	var total := 0.0
	for k in pesos_tipos:
		total += maxf(float(pesos_tipos[k]), 0.0)
	if total <= 0.0:
		push_error("Objetivos: pesos_tipos vazio ou zerado; usando 'radar'.")
		return "radar"
	var alvo := _rng.randf() * total
	var acumulado := 0.0
	var ultimo := "radar"
	for k in pesos_tipos:
		var peso := maxf(float(pesos_tipos[k]), 0.0)
		if peso <= 0.0:
			continue
		ultimo = String(k)
		acumulado += peso
		if alvo < acumulado:
			return ultimo
	return ultimo


# "Best candidate" (Mitchell): para cada objetivo sorteia alguns candidatos e fica com o mais
# distante dos ja escolhidos, respeitando a distancia minima. Se nao couber, a distancia minima
# cai ate o piso; se ainda nao couber, para (nunca coloca em lugar proibido para completar).
func _selecionar_posicoes(quantidade: int) -> Array[int]:
	var escolhidos: Array[int] = []
	var total := _cand_xz.size()
	if total == 0 or quantidade <= 0:
		return escolhidos

	var piso := maxf(minf(distancia_min_piso, distancia_min_entre_objetivos), 1.0)
	var dmin := maxf(distancia_min_entre_objetivos, piso)

	while escolhidos.size() < quantidade:
		var melhor := -1
		var melhor_d := -1.0
		for t in tentativas_por_ponto:
			var c := _rng.randi_range(0, total - 1)
			var d := _dist_min(c, escolhidos)
			if d >= dmin and d > melhor_d:
				melhor = c
				melhor_d = d
		if melhor < 0:
			# amostragem falhou: varredura completa (rara, so perto da saturacao)
			for c in total:
				var d := _dist_min(c, escolhidos)
				if d >= dmin and d > melhor_d:
					melhor = c
					melhor_d = d
		if melhor >= 0:
			escolhidos.append(melhor)
			continue
		if dmin <= piso:
			break
		dmin = maxf(dmin * 0.75, piso)
	return escolhidos


func _dist_min(c: int, escolhidos: Array[int]) -> float:
	var p := _cand_xz[c]
	var menor := INF
	for e in escolhidos:
		var d := p.distance_to(_cand_xz[e])
		if d < menor:
			menor = d
	return menor


# -----------------------------------------------------------------------------
#  CANDIDATOS (usa so Global.tipos / Global.mapa: sem fisica, funciona longe da camera)
# -----------------------------------------------------------------------------
func _calcular_candidatos() -> bool:
	var tamanho = Global.largura * Global.profundidade
	if Global.tipos.size() != tamanho or Global.mapa.size() != tamanho:
		push_error("Objetivos: Global.tipos/Global.mapa nao estao prontos.")
		return false

	var alcancaveis := PackedByteArray()
	if exigir_acessibilidade:
		alcancaveis = _calcular_alcancaveis()

	var n := _coletar(alcancaveis, margem_quadra_celulas)
	if n < candidatos_minimos and margem_quadra_celulas > 0:
		n = _coletar(alcancaveis, 0)
	if n == 0 and not alcancaveis.is_empty():
		push_warning("Objetivos: nenhuma calcada acessivel; ignorando a acessibilidade.")
		n = _coletar(PackedByteArray(), margem_quadra_celulas)
		if n == 0 and margem_quadra_celulas > 0:
			n = _coletar(PackedByteArray(), 0)

	if imprimir_relatorio:
		print("Objetivos: %d celulas de calcada candidatas." % n)
	return n > 0


func _coletar(alcancaveis: PackedByteArray, raio_quadra: int) -> int:
	_cand_idx = PackedInt32Array()
	_cand_xz = PackedVector2Array()
	var larg = Global.largura
	var prof = Global.profundidade
	var s = Global.tamanho_cubo
	var tipos = Global.tipos
	var filtrar := not alcancaveis.is_empty()
	for x in larg:
		for z in prof:
			var i = x * prof + z
			if tipos[i] != T_CALCADA:
				continue
			if filtrar and alcancaveis[i] == 0:
				continue
			if raio_quadra > 0 and _tem_tipo_perto(tipos, x, z, T_QUADRA, raio_quadra):
				continue
			_cand_idx.append(i)
			_cand_xz.append(Vector2((x + 0.5) * s, (z + 0.5) * s))
	return _cand_idx.size()


func _tem_tipo_perto(tipos: PackedByteArray, x: int, z: int, tipo: int, raio: int) -> bool:
	var larg = Global.largura
	var prof = Global.profundidade
	for dx in range(-raio, raio + 1):
		var nx := x + dx
		if nx < 0 or nx >= larg:
			continue
		for dz in range(-raio, raio + 1):
			var nz := z + dz
			if nz < 0 or nz >= prof:
				continue
			if tipos[nx * prof + nz] == tipo:
				return true
	return false


# Flood fill (4 vizinhos) a partir do ponto de nascimento, andando so em rua/ponte/calcada
# e sem degraus maiores que degrau_max_acessivel. Retorna vazio se nao der para calcular.
@warning_ignore("integer_division")
func _calcular_alcancaveis() -> PackedByteArray:
	if not _mundo.has_method("ponto_de_nascimento"):
		push_warning("Objetivos: o mundo nao tem ponto_de_nascimento(); sem filtro de acessibilidade.")
		return PackedByteArray()

	var larg = Global.largura
	var prof = Global.profundidade
	var s = Global.tamanho_cubo
	var tipos = Global.tipos
	var alturas = Global.mapa

	var spawn: Vector3 = _mundo.call("ponto_de_nascimento")
	var local := _terreno.to_local(spawn)
	var sx := clampi(floori(local.x / s), 0, larg - 1)
	var sz := clampi(floori(local.z / s), 0, prof - 1)

	var visitado := PackedByteArray()
	visitado.resize(larg * prof)
	var fila := PackedInt32Array()
	fila.append(sx * prof + sz)
	visitado[sx * prof + sz] = 1

	var cabeca := 0
	while cabeca < fila.size():
		var i := fila[cabeca]
		cabeca += 1
		var x = i / prof
		var z = i % prof
		var h = alturas[i]
		for d in DIRS4:
			var dv: Vector2i = d
			var nx = x + dv.x
			var nz = z + dv.y
			if nx < 0 or nz < 0 or nx >= larg or nz >= prof:
				continue
			var j = nx * prof + nz
			if visitado[j] != 0:
				continue
			var t = tipos[j]
			if t != T_RUA and t != T_PONTE and t != T_CALCADA:
				continue
			if absi(alturas[j] - h) > degrau_max_acessivel:
				continue
			visitado[j] = 1
			fila.append(j)
	return visitado


# -----------------------------------------------------------------------------
#  INSTANCIAS 3D
# -----------------------------------------------------------------------------
func _instanciar_objetivos() -> void:
	_limpar_instancias()
	for i in Global.pontos_position.size():
		_nos.append(_criar_no(i))


func _criar_no(indice: int) -> Node3D:
	var dados: Array = Global.pontos_position[indice]
	var tipo := String(dados[I_TIPO])

	var textura: Texture2D = null
	var valor: Variant = texturas_tipos.get(tipo)
	if valor is Texture2D:
		textura = valor
	else:
		_avisar_tipo(tipo)

	var frames: SpriteFrames = null
	var valor_frames: Variant = frames_tipos.get(tipo)
	if valor_frames is SpriteFrames:
		frames = valor_frames

	var tamanho := tamanho_sprite
	if tamanhos_tipos.has(tipo):
		tamanho = float(tamanhos_tipos[tipo])

	# Tamanho do sprite gerado no chao: usa chave separada para nao afetar o ponto flutuante.
	var tamanho_obj := tamanho_sprite
	if tamanhos_tipos.has(tipo + "_obj"):
		tamanho_obj = float(tamanhos_tipos[tipo + "_obj"])

	var no := ObjetivoSprite.new()
	no.name = "Objetivo_%d_%s" % [indice, tipo]
	_container.add_child(no)
	no.global_position = Vector3(float(dados[I_X]), float(dados[I_Y]), float(dados[I_Z]))
	no.configurar(tipo, textura, frames, tamanho, tamanho_obj, altura_sprite, ocultar_ao_completar)
	if dados[I_ESTADO] == COMPLETO:
		no.marcar_completo()
	no.tree_exiting.connect(_ao_no_saindo.bind(indice, rodada_atual))
	return no


func _avisar_tipo(tipo: String) -> void:
	pass
	#if _tipos_sem_textura_avisados.has(tipo):
	#	return
	#_tipos_sem_textura_avisados[tipo] = true
	#print("Objetivos [%s]: sem textura em texturas_tipos; usando ponto simples." % tipo)


func _limpar_instancias() -> void:
	_limpando = true
	for no in _nos:
		if is_instance_valid(no):
			var pai := no.get_parent()
			if pai != null:
				pai.remove_child(no)   # emite tree_exiting agora, com _limpando = true
			no.queue_free()
	_nos.clear()
	_limpando = false


# Instancia removida fora do fluxo normal: recria no mesmo lugar se o objetivo ainda vale.
func _ao_no_saindo(indice: int, numero_rodada: int) -> void:
	if _limpando:
		return
	_verificar_no_removido.call_deferred(indice, numero_rodada)


func _verificar_no_removido(indice: int, numero_rodada: int) -> void:
	if numero_rodada != rodada_atual or _limpando or not is_inside_tree():
		return
	if estado != Estado.PREPARANDO_RODADA and estado != Estado.RODADA_ATIVA:
		return
	if indice >= _nos.size() or indice >= Global.pontos_position.size():
		return
	var atual: Variant = _nos[indice]
	if is_instance_valid(atual) and (atual as Node3D).is_inside_tree():
		return   # foi so reparentado
	if Global.pontos_position[indice][I_ESTADO] == COMPLETO:
		return
	push_warning("Objetivos: a instancia do objetivo %d foi removida; recriando." % indice)
	_nos[indice] = _criar_no(indice)


# -----------------------------------------------------------------------------
#  BACKEND (Supabase)
# -----------------------------------------------------------------------------
# Todas as alteracoes da rodada saem por este unico HTTPRequest, em um unico
# PATCH da mesma linha. Assim a Central nunca recebe objetivos de uma rodada
# junto com o identificador/timer de outra.
func _carregar_credenciais() -> void:
	var consts: Dictionary = _mundo.get_script().get_script_constant_map()
	_projeto_ref = String(consts.get("PROJECT_REF", ""))
	_chave = String(consts.get("SUPABASE_KEY", ""))
	if _projeto_ref.is_empty() or _chave.is_empty():
		push_warning("Objetivos: PROJECT_REF/SUPABASE_KEY nao encontrados no mundo_manager; sem sincronizar.")


func _pode_publicar_rodada() -> bool:
	return sincronizar_backend \
		and not _projeto_ref.is_empty() \
		and not Global.salaID.is_empty() \
		and rodada_atual > 0 \
		and inicio_unix > 0.0


func _enviar_backend() -> void:
	if not _pode_publicar_rodada():
		return
	_reenviar = true
	if not _enviando:
		_processar_envios()


func _aguardar_publicacao_perdida(limite: float) -> void:
	var fim := _agora() + limite
	while is_inside_tree() and not _perdida_publicada and _agora() < fim:
		await get_tree().create_timer(0.1).timeout


func _montar_corpo_backend() -> Dictionary:
	var corpo: Dictionary = {
		"rodada_atual": rodada_atual,
		"estado_rodada": estado_backend(),
		"partida_perdida": estado == Estado.RODADA_PERDIDA,
		"inicio_timer": _unix_para_iso(int(inicio_unix)),
		"duracao_timer": int(round(_duracao_atual if _duracao_atual > 0.0 else duracao_rodada)),
		"pontos_position": Global.pontos_position.duplicate(true),
		"eventos": Global.eventos.duplicate(true),
	}
	# Posicao do abrigo gerado (se houver).
	var predios_node = _mundo.find_child("Predios", true, false)
	if predios_node != null and predios_node.abrigo_posicao != Vector3.ZERO:
		var ap: Vector3 = predios_node.abrigo_posicao
		corpo["abrigo_position"] = [ap.x, ap.y, ap.z]
	return corpo


func _processar_envios() -> void:
	if _enviando:
		return
	_enviando = true
	var tentativas := 0

	while _reenviar and is_inside_tree():
		_reenviar = false
		var corpo := _montar_corpo_backend()
		var url = "https://%s.supabase.co/rest/v1/salas" % _projeto_ref \
			+ "?id=eq." + Global.salaID.uri_encode() + "&select=id"
		var headers := PackedStringArray([
			"Content-Type: application/json",
			"apikey: " + _chave,
			"Authorization: Bearer " + _chave,
			"Prefer: return=representation",
		])

		var erro := _http.request(url, headers, HTTPClient.METHOD_PATCH, JSON.stringify(corpo))
		if erro != OK:
			push_error("Objetivos: nao foi possivel enviar a rodada %d (erro %d)." % [rodada_atual, erro])
			tentativas = _falha_envio(tentativas)
			if tentativas < 0:
				break
			await get_tree().create_timer(INTERVALO_RETENTATIVA).timeout
			continue

		var resposta = await _http.request_completed
		var resultado: int = resposta[0]
		var codigo: int = resposta[1]
		var texto: String = resposta[3].get_string_from_utf8()

		if resultado != HTTPRequest.RESULT_SUCCESS:
			push_error("Objetivos: falha de conexao ao publicar a rodada %d (resultado %d)." % [
				rodada_atual, resultado])
			tentativas = _falha_envio(tentativas)
			if tentativas < 0:
				break
			await get_tree().create_timer(INTERVALO_RETENTATIVA).timeout
			continue

		if codigo < 200 or codigo >= 300:
			push_error("Objetivos: erro HTTP %d ao publicar a rodada %d: %s" % [
				codigo, rodada_atual, texto])
			tentativas = _falha_envio(tentativas)
			if tentativas < 0:
				break
			await get_tree().create_timer(INTERVALO_RETENTATIVA).timeout
			continue

		var dados = JSON.parse_string(texto)
		if dados is Array and dados.is_empty():
			push_error("Objetivos: nenhuma sala atualizada (ID da sala ou RLS?).")
			tentativas = _falha_envio(tentativas)
			if tentativas < 0:
				break
			await get_tree().create_timer(INTERVALO_RETENTATIVA).timeout
			continue

		tentativas = 0
		if bool(corpo.get("partida_perdida", false)):
			_perdida_publicada = true
			print("Objetivos: derrota da rodada %d publicada no backend." % rodada_atual)
		if _ultima_rodada_publicada != rodada_atual:
			_ultima_rodada_publicada = rodada_atual
			print("Objetivos: rodada %d publicada no backend (estado=%s, inicio_timer=%d, duracao=%d)." % [
				rodada_atual, estado_backend(), int(inicio_unix),
				int(round(_duracao_atual))])

	_enviando = false


## Incrementa a tentativa e devolve -1 quando o limite foi atingido
## (nesse caso agenda uma nova tentativa mais tarde).
func _falha_envio(tentativas: int) -> int:
	var total := tentativas + 1
	_reenviar = true
	if total < MAX_TENTATIVAS_ENVIO:
		return total
	push_warning("Objetivos: envio falhou %d vezes; nova tentativa em %d s." % [
		total, int(INTERVALO_RETENTATIVA)])
	_agendar_reenvio()
	return -1


func _agendar_reenvio() -> void:
	if _retry_agendado or not is_inside_tree():
		return
	_retry_agendado = true
	await get_tree().create_timer(INTERVALO_RETENTATIVA).timeout
	_retry_agendado = false
	if is_inside_tree() and _reenviar and not _enviando:
		_processar_envios()


# -----------------------------------------------------------------------------
#  UTILITARIOS
# -----------------------------------------------------------------------------
func _agora() -> float:
	return Time.get_unix_time_from_system()


static func _unix_para_iso(unix: int) -> String:
	return Time.get_datetime_string_from_unix_time(unix, true) + "+00:00"


func _garantir_acao_interagir() -> void:
	if InputMap.has_action(acao_interagir):
		return
	InputMap.add_action(acao_interagir)
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_E
	InputMap.action_add_event(acao_interagir, ev)

func _processar_eventos(agora: float) -> void:
	for i in range(Global.eventos.size()):
		if _eventos_executados.has(i):
			continue

		var evento: Array = Global.eventos[i]

		if evento.size() < 2:
			continue

		var tipo: String = str(evento[0])
		var segundo_evento: float = float(evento[1])

		# Somente a chuva de granizo recebe 30 segundos extras.
		if tipo == "chuvaGranizo":
			segundo_evento += 30.0

		# Calcula o instante de execução a partir do início real da rodada.
		var instante_evento: float = inicio_unix + segundo_evento

		if agora < instante_evento:
			continue

		# Marca para impedir execução repetida.
		_eventos_executados.append(i)

		# Não executa eventos que ultrapassem o fim da rodada.
		if segundo_evento >= _duracao_atual:
			continue

		match tipo:
			"blackout":
				blackout()

			"chuvaGranizo":
				chuva_granizo()

			_:
				print("Tipo de evento desconhecido: ", tipo)


func blackout() -> void:
	print("BLACKOUT INICIADO!")


func chuva_granizo() -> void:
	if imprimir_relatorio:
		print("CHUVA DE GRANIZO INICIADA!")
	if _chuva_ativa:
		return
	_chuva_ativa = true
	_criar_efeito_chuva()
	_atualizar_aviso_chuva()
	_iniciar_loop_chuva()


# Enquanto a chuva dura, a cada `intervalo_dano_chuva` segundos o jogador
# perde uma vida se nao estiver dentro do abrigo.
func _iniciar_loop_chuva() -> void:
	var restante := duracao_chuva
	while is_inside_tree() and _chuva_ativa and restante > 0.0:
		await get_tree().create_timer(intervalo_dano_chuva).timeout
		if not is_inside_tree() or not _chuva_ativa:
			return
		if estado != Estado.RODADA_ATIVA:
			break
		restante -= intervalo_dano_chuva
		if not _dentro_abrigo:
			_perder_vida_na_chuva()
	_encerrar_chuva()


func _perder_vida_na_chuva() -> void:
	Global.vidas = maxi(Global.vidas - 1, 0)
	if imprimir_relatorio:
		print("Chuva: jogador perdeu uma vida (restam %d)." % Global.vidas)

	# Mantem o banco e a Central em sincronia, como nos minigames.
	if Banco != null and Banco.has_method("atualizar_vida"):
		await Banco.atualizar_vida(Global.vidas)
	if ConectSupa != null and ConectSupa.has_method("enviar_variavel"):
		ConectSupa.enviar_variavel({
			"tipo": "vida",
			"vidas": Global.vidas
		})


func _encerrar_chuva() -> void:
	if not _chuva_ativa:
		return
	_chuva_ativa = false
	if is_instance_valid(_particulas_chuva):
		_particulas_chuva.emitting = false
	_atualizar_aviso_chuva()

	var camada := _efeito_chuva
	_efeito_chuva = null
	_particulas_chuva = null
	if is_instance_valid(camada):
		# Deixa as ultimas pedras cairem antes de remover a camada.
		await get_tree().create_timer(2.6).timeout
		if is_instance_valid(camada):
			camada.queue_free()


func _criar_efeito_chuva() -> void:
	var tela := get_viewport().get_visible_rect().size

	var material := ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	material.emission_box_extents = Vector3(tela.x * 0.5 + 40.0, 8.0, 0.0)
	material.direction = Vector3(0.0, 1.0, 0.0)
	material.spread = 8.0
	material.initial_velocity_min = 320.0
	material.initial_velocity_max = 520.0
	material.gravity = Vector3(0.0, 500.0, 0.0)
	material.angle_min = 0.0
	material.angle_max = 360.0
	material.angular_velocity_min = -220.0
	material.angular_velocity_max = 220.0
	material.scale_min = 2.0
	material.scale_max = 3.0

	# Usa so o cubo maior do Gelos.png (o sprite tem dois cubos lado a lado).
	var textura := AtlasTexture.new()
	textura.atlas = preload("res://assets/Gelos.png")
	textura.region = Rect2(16, 0, 16, 16)

	_efeito_chuva = CanvasLayer.new()
	_efeito_chuva.name = "EfeitoChuvaGranizo"
	_efeito_chuva.layer = 5
	add_child(_efeito_chuva)

	_particulas_chuva = GPUParticles2D.new()
	_particulas_chuva.name = "Granizo"
	_particulas_chuva.texture = textura
	_particulas_chuva.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_particulas_chuva.amount = 160
	_particulas_chuva.lifetime = 2.5
	_particulas_chuva.process_material = material
	_particulas_chuva.position = Vector2(tela.x * 0.5, -8.0)
	_particulas_chuva.emitting = true
	_efeito_chuva.add_child(_particulas_chuva)


# Mostra o aviso do HUD enquanto chove e o jogador esta fora do abrigo.
func _atualizar_aviso_chuva() -> void:
	var mostrar := _chuva_ativa and not _dentro_abrigo
	if mostrar == _aviso_chuva_visivel:
		return
	_aviso_chuva_visivel = mostrar

	var hud = get_node_or_null("HudObjetivos")
	if hud == null:
		return
	if mostrar:
		hud.mostrar_aviso("Chuva de granizo!\nVá para o abrigo!", 0.0, Color(0.45, 0.75, 1.0))
	else:
		hud.esconder_aviso()
