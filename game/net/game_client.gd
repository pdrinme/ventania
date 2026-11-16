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
signal status_received(st: Dictionary)
signal shot_received(shot: Dictionary)
signal hit_confirmed(hit: Dictionary)
signal damaged(info: Dictionary)
signal eliminated(info: Dictionary)
signal loot_spawned(l: Dictionary)
signal loot_removed(id: int)
signal chest_changed(id: int, open: bool)
signal inventory_result(r: Dictionary)
signal melee_impact(m: Dictionary)
signal match_state(m: Dictionary)
signal storm(t: Dictionary)
signal result(r: Dictionary)

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
		Protocol.S_STATUS:
			var st := Protocol.unpack_status(dados)
			if not st.is_empty():
				status_received.emit(st)
		Protocol.S_SHOT:
			var sh := Protocol.unpack_shot(dados)
			if not sh.is_empty():
				shot_received.emit(sh)
		Protocol.S_HIT:
			hit_confirmed.emit(Protocol.unpack_hit(dados))
		Protocol.S_DAMAGED:
			damaged.emit(Protocol.unpack_damaged(dados))
		Protocol.S_ELIM:
			eliminated.emit(Protocol.unpack_elim(dados))
		Protocol.S_LOOT:
			var l := Protocol.unpack_loot(dados)
			if not l.is_empty():
				loot_spawned.emit(l)
		Protocol.S_LOOT_GONE:
			loot_removed.emit(Protocol.unpack_u16_msg(dados)[0])
		Protocol.S_CHEST:
			var c := Protocol.unpack_u16_msg(dados)
			chest_changed.emit(c[0], c[1] == 1)
		Protocol.S_INV_RESULT:
			var r := Protocol.unpack_inv_result(dados)
			if not r.is_empty():
				inventory_result.emit(r)
		Protocol.S_MATCH:
			var m := Protocol.unpack_match(dados)
			if not m.is_empty():
				match_state.emit(m)
		Protocol.S_STORM:
			var st := Protocol.unpack_storm(dados)
			if not st.is_empty():
				storm.emit(st)
		Protocol.S_RESULT:
			var r := Protocol.unpack_result(dados)
			if not r.is_empty():
				result.emit(r)
		Protocol.S_MELEE:
			var m := Protocol.unpack_melee(dados)
			if not m.is_empty():
				melee_impact.emit(m)


func send_inputs(cmds: Array) -> void:
	if connected:
		_enviar(Protocol.pack_inputs(cmds), false, Protocol.CH_INPUT)


var _req := 0


## Pede uma operação de inventário ao servidor. Retorna o número do pedido (a
## resposta chega em inventory_result com o mesmo "req").
func send_inventory(op: Dictionary) -> int:
	if not connected:
		return -1
	_req = (_req % 65000) + 1
	op["req"] = _req
	_enviar(Protocol.pack_inv(op), true, Protocol.CH_RELIABLE)
	return _req


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
