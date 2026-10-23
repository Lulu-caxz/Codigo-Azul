
extends Node

# =============================================================================
#  CENTRAL: SINCRONIZACAO DA SALA/RODADA COM O SUPABASE
# =============================================================================
# A Cidade e a Central rodam em processos diferentes. A unica fonte de verdade
# compartilhada e a linha da sala na tabela `salas`.
#
# A Cidade publica `rodada_atual` junto com estado, timer, pontos, eventos e
# abrigo em um unico PATCH. A Central consulta a linha periodicamente e troca
# de rodada quando `rodada_atual` muda. Uma resposta incompleta de rodada nova
# e descartada para nao misturar dados de rodadas diferentes.
# =============================================================================

signal dados_sala_atualizados(posicao: Vector3, pontos: Array)
signal timer_atualizado(segundos: int, iniciado: bool)
signal rodada_atualizada(numero: int, estado: String)
signal posicao_jogador_atualizada(posicao: Vector3)
signal abrigo_atualizado(posicao: Vector3)
signal evento_ocorreu(tipo: String)

const PROJECT_REF: String = "ovkvgnnsxmpymcjclnzo"
const SUPABASE_KEY: String = "sb_publishable_3FDWeQxz2a8wEO-se44m-w_guLkTpR5"

const INTERVALO_CONSULTA: float = 1.0
const TIMEOUT_HTTP: float = 8.0

const ESTADO_AGUARDANDO := "aguardando"
const ESTADO_ATIVA := "ativa"
const ESTADO_CONCLUIDA := "concluida"
const ESTADO_PERDIDA := "perdida"

const CONTAGEM_CENA: PackedScene = preload("res://scenes/cidade/contagem.tscn")

var http: HTTPRequest

var posicao_jogador: Vector3 = Vector3.ZERO
var inicio_unix: float = 0.0
var duracao_timer: float = 0.0
var rodada_atual: int = 0
var estado_rodada: String = ESTADO_AGUARDANDO
var abrigo_position: Vector3 = Vector3.ZERO
var eventos: Array = []

var _consultando: bool = false
var _avisou_sala_id := false
var _primeira_sincronizacao: bool = true
var _ultimo_segundo: int = -1
var _ultimo_estado_iniciado: bool = false
var _assinatura_pontos: String = ""
var _tem_posicao: bool = false
var _tem_abrigo: bool = false
var _eventos_assinatura: String = ""
var _temporizadores_eventos: Array[Timer] = []

var tela_contagem: CanvasLayer
var texto_titulo: Label
var texto_contagem: Label


func _ready() -> void:
	if http == null:
		http = HTTPRequest.new()
		http.name = "HTTPSincronizacaoCentral"
		http.timeout = TIMEOUT_HTTP
		add_child(http)

	_criar_tela_contagem()
	timer_atualizado.connect(_atualizar_tela_contagem)

	print("Central: iniciando sincronizacao com o Supabase (sala=%s)." % Global.salaID)
	_loop_sincronizacao()


func _process(_delta: float) -> void:
	_atualizar_timer(false)


func _loop_sincronizacao() -> void:
	while is_inside_tree():
		await sincronizar_sala()

		if not is_inside_tree():
			break

		await get_tree().create_timer(INTERVALO_CONSULTA).timeout


func sincronizar_sala() -> void:
	if http == null:
		http = HTTPRequest.new()
		http.name = "HTTPSincronizacaoCentral"
		http.timeout = TIMEOUT_HTTP
		add_child(http)

	if _consultando:
		return

	if Global.salaID.is_empty():
		if not _avisou_sala_id:
			push_warning("Central: Global.salaID ainda nao foi definido; aguardando.")
			_avisou_sala_id = true
		return

	_avisou_sala_id = false
	_consultando = true

	var url: String = "https://%s.supabase.co/rest/v1/salas" % PROJECT_REF
	url += "?id=eq." + Global.salaID.uri_encode()
	url += "&select=rodada_atual,estado_rodada,inicio_timer,duracao_timer"
	url += ",jogador_f_position,pontos_position,abrigo_position,eventos"

	var headers := PackedStringArray([
		"apikey: " + SUPABASE_KEY,
		"Authorization: Bearer " + SUPABASE_KEY,
		"Accept: application/json"
	])

	var erro := http.request(url, headers, HTTPClient.METHOD_GET)

	if erro != OK:
		_consultando = false
		push_error("Central: nao foi possivel solicitar os dados da sala (erro %d)." % erro)
		return

	var resposta = await http.request_completed
	_consultando = false

	var resultado: int = resposta[0]
	var codigo: int = resposta[1]
	var texto: String = resposta[3].get_string_from_utf8()

	if resultado != HTTPRequest.RESULT_SUCCESS:
		push_error("Central: falha de conexao com o Supabase (resultado %d)." % resultado)
		return

	if codigo < 200 or codigo >= 300:
		push_error("Central: erro HTTP %d ao consultar a sala: %s" % [codigo, texto])
		return

	var dados = JSON.parse_string(texto)

	if dados == null:
		push_warning("Central: resposta do Supabase nao e um JSON valido.")
		return

	if not dados is Array:
		push_warning("Central: resposta inesperada do Supabase: %s" % texto)
		return

	if dados.is_empty():
		push_warning("Central: sala nao encontrada no Supabase (id=%s)." % Global.salaID)
		return

	if not (dados[0] is Dictionary):
		push_warning("Central: linha da sala em formato inesperado: %s" % texto)
		return

	_aplicar_sala(dados[0])


func _aplicar_sala(sala: Dictionary) -> void:
	var rodada_recebida := _ler_int(sala.get("rodada_atual", null), -1)
	if rodada_recebida < 0:
		push_warning("Central: rodada_atual ausente ou invalida; resposta ignorada.")
		return

	var estado_recebido := String(sala.get("estado_rodada", ESTADO_AGUARDANDO))
	estado_recebido = estado_recebido.strip_edges().to_lower()
	if estado_recebido.is_empty():
		estado_recebido = ESTADO_AGUARDANDO
	if estado_recebido != ESTADO_AGUARDANDO \
	and estado_recebido != ESTADO_ATIVA \
	and estado_recebido != ESTADO_CONCLUIDA \
	and estado_recebido != ESTADO_PERDIDA:
		push_warning("Central: estado_rodada desconhecido ('%s'); tratando como ativa." % estado_recebido)
		estado_recebido = ESTADO_ATIVA

	var pontos_recebidos = _ler_array_json(sala.get("pontos_position", null))
	var eventos_recebidos = _ler_array_json(sala.get("eventos", null))
	var inicio_recebido := _converter_timestamp(sala.get("inicio_timer", null))
	var duracao_recebida := _ler_float(sala.get("duracao_timer", null), 0.0)
	var posicao_recebida = _ler_vetor3(sala.get("jogador_f_position", null))
	var abrigo_recebido = _ler_vetor3(sala.get("abrigo_position", null))

	var mudou_rodada := rodada_recebida != rodada_atual
	var mudou_estado := estado_recebido != estado_rodada
	var mudou_timer := false

	if mudou_rodada:
		# Rodada nova so e aceita com a fotografia completa publicada pela Cidade.
		if rodada_recebida >= 1:
			if pontos_recebidos == null:
				push_warning("Central: rodada %d sem pontos_position valido; aguardando a proxima consulta." % rodada_recebida)
				return
			if inicio_recebido <= 0.0:
				push_warning("Central: rodada %d sem inicio_timer valido; aguardando a proxima consulta." % rodada_recebida)
				return
			if duracao_recebida <= 0.0:
				push_warning("Central: rodada %d sem duracao_timer valida; aguardando a proxima consulta." % rodada_recebida)
				return
		elif pontos_recebidos == null:
			pontos_recebidos = []

		rodada_atual = rodada_recebida
		inicio_unix = inicio_recebido
		duracao_timer = duracao_recebida
		estado_rodada = estado_recebido
		eventos = eventos_recebidos if eventos_recebidos != null else []
		if eventos_recebidos == null:
			push_warning("Central: rodada %d sem eventos; seguindo sem eventos." % rodada_recebida)
		_ultimo_segundo = -1
		_ultimo_estado_iniciado = false
		mudou_timer = true

		print("Central: rodada %d detectada (estado=%s, inicio_unix=%d, duracao=%.0f)." % [
			rodada_atual, estado_rodada, int(inicio_unix), duracao_timer])
	else:
		if mudou_estado:
			estado_rodada = estado_recebido
			_ultimo_segundo = -1
			_ultimo_estado_iniciado = false
			mudou_timer = true
			print("Central: rodada %d mudou para o estado '%s'." % [
				rodada_atual, estado_rodada])

		# Mesma rodada pode receber um timer novo (reiniciar_rodada_atual).
		if inicio_recebido > 0.0 and duracao_recebida > 0.0:
			if absf(inicio_recebido - inicio_unix) > 0.5 \
			or absf(duracao_recebida - duracao_timer) > 0.5:
				inicio_unix = inicio_recebido
				duracao_timer = duracao_recebida
				_ultimo_segundo = -1
				mudou_timer = true
				print("Central: timer da rodada %d atualizado (inicio_unix=%d, duracao=%.0f)." % [
					rodada_atual, int(inicio_unix), duracao_timer])

		if eventos_recebidos != null:
			eventos = eventos_recebidos

	var pontos_atuais: Array = Global.pontos_position
	if pontos_recebidos != null:
		pontos_atuais = pontos_recebidos
		Global.pontos_position = pontos_atuais.duplicate(true)

	var assinatura := "%d|%s" % [rodada_recebida, JSON.stringify(pontos_atuais)]
	var mudou_pontos := assinatura != _assinatura_pontos

	if posicao_recebida != null:
		posicao_jogador = posicao_recebida
		_tem_posicao = true

	if _tem_posicao:
		# Emitido a cada consulta para que um mapa que terminou de carregar
		# depois do primeiro sync receba a posicao sem esperar uma mudanca.
		posicao_jogador_atualizada.emit(posicao_jogador)

	if abrigo_recebido != null:
		if not _tem_abrigo or abrigo_recebido.distance_to(abrigo_position) > 0.01:
			abrigo_position = abrigo_recebido
			_tem_abrigo = true
			abrigo_atualizado.emit(abrigo_position)

	if mudou_rodada or mudou_estado:
		rodada_atualizada.emit(rodada_atual, estado_rodada)

	if mudou_rodada or mudou_pontos:
		_assinatura_pontos = assinatura
		dados_sala_atualizados.emit(posicao_jogador, Global.pontos_position.duplicate(true))
		print("Central: %d objetivos sincronizados para a rodada %d." % [
			Global.pontos_position.size(), rodada_atual])

	if mudou_rodada or mudou_estado or mudou_timer:
		_atualizar_timer(true)

	_atualizar_eventos()

	if _primeira_sincronizacao:
		_primeira_sincronizacao = false
		if rodada_atual >= 1:
			print("Central: estado inicial carregado (rodada=%d, estado=%s, restante=%s)." % [
				rodada_atual, estado_rodada, str(_segundos_restantes())])
		else:
			print("Central: sala sincronizada; aguardando a primeira rodada.")


func _atualizar_timer(forcar: bool) -> void:
	var segundos: int
	var iniciado: bool

	if estado_rodada == ESTADO_PERDIDA or estado_rodada == ESTADO_CONCLUIDA:
		segundos = 0
		iniciado = true
	elif inicio_unix <= 0.0:
		return
	else:
		var agora := Time.get_unix_time_from_system()
		iniciado = agora >= inicio_unix
		if not iniciado:
			segundos = ceili(inicio_unix - agora)
		else:
			segundos = maxi(0, ceili(inicio_unix + duracao_timer - agora))

	Global.tempo = segundos

	if not forcar and segundos == _ultimo_segundo and iniciado == _ultimo_estado_iniciado:
		return

	var transicionou := iniciado != _ultimo_estado_iniciado
	_ultimo_segundo = segundos
	_ultimo_estado_iniciado = iniciado
	timer_atualizado.emit(segundos, iniciado)

	if transicionou:
		if iniciado:
			print("Central: rodada %d em andamento. Tempo restante: %d s." % [
				rodada_atual, segundos])
		else:
			print("Central: rodada %d comeca em %d s." % [rodada_atual, segundos])


# -----------------------------------------------------------------------------
#  EVENTOS DA RODADA
# -----------------------------------------------------------------------------
# A Cidade publica `eventos` como [["blackout", 30], ["chuvaGranizo", 60]].
# O instante de cada evento e inicio_timer + segundo. Para `chuvaGranizo`, o
# segundo salvo e o inicio do aviso; a Cidade executa o granizo 30 s depois.
func _atualizar_eventos() -> void:
	var assinatura := "%d|%s|%.3f|%.3f|%s" % [
		rodada_atual, estado_rodada, inicio_unix, duracao_timer,
		JSON.stringify(eventos)
	]
	if assinatura == _eventos_assinatura:
		return

	_eventos_assinatura = assinatura
	_limpar_temporizadores_eventos()

	if estado_rodada != ESTADO_ATIVA or inicio_unix <= 0.0 or duracao_timer <= 0.0:
		return
	if eventos.is_empty():
		return

	var agora := Time.get_unix_time_from_system()
	if agora >= inicio_unix + duracao_timer:
		return

	for evento in eventos:
		if not evento is Array:
			continue
		var dados: Array = evento
		if dados.size() < 2:
			continue

		var tipo := str(dados[0]).strip_edges()
		if tipo.is_empty():
			continue

		var segundo := _ler_float(dados[1], -1.0)
		if segundo < 0.0:
			continue

		if segundo >= duracao_timer:
			continue

		var espera := maxf(inicio_unix + segundo - agora, 0.01)
		var timer := Timer.new()
		timer.one_shot = true
		timer.ignore_time_scale = true
		timer.wait_time = espera
		timer.timeout.connect(_ao_temporizador_evento.bind(tipo, timer))
		add_child(timer)
		timer.start()
		_temporizadores_eventos.append(timer)

		print("Central: evento '%s' agendado para a rodada %d (em %.1f s)." % [
			tipo, rodada_atual, espera])


func _ao_temporizador_evento(tipo: String, timer: Timer) -> void:
	_temporizadores_eventos.erase(timer)
	if is_instance_valid(timer):
		timer.queue_free()

	if estado_rodada != ESTADO_ATIVA:
		return
	if Time.get_unix_time_from_system() >= inicio_unix + duracao_timer:
		return

	print("Central: evento '%s' iniciado na rodada %d." % [tipo, rodada_atual])
	evento_ocorreu.emit(tipo)


func _limpar_temporizadores_eventos() -> void:
	for timer in _temporizadores_eventos:
		if is_instance_valid(timer):
			timer.stop()
			timer.queue_free()
	_temporizadores_eventos.clear()


func _segundos_restantes() -> int:
	if estado_rodada == ESTADO_PERDIDA or estado_rodada == ESTADO_CONCLUIDA:
		return 0
	if inicio_unix <= 0.0:
		return 0
	var agora := Time.get_unix_time_from_system()
	if agora < inicio_unix:
		return ceili(inicio_unix - agora)
	return maxi(0, ceili(inicio_unix + duracao_timer - agora))


# Aceita unix (numero ou texto) e ISO-8601 com Z, +00:00 ou -03:00. O horario
# e convertido para UTC antes de virar unix, para os dois computadores
# concordarem mesmo em fusos horarios diferentes.
func _converter_timestamp(valor: Variant) -> float:
	if valor == null:
		return 0.0

	if valor is int or valor is float:
		var numero := float(valor)
		return numero if numero > 0.0 else 0.0

	var texto := String(valor).strip_edges()
	if texto.is_empty():
		return 0.0

	if texto.is_valid_float():
		var numero := texto.to_float()
		return numero if numero > 0.0 else 0.0

	if texto.length() < 19:
		return 0.0

	var data_hora := texto.substr(0, 19).replace("T", " ").replace("t", " ")
	var base := float(Time.get_unix_time_from_datetime_string(data_hora))
	if base <= 0.0:
		return 0.0

	return base - float(_offset_timezone_segundos(texto))


func _offset_timezone_segundos(texto: String) -> int:
	var resto := texto.substr(19)

	if resto.find("Z") >= 0 or resto.find("z") >= 0:
		return 0

	if resto.to_upper().find("UTC") >= 0:
		return 0

	var pos_mais := resto.rfind("+")
	var pos_menos := resto.rfind("-")
	var pos := maxi(pos_mais, pos_menos)
	if pos < 0:
		return 0

	var sinal := 1 if resto.substr(pos, 1) == "+" else -1
	var horas_min := resto.substr(pos + 1).replace(":", "").replace(" ", "").strip_edges()
	if horas_min.length() < 2:
		return 0

	var horas := horas_min.substr(0, 2).to_int()
	var minutos := 0
	if horas_min.length() >= 4:
		minutos = horas_min.substr(2, 2).to_int()

	return sinal * (horas * 3600 + minutos * 60)


func _ler_int(valor: Variant, padrao: int) -> int:
	if valor is int:
		return int(valor)
	if valor is float:
		return int(valor)
	if valor is String:
		var texto := String(valor).strip_edges()
		if texto.is_valid_int():
			return int(texto)
	return padrao


func _ler_float(valor: Variant, padrao: float) -> float:
	if valor is int or valor is float:
		return float(valor)
	if valor is String:
		var texto := String(valor).strip_edges()
		if texto.is_valid_float():
			return texto.to_float()
	return padrao


func _ler_array_json(valor: Variant) -> Variant:
	if valor == null:
		return null

	var bruto: Variant = valor
	if bruto is String:
		bruto = JSON.parse_string(String(bruto))

	if bruto is Array:
		return (bruto as Array).duplicate(true)

	return null


func _ler_vetor3(valor: Variant) -> Variant:
	if valor == null:
		return null

	var bruto: Variant = valor
	if bruto is String:
		bruto = JSON.parse_string(String(bruto))

	if bruto is Array and (bruto as Array).size() >= 3:
		var arr: Array = bruto
		if arr[0] == null or arr[1] == null or arr[2] == null:
			return null
		return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))

	return null


func _criar_tela_contagem() -> void:
	tela_contagem = CONTAGEM_CENA.instantiate() as CanvasLayer

	if tela_contagem == null:
		push_error("Central: nao foi possivel instanciar a cena de contagem.")
		return

	tela_contagem.name = "Contagem"
	add_child(tela_contagem)

	texto_titulo = tela_contagem.get_node(
		"CenterContainer/VBox/LabelTexto"
	) as Label

	texto_contagem = tela_contagem.get_node(
		"CenterContainer/VBox/LabelNumero"
	) as Label

	# Fica escondida ate a primeira rodada valida; evita exibir um valor antigo
	# de Global.tempo antes de qualquer sincronizacao.
	tela_contagem.visible = false

	print("Central: cena de contagem carregada.")


func _atualizar_tela_contagem(segundos: int, iniciado: bool) -> void:
	if tela_contagem == null:
		return

	if texto_titulo == null or texto_contagem == null:
		return

	if iniciado:
		tela_contagem.visible = false
		return

	tela_contagem.visible = true
	texto_titulo.text = "COMEÇA EM"
	texto_contagem.text = str(segundos)
