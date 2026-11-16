class_name GameServer
extends Node
## Servidor autoritativo da partida (ENet). Recebe entradas, simula movimento
## (Movement) e combate (CombatServer), administra o loot (LootServer) e envia
## snapshots. Roda dentro do jogo (treino local, em um mundo 3D separado) ou como
## servidor dedicado (--servidor).

signal player_joined(id: int, name: String)
signal player_left(id: int)
## Impacto da picareta no cenário (Etapa 5: vida das peças e coleta se ligam aqui).
signal melee_hit(player_id: int, collider: Object, material: int, pos: Vector3)

const MAX_FILA := 8          # entradas guardadas por jogador
const MAX_POR_TICK := 2      # recupera atraso sem permitir "speed hack"
const ESPERA_MAX := 6        # ticks esperando entrada antes de simular sem ela (~200 ms)
const DUMMY_ID_BASE := 60001
const MAX_OPS_INV_S := 12    # operações de inventário por segundo (evita spam)
const MAX_BUILD_S := 15      # peças/edições por segundo (construção rápida, sem spam)

class Cliente:
	var peer_id := 0
	var id := 0
	var nome := ""
	var pawn: Pawn
	var fila: Array = []
	var ultimo_seq := 0
	var ultimo_cmd := Protocol.InputCmd.new()
	var esperando := 0       # ticks seguidos sem entrada nova
	var simulados := 0       # passos simulados = relógio de combate deste jogador
	var descartados := 0     # entradas jogadas fora por fila cheia (diagnóstico)
	var inventados := 0      # passos simulados sem entrada do cliente (diagnóstico)
	var maior_fila := 0
	# combate
	var inv := Inventory.new()
	var vit := Vitals.new()
	var fire_next := 0.0
	var reload_end := -1.0
	var reload_total := 0.0
	var use_end := -1.0
	var use_total := 0.0
	var prev_fire := false
	var prev_reload := false
	var prev_interact := false
	var interact_steps := 0
	var interact_chest := -1
	var aiming := false
	# picareta (relógio = simulados)
	var swing_start := -1.0
	var swing_prev := -1.0
	var swing_hit := false
	var combo := 0
	var swings := 0          # golpes iniciados (diagnóstico/testes)
	var melee_hits := 0      # impactos registrados (diagnóstico/testes)
	# inventário
	var drops := 0           # itens largados (espalha no chão)
	var ops_janela := 0      # tick em que a janela de 1 s começou
	var ops_na_janela := 0
	var build_janela := 0
	var build_na_janela := 0
	var dead := false
	var respawn_tick := 0
	var dirty := true

var world: Mapa
var modo := "treino"         # "treino" (reaparece, bonecos) ou "br" (partida Battle Royale)
var partida: PartidaBR
var peer: ENetMultiplayerPeer
var tick := 0
var clientes := {}           # peer_id -> Cliente
var loot: LootServer
var combat: CombatServer
var build: BuildServer
var bonecos: Array = []      # [{"id", "pawn", "vit", "last_hit"}]
var kit_inicial := true      # treino: reaparece com uma pistola e munição
var _proximo_id := 1
var _spawns := 0


## modo "br": PartidaBR (config opcional, ex.: tempos curtos nos testes).
func _init(mundo: Mapa, semente_loot := 0, modo_partida := "treino", config_partida := {}) -> void:
	world = mundo
	modo = modo_partida
	combat = CombatServer.new(self)
	build = BuildServer.new(self)
	loot = LootServer.new(mundo, func(d): broadcast(d, true), semente_loot)
	if modo == "br":
		kit_inicial = false
		loot.reabastecer = false
		loot.reset(0, true)          # na espera não há loot; ele é sorteado ao começar
		partida = PartidaBR.new(self, config_partida)


func _ready() -> void:
	build.init_map()
	if modo != "treino":
		return
	for i in world.dummies().size():
		var p := Pawn.new()
		p.entity_id = DUMMY_ID_BASE + i
		world.add_child.call_deferred(p)
		p.position = world.dummies()[i]
		var v := Vitals.new()
		v.shield = 50
		bonecos.append({"id": p.entity_id, "pawn": p, "vit": v, "last_hit": 0})


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
			if c.dead and tick >= c.respawn_tick and partida == null:
				_reviver(c)
	combat.update_dummies()
	loot.update(tick)
	build.update()
	if partida:
		partida.update()
	for c: Cliente in clientes.values():
		if c.pawn:
			combat.record(tick, c.id, c.pawn.global_position, c.pawn.crouched)
			if c.dirty:
				c.dirty = false
				send_to(c.peer_id, Protocol.pack_status(_status(c)), true)
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
			if c.pawn.queda == Pawn.NO_ONIBUS and partida:
				partida.on_bus_input(c, cmd)     # Pular com as portas abertas = saltar
			Movement.step(c.pawn, cmd, dt)
			c.simulados += 1
			if not c.dead:
				combat.process(c, cmd)
	if c.pawn.global_position.y < world.death_height() and not c.dead:
		combat.eliminate(c, c.id, "")


func _receber(de: int, dados: PackedByteArray) -> void:
	var c: Cliente = clientes.get(de)
	match Protocol.msg_type(dados):
		Protocol.C_HELLO:
			if c and c.pawn:
				return
			var h := Protocol.unpack_hello(dados)
			if h.is_empty() or h["protocol"] != Protocol.GAME_PROTOCOL:
				send_to(de, Protocol.pack_reject("Versão do jogo diferente da do servidor. Atualize o jogo."), true)
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
		Protocol.C_BUILD, Protocol.C_EDIT:
			if c == null or c.pawn == null:
				return
			if tick - c.build_janela >= Protocol.TICK_RATE:
				c.build_janela = tick
				c.build_na_janela = 0
			c.build_na_janela += 1
			var lim := c.build_na_janela > MAX_BUILD_S
			if Protocol.msg_type(dados) == Protocol.C_BUILD:
				var b := Protocol.unpack_build(dados)
				if not b.is_empty():
					var r := Inventory.Err.BUSY if lim else build.try_build(c, b)
					send_to(de, Protocol.pack_inv_result(b["req"], Protocol.OP_BUILD, r), true)
			else:
				var ed := Protocol.unpack_edit(dados)
				if not ed.is_empty():
					var r := Inventory.Err.BUSY if lim else build.try_edit(c, ed["id"], ed["mask"])
					send_to(de, Protocol.pack_inv_result(ed["req"], Protocol.OP_EDIT, r), true)
		Protocol.C_INV:
			if c == null or c.pawn == null:
				return
			var op := Protocol.unpack_inv(dados)
			if op.is_empty():
				return
			if tick - c.ops_janela >= Protocol.TICK_RATE:
				c.ops_janela = tick
				c.ops_na_janela = 0
			c.ops_na_janela += 1
			var r := Inventory.Err.BUSY if c.ops_na_janela > MAX_OPS_INV_S else combat.inventory_op(c, op)
			send_to(de, Protocol.pack_inv_result(op["req"], op["op"], r), true)


func _entrar(de: int, nome: String) -> void:
	var c := Cliente.new()
	c.peer_id = de
	c.id = _proximo_id
	_proximo_id = (_proximo_id % 60000) + 1
	c.nome = nome
	c.pawn = Pawn.new()
	c.pawn.entity_id = c.id
	c.pawn.name = "pawn_%d" % c.id
	world.add_child(c.pawn)
	clientes[de] = c
	_reaparecer(c)
	_dar_kit(c)
	if partida:
		partida.on_join(c)
	send_to(de, Protocol.pack_welcome(c.id, tick, world.map_name()), true)
	for outro: Cliente in clientes.values():
		send_to(de, Protocol.pack_player_info(outro.id, outro.nome), true)
		if outro.peer_id != de:
			send_to(outro.peer_id, Protocol.pack_player_info(c.id, c.nome), true)
	for i in bonecos.size():
		send_to(de, Protocol.pack_player_info(bonecos[i]["id"], "Boneco %d" % (i + 1)), true)
	for m in loot.full_state():
		send_to(de, m, true)
	for m in build.full_state():
		send_to(de, m, true)
	_log("entrou: %s (id %d)" % [nome, c.id])
	player_joined.emit(c.id, nome)


func _dar_kit(c: Cliente) -> void:
	# a picareta já vem no Inventory (permanente); o treino dá também uma pistola na mão
	if kit_inicial:
		c.inv.add_item("faisca", 0)
		c.inv.add_ammo("leve", 48)
		c.inv.select(0)
		for t in ItemDB.material_types():
			c.inv.add_material(t, int(Grade.config()["kit_treino"]))
	c.dirty = true


func _reaparecer(c: Cliente) -> void:
	c.pawn.global_position = world.spawn_point(_spawns)
	c.pawn.velocity = Vector3.ZERO
	_spawns += 1


func _reviver(c: Cliente) -> void:
	c.dead = false
	c.vit.reset()
	c.inv = Inventory.new()
	c.reload_end = -1.0
	c.use_end = -1.0
	c.swing_start = -1.0
	_reaparecer(c)
	_dar_kit(c)


func _on_conectou(id: int) -> void:
	Protocol.configure_peer(peer.get_peer(id))
	clientes[id] = Cliente.new()
	clientes[id].peer_id = id


func _on_desconectou(id: int) -> void:
	var c: Cliente = clientes.get(id)
	clientes.erase(id)
	if c and c.pawn:
		if partida:
			partida.on_leave(c)
		if not c.dead:
			loot.drop_inventory(c.inv, c.pawn.global_position)
		c.pawn.queue_free()
		broadcast(Protocol.pack_player_left(c.id), true)
		_log("saiu: %s (id %d)" % [c.nome, c.id])
		player_left.emit(c.id)


func _status(c: Cliente) -> Dictionary:
	var slots := []
	for s: Inventory.Slot in c.inv.slots:
		slots.append({"item": ItemDB.index_of(s.item), "rarity": s.rarity, "mag": s.mag, "count": s.count})
	var acao := 0
	var restante := 0.0
	var total := 0.0
	if c.reload_end >= 0.0:
		acao = 1
		restante = c.reload_end - c.simulados
		total = c.reload_total
	elif c.use_end >= 0.0:
		acao = 2
		restante = c.use_end - c.simulados
		total = c.use_total
	var ms := 1000.0 / Protocol.TICK_RATE
	var sel := Protocol.SELECTED_PICKAXE if c.inv.pickaxe_selected() else c.inv.selected
	return {"hp": c.vit.health, "shield": c.vit.shield, "selected": sel, "action": acao,
			"action_left_ms": clampi(roundi(restante * ms), 0, 65535), "action_total_ms": clampi(roundi(total * ms), 0, 65535),
			"slots": slots, "ammo": ItemDB.ammo_types().map(func(t): return c.inv.ammo[t]),
			"materials": ItemDB.material_types().map(func(t): return c.inv.materials[t])}


func _enviar_snapshots() -> void:
	var estados: Array = []
	for c: Cliente in clientes.values():
		if c.pawn:
			var e := c.pawn.to_state()
			var s := c.inv.current()
			e.weapon = ItemDB.index_of(s.item) if not c.dead else 0
			e.pitch = c.ultimo_cmd.pitch
			if c.dead:
				e.flags |= Protocol.F_DEAD
			if c.aiming:
				e.flags |= Protocol.F_AIMING
			var a := combat.action_of(c)
			e.action = a[0]
			e.progress = a[1]
			estados.append(e)
	for b in bonecos:
		var e: Protocol.EntityState = (b["pawn"] as Pawn).to_state()
		e.flags |= Protocol.F_DUMMY | Protocol.F_ON_FLOOR
		estados.append(e)
	for c: Cliente in clientes.values():
		if c.pawn:
			send_to(c.peer_id, Protocol.pack_snapshot(tick, c.ultimo_seq, estados), false, Protocol.CH_SNAPSHOT)


func send_to(para: int, dados: PackedByteArray, confiavel: bool, canal := Protocol.CH_RELIABLE) -> void:
	if peer == null:
		return
	peer.set_target_peer(para)
	peer.set_transfer_channel(canal)
	peer.transfer_mode = MultiplayerPeer.TRANSFER_MODE_RELIABLE if confiavel else MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED
	peer.put_packet(dados)


func broadcast(dados: PackedByteArray, confiavel: bool) -> void:
	for c: Cliente in clientes.values():
		if c.pawn:
			send_to(c.peer_id, dados, confiavel, Protocol.CH_RELIABLE if confiavel else Protocol.CH_SNAPSHOT)


func broadcast_except(peer_id: int, dados: PackedByteArray, confiavel: bool) -> void:
	for c: Cliente in clientes.values():
		if c.pawn and c.peer_id != peer_id:
			send_to(c.peer_id, dados, confiavel, Protocol.CH_RELIABLE if confiavel else Protocol.CH_SNAPSHOT)


static func _limpar_nome(n: String) -> String:
	var limpo := ""
	for ch in n.strip_edges():
		if ch.unicode_at(0) >= 32:
			limpo += ch
	limpo = limpo.substr(0, Protocol.MAX_NAME).strip_edges()
	return limpo if not limpo.is_empty() else "Jogador"


func client_by_id(id: int) -> Cliente:
	for c: Cliente in clientes.values():
		if c.id == id:
			return c
	return null


## Volta para a área de espera (partida BR fora de jogo).
func respawn_lobby(c: Cliente) -> void:
	c.dead = false
	_reaparecer(c)
	c.dirty = true


func log_msg(msg: String) -> void:
	_log(msg)


func player_count() -> int:
	return clientes.values().filter(func(c): return c.pawn != null).size()


func _log(msg: String) -> void:
	var l := get_node_or_null("/root/Log")
	if l:
		l.info("servidor", msg)
	else:
		print("[servidor] " + msg)
