class_name GameServer
extends Node
## Servidor autoritativo da partida (ENet). Recebe entradas, simula o movimento
## (Movement.step) e envia snapshots. Roda dentro do jogo (treino local, em um
## mundo 3D separado) ou como servidor dedicado (--servidor).

signal player_joined(id: int, name: String)
signal player_left(id: int)

const MAX_FILA := 8          # entradas guardadas por jogador
const MAX_POR_TICK := 2      # recupera atraso sem permitir "speed hack"
const ESPERA_MAX := 6        # ticks esperando entrada antes de simular sem ela (~200 ms)

class Cliente:
	var peer_id := 0
	var id := 0
	var nome := ""
	var pawn: Pawn
	var fila: Array = []
	var ultimo_seq := 0
	var ultimo_cmd := Protocol.InputCmd.new()
	var esperando := 0       # ticks seguidos sem entrada nova
	var simulados := 0       # passos simulados (para medir velocidade efetiva / testes)
	var descartados := 0     # entradas jogadas fora por fila cheia (diagnóstico)
	var inventados := 0      # passos simulados sem entrada do cliente (diagnóstico)
	var maior_fila := 0

var world: CampoTreino
var peer: ENetMultiplayerPeer
var tick := 0
var clientes := {}           # peer_id -> Cliente
var _proximo_id := 1
var _spawns := 0


func _init(mundo: CampoTreino) -> void:
	world = mundo


func start(porta: int, bind_ip := "*") -> Error:
	peer = ENetMultiplayerPeer.new()
	peer.set_bind_ip(bind_ip)
	var e := peer.create_server(porta, Protocol.MAX_PLAYERS, 3, 0, 0)
	if e != OK:
		return e
	# Banda "ilimitada" explícita: sem isso o ajuste de banda do ENet (a cada 1 s)
	# limitava o envio não confiável a ~1/32 dos pacotes (medido no teste de fumaça).
	peer.host.bandwidth_limit(0, 0)
	peer.peer_connected.connect(_on_conectou)
	peer.peer_disconnected.connect(_on_desconectou)
	_log("servidor ouvindo na porta %d (%s)" % [porta, bind_ip])
	return OK


func stop() -> void:
	if peer:
		peer.close()
		peer = null


func _physics_process(dt: float) -> void:
	if peer == null:
		return
	peer.poll()
	while peer.get_available_packet_count() > 0:
		var de := peer.get_packet_peer()
		_receber(de, peer.get_packet())
	tick += 1
	for c: Cliente in clientes.values():
		if c.pawn:
			_simular(c, dt)
	if tick % Protocol.SNAPSHOT_EVERY == 0:
		_enviar_snapshots()


## Cada entrada do cliente vira exatamente um passo, na mesma ordem: assim a
## predição do cliente e o servidor fazem a mesma conta. Sem entrada, o servidor
## espera (atraso normal da rede); só depois de ESPERA_MAX ticks simula sem ela.
func _simular(c: Cliente, dt: float) -> void:
	if c.fila.is_empty():
		c.esperando += 1
		if c.esperando > ESPERA_MAX:
			var parado := Protocol.InputCmd.new()   # só gravidade; sem mover
			parado.yaw = c.ultimo_cmd.yaw
			parado.buttons = c.ultimo_cmd.buttons & Protocol.BTN_CROUCH
			Movement.step(c.pawn, parado, dt)
			c.simulados += 1
			c.inventados += 1
	else:
		c.esperando = 0
		var n := MAX_POR_TICK if c.fila.size() > 2 else 1
		for i in mini(n, c.fila.size()):
			var cmd: Protocol.InputCmd = c.fila.pop_front()
			c.ultimo_seq = cmd.seq
			c.ultimo_cmd = cmd
			Movement.step(c.pawn, cmd, dt)
			c.simulados += 1
	if c.pawn.global_position.y < CampoTreino.ALTURA_MORTE:
		_reaparecer(c)


func _receber(de: int, dados: PackedByteArray) -> void:
	var c: Cliente = clientes.get(de)
	match Protocol.msg_type(dados):
		Protocol.C_HELLO:
			if c and c.pawn:
				return
			var h := Protocol.unpack_hello(dados)
			if h.is_empty() or h["protocol"] != Protocol.GAME_PROTOCOL:
				_enviar(de, Protocol.pack_reject("Versão do jogo diferente da do servidor. Atualize o jogo."), true)
				peer.disconnect_peer(de, false)
				return
			_entrar(de, _limpar_nome(h["name"]))
		Protocol.C_INPUT:
			if c == null or c.pawn == null:
				return
			for cmd: Protocol.InputCmd in Protocol.unpack_inputs(dados):
				if cmd.seq <= c.ultimo_seq or cmd.seq > c.ultimo_seq + 1000:
					continue
				if c.fila.any(func(x): return x.seq == cmd.seq):
					continue
				c.fila.append(cmd)
			c.fila.sort_custom(func(a, b): return a.seq < b.seq)
			c.maior_fila = maxi(c.maior_fila, c.fila.size())
			while c.fila.size() > MAX_FILA:
				c.fila.pop_front()
				c.descartados += 1


func _entrar(de: int, nome: String) -> void:
	var c := Cliente.new()
	c.peer_id = de
	c.id = _proximo_id
	_proximo_id = (_proximo_id % 65000) + 1
	c.nome = nome
	c.pawn = Pawn.new()
	c.pawn.entity_id = c.id
	c.pawn.name = "pawn_%d" % c.id
	world.add_child(c.pawn)
	clientes[de] = c
	_reaparecer(c)
	_enviar(de, Protocol.pack_welcome(c.id, tick, CampoTreino.NOME), true)
	for outro: Cliente in clientes.values():
		_enviar(de, Protocol.pack_player_info(outro.id, outro.nome), true)
		if outro.peer_id != de:
			_enviar(outro.peer_id, Protocol.pack_player_info(c.id, c.nome), true)
	_log("entrou: %s (id %d)" % [nome, c.id])
	player_joined.emit(c.id, nome)


func _reaparecer(c: Cliente) -> void:
	c.pawn.global_position = world.spawn_point(_spawns)
	c.pawn.velocity = Vector3.ZERO
	_spawns += 1


func _on_conectou(id: int) -> void:
	Protocol.configure_peer(peer.get_peer(id))
	clientes[id] = Cliente.new()
	clientes[id].peer_id = id


func _on_desconectou(id: int) -> void:
	var c: Cliente = clientes.get(id)
	clientes.erase(id)
	if c and c.pawn:
		c.pawn.queue_free()
		for outro: Cliente in clientes.values():
			_enviar(outro.peer_id, Protocol.pack_player_left(c.id), true)
		_log("saiu: %s (id %d)" % [c.nome, c.id])
		player_left.emit(c.id)


func _enviar_snapshots() -> void:
	var estados: Array = []
	for c: Cliente in clientes.values():
		if c.pawn:
			estados.append(c.pawn.to_state())
	for c: Cliente in clientes.values():
		if c.pawn:
			_enviar(c.peer_id, Protocol.pack_snapshot(tick, c.ultimo_seq, estados), false, Protocol.CH_SNAPSHOT)


func _enviar(para: int, dados: PackedByteArray, confiavel: bool, canal := Protocol.CH_RELIABLE) -> void:
	peer.set_target_peer(para)
	peer.set_transfer_channel(canal)
	peer.transfer_mode = MultiplayerPeer.TRANSFER_MODE_RELIABLE if confiavel else MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED
	peer.put_packet(dados)


static func _limpar_nome(n: String) -> String:
	var limpo := ""
	for ch in n.strip_edges():
		if ch.unicode_at(0) >= 32:
			limpo += ch
	limpo = limpo.substr(0, Protocol.MAX_NAME).strip_edges()
	return limpo if not limpo.is_empty() else "Jogador"


func player_count() -> int:
	return clientes.values().filter(func(c): return c.pawn != null).size()


func _log(msg: String) -> void:
	var l := get_node_or_null("/root/Log")
	if l:
		l.info("servidor", msg)
	else:
		print("[servidor] " + msg)
