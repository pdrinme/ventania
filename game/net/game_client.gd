class_name GameClient
extends Node
## Conexão do jogo com o servidor da partida (ENet). Não simula nada: só
## envia entradas e entrega mensagens decodificadas por sinais.
## Chame poll() no _physics_process (antes de amostrar a entrada).

signal welcomed(info: Dictionary)
signal rejected(reason: String)
signal disconnected
signal snapshot_received(snap: Dictionary)
signal player_info(id: int, name: String)
signal player_left(id: int)

const TEMPO_CONEXAO_S := 6.0

var peer: ENetMultiplayerPeer
var connected := false
var my_id := 0
var _nome := ""
var _hello_enviado := false
var _inicio := 0.0
var _encerrado := false


func connect_to(host: String, porta: int, nome: String) -> Error:
	peer = ENetMultiplayerPeer.new()
	var e := peer.create_client(host, porta, 3, 0, 0)
	if e != OK:
		return e
	peer.host.bandwidth_limit(0, 0)   # ver GameServer.start: evita descarte de pacotes pelo ENet
	_nome = nome
	_inicio = Time.get_ticks_msec() / 1000.0
	peer.peer_disconnected.connect(func(_id):
		if not _encerrado:
			_encerrado = true
			connected = false
			disconnected.emit())
	return OK


func poll() -> void:
	if peer == null or _encerrado:
		return
	peer.poll()
	var status := peer.get_connection_status()
	if status == MultiplayerPeer.CONNECTION_CONNECTED and not _hello_enviado:
		_hello_enviado = true
		Protocol.configure_peer(peer.get_peer(1))
		_enviar(Protocol.pack_hello(_nome), true, Protocol.CH_RELIABLE)
	elif status != MultiplayerPeer.CONNECTION_CONNECTED and not connected \
			and Time.get_ticks_msec() / 1000.0 - _inicio > TEMPO_CONEXAO_S:
		_encerrado = true
		rejected.emit("O servidor não respondeu. Confira o endereço e se ele está ligado.")
		return
	while peer and peer.get_available_packet_count() > 0:
		_receber(peer.get_packet())


func _receber(dados: PackedByteArray) -> void:
	match Protocol.msg_type(dados):
		Protocol.S_WELCOME:
			var w := Protocol.unpack_welcome(dados)
			if not w.is_empty():
				my_id = w["id"]
				connected = true
				welcomed.emit(w)
		Protocol.S_REJECT:
			_encerrado = true
			rejected.emit(Protocol.unpack_reject(dados))
		Protocol.S_SNAPSHOT:
			var s := Protocol.unpack_snapshot(dados)
			if not s.is_empty():
				snapshot_received.emit(s)
		Protocol.S_PLAYER_INFO:
			var i := Protocol.unpack_player_info(dados)
			player_info.emit(i["id"], i["name"])
		Protocol.S_PLAYER_LEFT:
			player_left.emit(Protocol.unpack_player_left(dados))


func send_inputs(cmds: Array) -> void:
	if connected:
		_enviar(Protocol.pack_inputs(cmds), false, Protocol.CH_INPUT)


func rtt_ms() -> int:
	if peer == null or not connected:
		return -1
	var p := peer.get_peer(1)
	return int(p.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)) if p else -1


func close() -> void:
	_encerrado = true
	if peer:
		peer.close()


func _enviar(dados: PackedByteArray, confiavel: bool, canal: int) -> void:
	peer.set_target_peer(1)
	peer.set_transfer_channel(canal)
	peer.transfer_mode = MultiplayerPeer.TRANSFER_MODE_RELIABLE if confiavel else MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED
	peer.put_packet(dados)
