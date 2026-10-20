extends Node

signal variavel_recebida(valor: Variant)
signal conectado_ao_canal

const PROJECT_REF := "ovkvgnnsxmpymcjclnzo"
const SUPABASE_KEY := "sb_publishable_3FDWeQxz2a8wEO-se44m-w_guLkTpR5"
const CANAL := "realtime:game-room"

var socket := WebSocketPeer.new()
var entrou_no_canal := false
var enviou_entrada := false

var proxima_ref := 1
var tempo_heartbeat := 0.0


func _ready() -> void:
	var url := "wss://%s.supabase.co/realtime/v1/websocket?apikey=%s&vsn=1.0.0" % [
		PROJECT_REF,
		SUPABASE_KEY.uri_encode()
	]

	var erro := socket.connect_to_url(url)

	if erro != OK:
		push_error("Erro ao iniciar conexão: %s" % erro)


func _process(delta: float) -> void:
	socket.poll()

	if socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		if not enviou_entrada:
			entrar_no_canal()

		if entrou_no_canal:
			tempo_heartbeat += delta

			if tempo_heartbeat >= 25.0:
				enviar_heartbeat()
				tempo_heartbeat = 0.0

		while socket.get_available_packet_count() > 0:
			var mensagem_texto := socket.get_packet().get_string_from_utf8()
			var mensagem = JSON.parse_string(mensagem_texto)

			if mensagem is Dictionary:
				processar_mensagem(mensagem)


func entrar_no_canal() -> void:
	enviou_entrada = true

	var mensagem := {
		"topic": CANAL,
		"event": "phx_join",
		"payload": {
			"config": {
				"broadcast": {
					"ack": false,
					"self": false
				},
				"presence": {
					"enabled": false
				},
				"private": false
			}
		},
		"ref": str(proxima_ref),
		"join_ref": str(proxima_ref)
	}

	proxima_ref += 1
	enviar_json(mensagem)


func processar_mensagem(mensagem: Dictionary) -> void:
	var evento: String = mensagem.get("event", "")

	if evento == "phx_reply":
		var payload: Dictionary = mensagem.get("payload", {})

		if payload.get("status", "") == "ok":
			entrou_no_canal = true
			conectado_ao_canal.emit()
			print("Conectado ao canal do Supabase!")

	elif evento == "broadcast":
		var payload: Dictionary = mensagem.get("payload", {})
		var dados = payload.get("payload", {})

		if dados is Dictionary and dados.has("valor"):
			variavel_recebida.emit(dados["valor"])
			print("Valor recebido: ", dados["valor"])

	elif evento == "phx_error" or evento == "phx_close":
		entrou_no_canal = false
		enviou_entrada = false
		push_warning("O canal foi fechado ou apresentou um erro.")


func enviar_variavel(valor: Variant) -> void:
	if not entrou_no_canal:
		push_warning("Ainda não conectado ao canal.")
		return

	var mensagem := {
		"topic": CANAL,
		"event": "broadcast",
		"payload": {
			"type": "broadcast",
			"event": "atualizar_variavel",
			"payload": {
				"valor": valor
			}
		},
		"ref": str(proxima_ref),
		"join_ref": "1"
	}

	proxima_ref += 1
	enviar_json(mensagem)


func enviar_heartbeat() -> void:
	enviar_json({
		"topic": "phoenix",
		"event": "heartbeat",
		"payload": {},
		"ref": str(proxima_ref)
	})

	proxima_ref += 1


func enviar_json(dados: Dictionary) -> void:
	var erro := socket.send_text(JSON.stringify(dados))

	if erro != OK:
		push_warning("Erro ao enviar mensagem: %s" % erro)


func _exit_tree() -> void:
	socket.close()
