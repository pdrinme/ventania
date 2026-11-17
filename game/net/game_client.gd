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
signal piece(d: Dictionary)
signal piece_gone(id: int, motivo: int)
signal pieces_hp(lista: Array)
signal build_reset
signal bus(d: Dictionary)

const TEMPO_CONEXAO_S := 6.0

var peer: ENetMultiplayerPeer
var connected := false
var my_id := 0
var _nome := ""
var _hello_enviado := false
var _inicio := 0.0
var _encerrado := false
# Etapa 7: reconexão, medição de banda e simulador de rede ruim
var token := 0                 # ficha de sessão do servidor (WELCOME)
var host_atual := ""
var porta_atual := 0
var bytes_env := 0             # carga útil (sem cabeçalhos do ENet/UDP)
var bytes_rec := 0
var lag_ms := 0                # simulador: atraso de ida (e de volta)
var jitter_ms := 0
var perda := 0.0               # 0..1, só pacotes não confiáveis (os confiáveis o ENet reenvia)
var _fila_env: Array = []      # [hora_ms, dados, confiavel, canal]
var _fila_rec: Array = []      # [hora_ms, dados]
var _rng := RandomNumberGenerator.new()


## Lê --lag=MS, --jitter=MS e --perda=PCT da linha de comando (testes de rede ruim).
func simulate_from_args(args: PackedStringArray) -> void:
	for a in args:
		if a.begins_with("--lag="):
			lag_ms = maxi(0, a.trim_prefix("--lag=").to_int())
		elif a.begins_with("--jitter="):
			jitter_ms = maxi(0, a.trim_prefix("--jitter=").to_int())
		elif a.begins_with("--perda="):
			perda = clampf(a.trim_prefix("--perda=").to_float() / 100.0, 0.0, 0.9)


func simulating() -> bool:
	return lag_ms > 0 or jitter_ms > 0 or perda > 0.0


## Reconecta ao mesmo servidor apresentando a ficha: volta o mesmo personagem.
func reconnect() -> Error:
	if host_atual.is_empty():
		return ERR_UNCONFIGURED
	if peer:
		peer.close()
	_fila_env.clear()
	_fila_rec.clear()
	return connect_to(host_atual, porta_atual, _nome)


func connect_to(host: String, porta: int, nome: String) -> Error:
	host_atual = host
	porta_atual = porta
	connected = false
	_encerrado = false
	_hello_enviado = false
	peer = ENetMultiplayerPeer.new()
	var e := peer.create_client(host, porta, 3, 0, 0)
	if e != OK:
		return e
	peer.host.bandwidth_limit(0, 0)   # ver GameServer.start: evita descarte de pacotes pelo ENet
	_nome = nome
	_inicio = Time.get_ticks_msec() / 1000.0
	var este := peer
	peer.peer_disconnected.connect(func(_id):
		if not _encerrado and este == peer:
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
		_enviar(Protocol.pack_hello(_nome, token), true, Protocol.CH_RELIABLE)
	elif status != MultiplayerPeer.CONNECTION_CONNECTED and not connected \
			and Time.get_ticks_msec() / 1000.0 - _inicio > TEMPO_CONEXAO_S:
		_encerrado = true
		rejected.emit("O servidor não respondeu. Confira o endereço e se ele está ligado.")
		return
	var agora := Time.get_ticks_msec()
	while peer and peer.get_available_packet_count() > 0:
		var confiavel := peer.get_packet_mode() == MultiplayerPeer.TRANSFER_MODE_RELIABLE
		var d := peer.get_packet()
		bytes_rec += d.size()
		if simulating():
			if not confiavel and _rng.randf() < perda:
				continue
			var t := agora + _atraso()
			if not _fila_rec.is_empty():
				t = maxi(t, _fila_rec[-1][0])
			_fila_rec.append([t, d])
		else:
			_receber(d)
	if simulating():
		_escoar(agora)


func _atraso() -> int:
	return lag_ms + (_rng.randi_range(0, jitter_ms) if jitter_ms > 0 else 0)


## Entrega/envia o que já "chegou" (a ordem é mantida: o atraso nunca ultrapassa o anterior).
func _escoar(agora: int) -> void:
	while not _fila_env.is_empty() and _fila_env[0][0] <= agora and peer:
		var e: Array = _fila_env.pop_front()
		_enviar_ja(e[1], e[2], e[3])
	while not _fila_rec.is_empty() and _fila_rec[0][0] <= agora and not _encerrado:
		_receber(_fila_rec.pop_front()[1])


func _receber(dados: PackedByteArray) -> void:
	match Protocol.msg_type(dados):
		Protocol.S_WELCOME:
			var w := Protocol.unpack_welcome(dados)
			if not w.is_empty():
				my_id = w["id"]
				token = w.get("token", 0)
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
		Protocol.S_PIECE:
			var pc := Protocol.unpack_piece(dados)
			if not pc.is_empty():
				piece.emit(pc)
		Protocol.S_PIECE_GONE:
			var g := Protocol.unpack_piece_gone(dados)
			if not g.is_empty():
				piece_gone.emit(g[0], g[1])
		Protocol.S_PIECES_HP:
			pieces_hp.emit(Protocol.unpack_pieces_hp(dados))
		Protocol.S_BUILD_RESET:
			build_reset.emit()
		Protocol.S_BUS:
			var o := Protocol.unpack_bus(dados)
			if not o.is_empty():
				bus.emit(o)
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


func send_build(escolha: int, material: int, cell: Vector3i, rot: int) -> int:
	if not connected:
		return -1
	_req = (_req % 65000) + 1
	_enviar(Protocol.pack_build({"req": _req, "escolha": escolha, "material": material, "cell": cell, "rot": rot}), true, Protocol.CH_RELIABLE)
	return _req


func send_edit(id: int, mask: int) -> int:
	if not connected:
		return -1
	_req = (_req % 65000) + 1
	_enviar(Protocol.pack_edit(_req, id, mask), true, Protocol.CH_RELIABLE)
	return _req


func rtt_ms() -> int:
	if peer == null or not connected:
		return -1
	var p := peer.get_peer(1)
	return int(p.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)) if p else -1


## Fecha a conexão. `despedida`: avisa o servidor que é uma saída de propósito
## (sem isso, o servidor guarda o lugar por 60 s esperando reconexão). A
## despedida tem que chegar antes da desconexão (o ENet descarta o que chega
## depois), então a conexão passa para um nó auxiliar que a mantém até o
## servidor confirmar (no máximo 1 s), mesmo que este GameClient seja liberado.
func close(despedida := true) -> void:
	var estava := connected
	_encerrado = true
	connected = false
	_fila_env.clear()
	_fila_rec.clear()
	if peer == null:
		return
	var tree := Engine.get_main_loop() as SceneTree
	if despedida and estava and peer.get_peer(1) and tree:
		_enviar_ja(PackedByteArray([Protocol.C_BYE]), true, Protocol.CH_RELIABLE)
		for con in peer.peer_disconnected.get_connections():
			peer.peer_disconnected.disconnect(con["callable"])
		peer.get_peer(1).peer_disconnect_later()
		var d := _Despedida.new()
		d.peer = peer
		tree.root.add_child.call_deferred(d)
		peer = null
		return
	peer.close()
	peer = null


class _Despedida:
	extends Node
	var peer: ENetMultiplayerPeer
	var t := 0.0

	func _process(dt: float) -> void:
		t += dt
		peer.poll()
		if t > 1.0 or peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
			peer.close()
			queue_free()


func _enviar(dados: PackedByteArray, confiavel: bool, canal: int) -> void:
	if simulating():
		if not confiavel and _rng.randf() < perda:
			bytes_env += dados.size()
			return
		var t := Time.get_ticks_msec() + _atraso()
		if not _fila_env.is_empty():
			t = maxi(t, _fila_env[-1][0])
		_fila_env.append([t, dados, confiavel, canal])
		return
	_enviar_ja(dados, confiavel, canal)


func _enviar_ja(dados: PackedByteArray, confiavel: bool, canal: int) -> void:
	bytes_env += dados.size()
	peer.set_target_peer(1)
	peer.set_transfer_channel(canal)
	peer.transfer_mode = MultiplayerPeer.TRANSFER_MODE_RELIABLE if confiavel else MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED
	peer.put_packet(dados)
