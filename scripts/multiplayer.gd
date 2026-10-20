extends Node

const PORT = 7000
const MAX_CLIENTS = 2

func criar_servidor():
	var peer = ENetMultiplayerPeer.new()

	var server = peer.create_server(PORT, MAX_CLIENTS)

	if server != OK:
		print("Erro ao criar servidor: ", server)
		return

	multiplayer.multiplayer_peer = peer
	print("Servidor criado! Aguardando jogadores...")


func conectar_cliente(ip: String):
	var peer = ENetMultiplayerPeer.new()

	var cliente = peer.create_client(ip, PORT)

	if cliente != OK:
		print("Erro ao conectar: ", cliente)
		return

	multiplayer.multiplayer_peer = peer
	print("Tentando conectar ao servidor...")


func _ready():
	multiplayer.peer_connected.connect(_quando_jogador_conectar)
	multiplayer.peer_disconnected.connect(_quando_jogador_desconectar)
	multiplayer.connected_to_server.connect(_quando_conectar)
	multiplayer.connection_failed.connect(_quando_falhar)


func _quando_jogador_conectar(id: int):
	print("Jogador conectado: ", id)


func _quando_jogador_desconectar(id: int):
	print("Jogador desconectado: ", id)


func _quando_conectar():
	print("Conectado ao servidor!")


func _quando_falhar():
	print("Falha na conexão!")
