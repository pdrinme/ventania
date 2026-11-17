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
# Etapa 7: robustez da rede
const JANELA_RECONEXAO_S := 60     # quem cai fica no jogo (parado) este tempo esperando reconectar
const MAX_PACOTES_S := 240         # acima disso, pacotes do segundo são ignorados
const EXPULSAR_PACOTES_S := 900    # inundação: expulsa
const MAX_INVALIDOS := 40          # pacotes malformados até expulsar
const RELEVANCIA_M := 250.0        # snapshots: só entidades até esta distância
const RELEVANCIA_PERTO_M := 120.0  # entre PERTO e RELEVANCIA: metade da frequência
const TIRO_AUDIVEL_M := 320.0      # traçantes/golpes só para quem está perto

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
	var bot: BotCerebro = null      # bot do servidor (sem conexão); null = humano
	var token := 0                  # ficha de sessão (reconexão)
	var conta := 0                  # conta do meta-servidor (ticket); 0 = sem conta
	var traje := ""                 # cosméticos equipados (do ticket; sem ticket = padrão). Só aparência.
	var picareta := ""
	var planador := ""
	var desconectado_tick := -1     # >= 0: caiu e está esperando reconectar
	var bytes_env := 0              # banda (só a carga útil dos pacotes, sem o cabeçalho do ENet)
	var bytes_rec := 0
	var pacotes_janela := 0
	var pacotes_na_janela := 0
	var invalidos := 0
	var expulso := false
	var bytes_env_rel := 0          # posição no último relatório
	var bytes_rec_rel := 0
	var stats := {}                 # métricas da partida (saques, curas, dano, Tormenta…)
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
var nav: NavGrade            # navegação dos bots (criada com o primeiro bot)
var bot_raios := 0           # orçamento de raios de percepção dos bots neste tick
var bot_planejamentos := 0   # orçamento de A* neste tick
var tempo_bots_us := 0       # custo acumulado dos cérebros (diagnóstico)
var tempo_tick_us := 0       # custo acumulado do tick inteiro (diagnóstico)
var ticks_medidos := 0
var _proximo_bot := 0
var _rng_nomes := RandomNumberGenerator.new()   # semente aleatória: nomes novos a cada partida
var max_jogadores := 16      # humanos por sala (sala cheia = recusa com mensagem)
var outras_salas := ""       # dica na recusa de sala cheia (ex.: "porta 24801")
var expulsos := 0            # diagnóstico/testes
var segredo_tickets := ""    # Etapa 8: se definido, confere tickets do meta-servidor
var ticket_obrigatorio := true   # false: aceita também quem entra direto pelo endereço (sem conta)
var porta := 0
signal match_report(d: Dictionary)   # fim de partida (Etapa 9): o MetaLink envia ao meta-servidor
var privada := false         # sala privada (meta-servidor): só começa quando o dono mandar
var cosmeticos_sem_ticket := {"traje": "", "picareta": "", "planador": ""}   # sem ticket: padrão; a partida local usa o equipado
var forcar_inicio := false   # sala privada: o dono mandou começar
var reservas_pendentes := 0  # matchmaking: jogadores com vaga reservada que ainda não chegaram
var reconexoes := 0
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


func start(p_porta: int, bind_ip := "*") -> Error:
	porta = p_porta
	peer = ENetMultiplayerPeer.new()
	peer.set_bind_ip(bind_ip)
	var e := peer.create_server(porta, Protocol.MAX_PLAYERS + 4, 3, 0, 0)   # folga: recusar "sala cheia" com mensagem e reconexões
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
	while peer and peer.get_available_packet_count() > 0:
		var de := peer.get_packet_peer()
		var dados := peer.get_packet()
		var c: Cliente = clientes.get(de)
		if c:
			if c.expulso:
				continue
			c.bytes_rec += dados.size()
			if tick - c.pacotes_janela >= Protocol.TICK_RATE:
				c.pacotes_janela = tick
				c.pacotes_na_janela = 0
			c.pacotes_na_janela += 1
			if c.pacotes_na_janela > EXPULSAR_PACOTES_S:
				_expulsar(de, "Pacotes demais (inundação).")
				continue
			if c.pacotes_na_janela > MAX_PACOTES_S:
				continue
		if not _receber(de, dados) and c:
			c.invalidos += 1
			if c.invalidos > MAX_INVALIDOS:
				_expulsar(de, "Pacotes inválidos.")
	tick += 1
	var t0 := Time.get_ticks_usec()
	var cfg_bots := BotCerebro.config()
	bot_raios = int(cfg_bots.get("raios_visao_por_tick", 24))
	bot_planejamentos = 2
	for c: Cliente in clientes.values():
		if c.bot and c.pawn:
			var tb := Time.get_ticks_usec()
			c.fila.append(c.bot.pensar())
			tempo_bots_us += Time.get_ticks_usec() - tb
	for c: Cliente in clientes.values():
		if c.pawn:
			_simular(c, dt)
			if c.dead and tick >= c.respawn_tick and partida == null:
				_reviver(c)
	_expirar_desconectados()
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
	tempo_tick_us += Time.get_ticks_usec() - t0
	ticks_medidos += 1


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


## Trata um pacote. Retorna false se ele for malformado/indevido (conta para expulsão).
func _receber(de: int, dados: PackedByteArray) -> bool:
	var c: Cliente = clientes.get(de)
	match Protocol.msg_type(dados):
		Protocol.C_HELLO:
			if c and c.pawn:
				return false
			var h := Protocol.unpack_hello(dados)
			if h.is_empty() or h["protocol"] != Protocol.GAME_PROTOCOL:
				send_to(de, Protocol.pack_reject("Versão do jogo diferente da do servidor. Atualize o jogo."), true)
				_desligar(de)
				return true
			if h["token"] != 0 and _reconectar(de, h["token"]):
				return true
			var nome := _limpar_nome(h["name"])
			var conta := 0
			var cos := cosmeticos_sem_ticket.duplicate()
			if not segredo_tickets.is_empty() and (ticket_obrigatorio or not h["ticket"].is_empty()):
				var t := Ticket.verify(segredo_tickets, h["ticket"], porta)
				if t.is_empty():
					send_to(de, Protocol.pack_reject("Entre pelo lobby: ticket de partida inválido ou vencido."), true)
					_desligar(de)
					return true
				conta = int(t["acc"])
				nome = _limpar_nome(str(t["name"]))
				cos = {"traje": str(t.get("traje", "")), "picareta": str(t.get("pic", "")), "planador": str(t.get("plan", ""))}
				if t.get("priv", false):
					privada = true          # já sabe antes do próximo heartbeat
				for o: Cliente in clientes.values():
					if o.conta == conta and o.pawn and o.bot == null:
						# mesma conta voltando (outro aparelho ou ficha perdida): assume o personagem
						if o.token != 0 and _reconectar(de, o.token):
							return true
						send_to(de, Protocol.pack_reject("Essa conta já está nesta partida."), true)
						_desligar(de)
						return true
			if humanos() >= max_jogadores:
				var dica := (" Tente outra sala: %s." % outras_salas) if not outras_salas.is_empty() else ""
				send_to(de, Protocol.pack_reject("Sala cheia (%d jogadores).%s" % [max_jogadores, dica]), true)
				_desligar(de)
				return true
			for chave in cos:
				if not Cosmeticos.valid_id(str(cos[chave])):
					cos[chave] = ""
			_entrar(de, nome, cos)
			if clientes.has(de):
				clientes[de].conta = conta
		Protocol.C_INPUT:
			if c == null or c.pawn == null:
				return false
			var lista := Protocol.unpack_inputs(dados)
			if lista.is_empty():
				return false
			for cmd: Protocol.InputCmd in lista:
				if c.ultimo_seq < 0:
					c.ultimo_seq = cmd.seq - 1          # reconectou: continua da sequência do cliente
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
				return false
			if tick - c.build_janela >= Protocol.TICK_RATE:
				c.build_janela = tick
				c.build_na_janela = 0
			c.build_na_janela += 1
			var lim := c.build_na_janela > MAX_BUILD_S
			if Protocol.msg_type(dados) == Protocol.C_BUILD:
				var b := Protocol.unpack_build(dados)
				if b.is_empty():
					return false
				var r := Inventory.Err.BUSY if lim else build.try_build(c, b)
				send_to(de, Protocol.pack_inv_result(b["req"], Protocol.OP_BUILD, r), true)
			else:
				var ed := Protocol.unpack_edit(dados)
				if ed.is_empty():
					return false
				var r := Inventory.Err.BUSY if lim else build.try_edit(c, ed["id"], ed["mask"])
				send_to(de, Protocol.pack_inv_result(ed["req"], Protocol.OP_EDIT, r), true)
		Protocol.C_INV:
			if c == null or c.pawn == null:
				return false
			var op := Protocol.unpack_inv(dados)
			if op.is_empty():
				return false
			if tick - c.ops_janela >= Protocol.TICK_RATE:
				c.ops_janela = tick
				c.ops_na_janela = 0
			c.ops_na_janela += 1
			var r := Inventory.Err.BUSY if c.ops_na_janela > MAX_OPS_INV_S else combat.inventory_op(c, op)
			send_to(de, Protocol.pack_inv_result(op["req"], op["op"], r), true)
		Protocol.C_BYE:
			if c:
				c.token = 0               # saiu de propósito: a desconexão a seguir é saída

		_:
			return false
	return true


func _entrar(de: int, nome: String, cos := {}) -> void:
	var c := Cliente.new()
	c.peer_id = de
	c.id = _proximo_id
	_proximo_id = (_proximo_id % 60000) + 1
	c.nome = nome
	c.traje = cos.get("traje", "")
	c.picareta = cos.get("picareta", "")
	c.planador = cos.get("planador", "")
	c.token = (_rng_nomes.randi() << 31) ^ _rng_nomes.randi() ^ (Time.get_ticks_usec() << 8)
	c.token = absi(c.token) | 1
	c.pawn = Pawn.new()
	c.pawn.entity_id = c.id
	c.pawn.name = "pawn_%d" % c.id
	world.add_child(c.pawn)
	clientes[de] = c
	_reaparecer(c)
	_dar_kit(c)
	if partida:
		partida.on_join(c)
	send_to(de, Protocol.pack_welcome(c.id, tick, world.map_name(), c.token), true)
	_estado_completo(de, c)
	_log("entrou: %s (id %d)" % [nome, c.id])
	player_joined.emit(c.id, nome)


## Tudo que um cliente precisa ao entrar (ou ao reconectar): nomes, loot, construções.
func _estado_completo(de: int, c: Cliente) -> void:
	for outro: Cliente in clientes.values():
		if outro.pawn == null:
			continue                    # conexão que ainda não se apresentou (sem nome)
		send_to(de, Protocol.pack_player_info(outro.id, outro.nome, outro.traje, outro.picareta, outro.planador), true)
		if outro.peer_id != de:
			send_to(outro.peer_id, Protocol.pack_player_info(c.id, c.nome, c.traje, c.picareta, c.planador), true)
	for i in bonecos.size():
		send_to(de, Protocol.pack_player_info(bonecos[i]["id"], "Boneco %d" % (i + 1)), true)
	for m in loot.full_state():
		send_to(de, m, true)
	for m in build.full_state():
		send_to(de, m, true)


## Reconexão: a ficha devolve o mesmo personagem (id, inventário, posição, partida).
func _reconectar(de: int, token: int) -> bool:
	var c: Cliente = null
	for o: Cliente in clientes.values():
		if o.token == token and o.pawn and o.bot == null and o.peer_id != de:
			c = o
	if c == null:
		return false
	if c.desconectado_tick < 0 and c.peer_id > 0:
		# a conexão antiga ainda não expirou no ENet (queda de rede): a nova assume
		var antigo := c.peer_id
		clientes.erase(antigo)
		peer.disconnect_peer(antigo, true)
	clientes.erase(c.peer_id)
	clientes.erase(de)                  # o registro provisório criado em _on_conectou
	c.peer_id = de
	c.desconectado_tick = -1
	c.fila.clear()
	c.ultimo_seq = -1
	c.esperando = 0
	c.invalidos = 0
	clientes[de] = c
	reconexoes += 1
	send_to(de, Protocol.pack_welcome(c.id, tick, world.map_name(), c.token, true), true)
	_estado_completo(de, c)
	if partida:
		send_to(de, Protocol.pack_match(partida.match_dict()), true)
		if partida.tormenta:
			send_to(de, Protocol.pack_storm(partida.tormenta.to_dict()), true)
		if partida.onibus and partida.estado == Protocol.MATCH_ONIBUS:
			send_to(de, Protocol.pack_bus(partida.onibus.to_dict()), true)
	c.dirty = true
	_log("reconectou: %s (id %d)" % [c.nome, c.id])
	return true


func _expulsar(de: int, motivo: String) -> void:
	var c: Cliente = clientes.get(de)
	if c and c.expulso:
		return
	expulsos += 1
	_log("expulso (peer %d): %s" % [de, motivo])
	send_to(de, Protocol.pack_reject(motivo), true)
	if c:
		c.expulso = true                # nada mais é enviado nem recebido dele
		c.token = 0                     # sem reconexão
	_desligar(de)


## Desconecta depois de entregar o que está na fila (a mensagem de recusa chega).
func _desligar(de: int) -> void:
	var p := peer.get_peer(de)
	if p:
		p.peer_disconnect_later()


## Quem caiu e não voltou na janela de reconexão sai de vez.
func _expirar_desconectados() -> void:
	for c: Cliente in clientes.values().duplicate():
		if c.desconectado_tick >= 0 and tick - c.desconectado_tick > JANELA_RECONEXAO_S * Protocol.TICK_RATE:
			clientes.erase(c.peer_id)
			_sair(c)


## Contas presentes (para o meta-servidor saber quem já chegou).
func accounts() -> Array:
	return clientes.values().filter(func(c): return c.conta > 0 and c.pawn != null).map(func(c): return c.conta)


func humanos() -> int:
	return clientes.values().filter(func(c): return c.pawn != null and c.bot == null).size()


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
	var em_jogo := partida == null or partida.estado == Protocol.MATCH_ONIBUS or partida.estado == Protocol.MATCH_JOGO
	if c and c.pawn and c.token != 0 and not c.dead and em_jogo:
		# fica no jogo esperando reconectar (parado; o servidor simula sem entradas)
		c.desconectado_tick = tick
		c.peer_id = -(200000 + c.id)
		c.fila.clear()
		clientes[c.peer_id] = c
		_log("caiu: %s (id %d) — aguardando reconexão por %d s" % [c.nome, c.id, JANELA_RECONEXAO_S])
		return
	if c and c.pawn:
		_sair(c)


func _sair(c: Cliente) -> void:
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
	var meia := tick % (Protocol.SNAPSHOT_EVERY * 2) == 0
	for c: Cliente in clientes.values():
		if c.pawn and c.peer_id > 0:
			var lista := estados if c.dead else _relevantes(c, estados, meia)
			send_to(c.peer_id, Protocol.pack_snapshot(tick, maxi(0, c.ultimo_seq), lista), false, Protocol.CH_SNAPSHOT)


## Relevância (interest management): o próprio jogador sempre; outros até
## RELEVANCIA_M; os de longe (> PERTO) só em metade dos snapshots. Quem está
## eliminado assiste e recebe todos.
static func relevant(distancia: float, eu: bool, meia: bool) -> bool:
	if eu:
		return true
	if distancia > RELEVANCIA_M:
		return false
	return distancia <= RELEVANCIA_PERTO_M or meia


func _relevantes(c: Cliente, estados: Array, meia: bool) -> Array:
	var p := c.pawn.global_position
	var out := []
	for e: Protocol.EntityState in estados:
		if relevant(Vector2(e.position.x - p.x, e.position.z - p.z).length(), e.id == c.id, meia):
			out.append(e)
	return out


## Para quem está perto de `pos` (tiros, golpes): os de longe não precisam.
func broadcast_near(pos: Vector3, dados: PackedByteArray, confiavel: bool, exceto := -1, raio := TIRO_AUDIVEL_M) -> void:
	for c: Cliente in clientes.values():
		if c.pawn and c.peer_id > 0 and c.peer_id != exceto and (c.dead or c.pawn.global_position.distance_to(pos) <= raio):
			send_to(c.peer_id, dados, confiavel, Protocol.CH_RELIABLE if confiavel else Protocol.CH_SNAPSHOT)


func send_to(para: int, dados: PackedByteArray, confiavel: bool, canal := Protocol.CH_RELIABLE) -> void:
	if peer == null or para <= 0:
		return                       # bots e quem caiu não têm conexão
	var c: Cliente = clientes.get(para)
	if c:
		if c.expulso:
			return
		c.bytes_env += dados.size()
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


# ---------- bots (Etapa 6) ----------

## Cria um bot do servidor. dificuldade: "facil", "medio" ou "dificil".
func add_bot(dificuldade: String) -> Cliente:
	if nav == null:
		nav = NavGrade.new(world)
		# pisos primeiro (as rampas e escadas se ligam a eles)
		for p: Construcoes.Peca in build.estado.pecas.values():
			if p.tipo != Grade.RAMPA:
				nav.set_piece(p.tipo, p.cell, p.rot, p.mask, true)
		for p: Construcoes.Peca in build.estado.pecas.values():
			if p.tipo == Grade.RAMPA:
				nav.set_piece(p.tipo, p.cell, p.rot, p.mask, true)
		nav.resolve_stairs()
	var cfg := BotCerebro.config()
	var c := Cliente.new()
	c.id = _proximo_id
	_proximo_id = (_proximo_id % 60000) + 1
	c.peer_id = -c.id
	c.nome = _nome_bot()
	_proximo_bot += 1
	c.pawn = Pawn.new()
	c.pawn.entity_id = c.id
	c.pawn.name = "bot_%d" % c.id
	world.add_child(c.pawn)
	c.bot = BotCerebro.new(self, c, dificuldade, c.id * 7919 + tick)
	c.stats["dificuldade"] = dificuldade
	clientes[c.peer_id] = c
	var trajes := Cosmeticos.bot_outfits()
	c.traje = trajes[_rng_nomes.randi() % trajes.size()]
	_reaparecer(c)
	broadcast(Protocol.pack_player_info(c.id, c.nome, c.traje, c.picareta, c.planador), true)
	return c


## Nome sorteado da lista de nomes de jogadores, sem repetir na partida nem
## coincidir com quem está jogando (a dificuldade não aparece no nome).
func _nome_bot() -> String:
	var lista := BotCerebro.nomes()
	var usados := {}
	for o: Cliente in clientes.values():
		usados[o.nome.to_lower()] = true
	if lista.is_empty():
		return "Jogador%d" % (_proximo_bot + 1)
	for i in 50:
		var n := lista[_rng_nomes.randi() % lista.size()]
		if not usados.has(n.to_lower()):
			return n
	return lista[_rng_nomes.randi() % lista.size()] + str(_proximo_bot)


func remove_bot(c: Cliente) -> void:
	clientes.erase(c.peer_id)
	if c.pawn:
		c.pawn.queue_free()
	broadcast(Protocol.pack_player_left(c.id), true)


func bots() -> Array:
	return clientes.values().filter(func(c): return c.bot != null)


## Bots que ouvem um tiro (alcance de audição).
func bots_hear(atirador: Cliente) -> void:
	var alcance := float(BotCerebro.config().get("audicao_tiro_m", 70))
	var p := atirador.pawn.global_position
	for c: Cliente in clientes.values():
		if c.bot and c != atirador and not c.dead and c.pawn and c.pawn.global_position.distance_to(p) < alcance:
			c.bot.on_heard(atirador.id, p)


static func add_stat(c: Cliente, nome: String, n := 1) -> void:
	c.stats[nome] = int(c.stats.get(nome, 0)) + n


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


## Banda por cliente humano conectado desde o último relatório (kbit/s de carga
## útil; o ENet acrescenta ~28-40 bytes de cabeçalho UDP/ENet por pacote).
func bandwidth(segundos: float, zerar := true) -> Dictionary:
	var por := {}
	for c: Cliente in clientes.values():
		if c.pawn == null or c.bot != null or c.peer_id <= 0:
			continue
		por[c.id] = {"nome": c.nome,
				"desce_kbps": (c.bytes_env - c.bytes_env_rel) * 8.0 / 1000.0 / maxf(segundos, 0.001),
				"sobe_kbps": (c.bytes_rec - c.bytes_rec_rel) * 8.0 / 1000.0 / maxf(segundos, 0.001)}
		if zerar:
			c.bytes_env_rel = c.bytes_env
			c.bytes_rec_rel = c.bytes_rec
	return por


func report(segundos: float) -> String:
	var b := bandwidth(segundos)
	var desce := b.values().map(func(x): return x["desce_kbps"])
	var media := 0.0
	for v in desce:
		media += v
	media /= maxf(1.0, desce.size())
	var tick_ms := tempo_tick_us / 1000.0 / maxf(1.0, ticks_medidos)
	tempo_tick_us = 0
	ticks_medidos = 0
	return "%d humano(s), %d bot(s), %s; banda/cliente média %.1f kbit/s (máx %.1f); tick %.2f ms; reconexões %d; expulsos %d" % [
			humanos(), bots().size(), partida.estado_nome() if partida else "treino", media,
			desce.max() if not desce.is_empty() else 0.0, tick_ms, reconexoes, expulsos]


func player_count() -> int:
	return clientes.values().filter(func(c): return c.pawn != null).size()


func _log(msg: String) -> void:
	var l := get_node_or_null("/root/Log")
	if l:
		l.info("servidor", msg)
	else:
		print("[servidor] " + msg)
