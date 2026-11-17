class_name CombatServer
extends RefCounted
## Combate no servidor (autoridade). Chamado uma vez por entrada processada de cada
## jogador, logo depois do movimento. Os tempos (cadência, recarga, uso) são medidos
## em PASSOS DO JOGADOR (c.simulados), o mesmo relógio que o cliente usa ao prever.

const PASSOS_TROCA := 6               # 0,2 s para sacar a arma ao trocar de espaço
const REWIND_MAX_TICKS := 12          # compensação de latência limitada a 400 ms
const HISTORICO_TICKS := 32
const RESPAWN_TICKS := 4 * Protocol.TICK_RATE

var server: GameServer
var history := {}                     # entity_id -> Array[[tick, pos, agachado]]


func _init(s: GameServer) -> void:
	server = s


# ---------- histórico para compensação de latência ----------

func record(tick: int, id: int, pos: Vector3, agachado: bool) -> void:
	var h: Array = history.get(id, [])
	h.append([tick, pos, agachado])
	if h.size() > HISTORICO_TICKS:
		h.pop_front()
	history[id] = h


## Posição de um alvo no tick que o atirador via (clampado).
func rewound(id: int, view_tick: int, atual: Vector3, agachado: bool) -> Array:
	var alvo_tick := clampi(view_tick, server.tick - REWIND_MAX_TICKS, server.tick)
	var h: Array = history.get(id, [])
	for i in range(h.size() - 1, -1, -1):
		if h[i][0] <= alvo_tick:
			if i + 1 < h.size() and h[i + 1][0] > h[i][0]:
				var t := float(alvo_tick - h[i][0]) / float(h[i + 1][0] - h[i][0])
				return [(h[i][1] as Vector3).lerp(h[i + 1][1], t), h[i][2]]
			return [h[i][1], h[i][2]]
	return [atual, agachado]


## [ação, progresso 0..1] para animar o personagem nos outros clientes.
func action_of(c: GameServer.Cliente) -> Array:
	var passos := float(c.simulados)
	if c.reload_end >= 0.0 and c.reload_total > 0.0:
		return [Protocol.ACT_RELOAD, clampf(1.0 - (c.reload_end - passos) / c.reload_total, 0.0, 1.0)]
	if c.use_end >= 0.0 and c.use_total > 0.0:
		return [Protocol.ACT_USE, clampf(1.0 - (c.use_end - passos) / c.use_total, 0.0, 1.0)]
	if c.swing_start >= 0.0:
		var k := clampf((passos - c.swing_start) / float(Combat.melee_swing_steps()), 0.0, 1.0)
		return [Protocol.ACT_SWING_B if c.combo == 1 else Protocol.ACT_SWING, k]
	if c.interact_steps > 0 and c.interact_chest >= 0:
		return [Protocol.ACT_CHEST, clampf(c.interact_steps / float(LootServer.ABRIR_BAU_PASSOS), 0.0, 1.0)]
	return [Protocol.ACT_NONE, 0.0]


# ---------- por entrada ----------

func process(c: GameServer.Cliente, cmd: Protocol.InputCmd) -> void:
	if c.pawn.queda != 0:
		# no ônibus, em queda ou planando: sem tiro, golpe, interação ou troca de item
		c.prev_fire = cmd.has(Protocol.BTN_FIRE)
		c.prev_reload = cmd.has(Protocol.BTN_RELOAD)
		c.prev_interact = cmd.has(Protocol.BTN_INTERACT)
		return
	var passos := float(c.simulados)
	var inv := c.inv
	var pedido := Inventory.PICKAXE if cmd.slot == Protocol.SLOT_PICKAXE else cmd.slot - 1
	if cmd.slot > 0 and inv.select(pedido):
		_cancelar(c)
		c.fire_next = maxf(c.fire_next, passos + PASSOS_TROCA)
		c.dirty = true
	var s := inv.current()

	if c.reload_end >= 0.0 and passos >= c.reload_end:
		inv.finish_reload()
		c.reload_end = -1.0
		c.dirty = true
	if c.use_end >= 0.0 and passos >= c.use_end:
		_aplicar_consumivel(c)
		c.use_end = -1.0
		c.dirty = true

	var fogo := cmd.has(Protocol.BTN_FIRE)
	var recarregar := cmd.has(Protocol.BTN_RELOAD) and not c.prev_reload
	if ItemDB.is_weapon(s.item):
		var w := ItemDB.weapon(s.item)
		if recarregar and c.reload_end < 0.0 and inv.reload_amount() > 0:
			_iniciar_recarga(c, passos)
		var gatilho := fogo if w["automatica"] else (fogo and not c.prev_fire)
		if gatilho and c.reload_end < 0.0 and passos >= c.fire_next:
			if s.mag > 0:
				s.mag -= 1
				c.fire_next = passos + Protocol.TICK_RATE / float(w["cadencia"])
				c.dirty = true
				_disparar(c, cmd, s, w)
			elif inv.reload_amount() > 0:
				_iniciar_recarga(c, passos)
	elif ItemDB.is_consumable(s.item):
		if fogo and c.use_end < 0.0 and _pode_usar(c, s.item):
			var t := float(ItemDB.consumable(s.item)["tempo_s"]) * Protocol.TICK_RATE
			c.use_end = passos + t
			c.use_total = t
			c.dirty = true
	elif ItemDB.is_tool_item(s.item):
		_picareta(c, cmd, passos, fogo)

	_interagir(c, cmd)
	if server.loot.auto_ammo(inv, c.pawn.global_position, c.id, server.tick):
		c.dirty = true
	c.prev_fire = fogo
	c.prev_reload = cmd.has(Protocol.BTN_RELOAD)
	c.prev_interact = cmd.has(Protocol.BTN_INTERACT)
	c.aiming = cmd.has(Protocol.BTN_AIM)


func cancel(c: GameServer.Cliente) -> void:
	_cancelar(c)
	c.fire_next = 0.0
	c.swing_prev = -1.0


func _cancelar(c: GameServer.Cliente) -> void:
	c.reload_end = -1.0
	c.use_end = -1.0
	c.swing_start = -1.0


# ---------- picareta ----------

## Golpes enquanto o botão estiver segurado. Cada golpe dura melee_swing_steps()
## passos e registra NO MÁXIMO um impacto, no passo melee_impact_step() (o quadro
## de impacto da animação). Golpes seguidos alternam o lado (combo 0/1).
func _picareta(c: GameServer.Cliente, cmd: Protocol.InputCmd, passos: float, fogo: bool) -> void:
	var n := Combat.melee_swing_steps()
	if c.swing_start >= 0.0:
		var k := passos - c.swing_start
		if not c.swing_hit and k >= Combat.melee_impact_step():
			c.swing_hit = true
			_golpe(c, cmd)
		if k >= n:
			c.swing_start = -1.0
	if fogo and c.swing_start < 0.0 and passos >= c.fire_next:
		var seguido := c.swing_prev >= 0.0 and passos - c.swing_prev <= n + 1
		c.combo = (1 - c.combo) if seguido else 0
		c.swing_start = passos
		c.swing_prev = passos
		c.swing_hit = false
		c.fire_next = passos + n
		c.swings += 1


## Impacto do golpe: primeiro o que estiver mais perto na linha da mira, entre o
## cenário (raio de física) e jogadores/bonecos (hitbox voltada no tempo).
func _golpe(c: GameServer.Cliente, cmd: Protocol.InputCmd) -> void:
	var p := c.pawn
	var raio := Combat.aim_ray(p.global_position, p.crouched, cmd.yaw, cmd.pitch)
	var origem: Vector3 = raio["origin"]
	var d: Vector3 = raio["dir"]
	var mundo := Combat.melee_trace(server.world.get_world_3d().direct_space_state, origem, d)
	var t_mundo: float = mundo["t"] if not mundo.is_empty() else Combat.melee_range()
	var melhor := {}
	for a in _alvos(c, cmd.view_tick):
		var h := Hitbox.test(origem, d, a["pos"], a["crouched"])
		if not h.is_empty() and h["t"] <= t_mundo and (melhor.is_empty() or h["t"] < melhor["t"]):
			melhor = h
			melhor["alvo"] = a
	if not melhor.is_empty():
		var ponto: Vector3 = origem + d * float(melhor["t"])
		c.melee_hits += 1
		server.broadcast_near(origem, Protocol.pack_melee({"swinger": c.id, "pos": ponto, "normal": -d, "material": ImpactMaterial.JOGADOR,
				"flags": Protocol.MELEE_PLAYER, "target": melhor["alvo"]["id"]}), true, -1, 160.0)
		_aplicar_dano(c, melhor["alvo"], int(ItemDB.tool_def(Inventory.PICKAXE_ID)["dano_jogador"]), false, ponto, Inventory.PICKAXE_ID)
		return
	if mundo.is_empty():
		return
	c.melee_hits += 1
	server.broadcast_near(origem, Protocol.pack_melee({"swinger": c.id, "pos": mundo["pos"], "normal": mundo["normal"], "material": mundo["material"]}), true, -1, 160.0)
	# Etapa 5: dano nas construções e coleta de materiais
	server.build.on_pickaxe(c, mundo["collider"], mundo["material"])
	server.melee_hit.emit(c.id, mundo["collider"], mundo["material"], mundo["pos"])


func _iniciar_recarga(c: GameServer.Cliente, passos: float) -> void:
	var s := c.inv.current()
	c.reload_end = passos + ItemDB.reload_time(s.item, s.rarity) * Protocol.TICK_RATE
	c.reload_total = c.reload_end - passos
	c.dirty = true


func _pode_usar(c: GameServer.Cliente, item: String) -> bool:
	var d := ItemDB.consumable(item)
	if d.has("vida"):
		return c.vit.health < int(d["limite"])
	return c.vit.shield < int(d["limite"])


func _aplicar_consumivel(c: GameServer.Cliente) -> void:
	var s := c.inv.current()
	if not ItemDB.is_consumable(s.item):
		return
	var d := ItemDB.consumable(s.item)
	if d.has("vida"):
		c.vit.heal(int(d["vida"]), int(d["limite"]))
	else:
		c.vit.add_shield(int(d["escudo"]), int(d["limite"]))
	s.count -= 1
	GameServer.add_stat(c, "curas")
	if s.count <= 0:
		c.inv.remove_slot(c.inv.selected)


func _soltar_bau(c: GameServer.Cliente) -> void:
	if c.interact_chest >= 0 and c.interact_chest < server.loot.chests.size():
		if server.loot.chests[c.interact_chest].get("abrindo", 0) == c.id:
			server.loot.chests[c.interact_chest]["abrindo"] = 0
	c.interact_steps = 0
	c.interact_chest = -1


func _interagir(c: GameServer.Cliente, cmd: Protocol.InputCmd) -> void:
	var pos := c.pawn.global_position
	if not cmd.has(Protocol.BTN_INTERACT):
		_soltar_bau(c)
		return
	var bau := server.loot.nearest_chest(pos)
	if bau >= 0:
		# um jogador por vez: quem começou a abrir "reserva" o baú até soltar
		var dono: int = server.loot.chests[bau].get("abrindo", 0)
		if dono != 0 and dono != c.id:
			c.interact_steps = 0
			return
		server.loot.chests[bau]["abrindo"] = c.id
		c.interact_steps = c.interact_steps + 1 if c.interact_chest == bau else 1
		c.interact_chest = bau
		if c.interact_steps >= LootServer.ABRIR_BAU_PASSOS:
			server.loot.open_chest(bau)
			server.loot.chests[bau]["abrindo"] = 0
			c.interact_steps = 0
			c.interact_chest = -1
		return
	_soltar_bau(c)
	if not c.prev_interact:
		var id := server.loot.nearest_loot(pos)
		if id >= 0:
			# inventário cheio: troca pelo item NA MÃO (escolha clara do jogador);
			# com a picareta na mão não troca nada e avisa
			var troca := c.inv.selected if not c.inv.pickaxe_selected() else -1
			var r := pick_up(c, id, troca)
			if r != Inventory.Err.OK:
				server.send_to(c.peer_id, Protocol.pack_inv_result(0, Protocol.OP_PICKUP, r), true)


# ---------- inventário (operações pedidas pelo cliente; o servidor decide) ----------

## Pega um item do chão. troca: espaço a substituir se não houver lugar (-1 = nenhum).
func pick_up(c: GameServer.Cliente, id: int, troca: int) -> int:
	var r := server.loot.pick_up(id, c.inv, c.pawn.global_position, troca, drop_position(c, 0))
	if r == Inventory.Err.OK:
		c.fire_next = maxf(c.fire_next, float(c.simulados) + PASSOS_TROCA)
		c.dirty = true
		GameServer.add_stat(c, "saques")
	return r


## Executa uma operação de C_INV. Retorna Inventory.Err.
func inventory_op(c: GameServer.Cliente, op: Dictionary) -> int:
	if c.dead or c.pawn == null:
		return Inventory.Err.INVALID
	var inv := c.inv
	var a: int = op["a"]
	var b: int = op["b"]
	var n: int = op["n"]
	var antes := inv.current()
	var r := Inventory.Err.INVALID
	match op["op"]:
		Protocol.OP_SWAP:
			r = inv.swap(a, b)
		Protocol.OP_SPLIT:
			r = inv.split(Inventory.PICKAXE if a == Protocol.SEM_ESPACO else a, n)
		Protocol.OP_DROP:
			var t := inv.take_from_slot(Inventory.PICKAXE if a == Protocol.SEM_ESPACO else a, n)
			r = t["error"]
			if r == Inventory.Err.OK:
				var s: Inventory.Slot = t["slot"]
				server.loot.spawn_item(s.item, s.rarity, s.count, s.mag if ItemDB.is_weapon(s.item) else -1,
						drop_position(c, c.drops), c.id, server.tick)
				c.drops += 1
		Protocol.OP_DROP_AMMO, Protocol.OP_DROP_MATERIAL:
			var tipos := ItemDB.ammo_types() if op["op"] == Protocol.OP_DROP_AMMO else ItemDB.material_types()
			if a < tipos.size() and n > 0:
				var saiu := inv.take_reserve(tipos[a], n)
				if saiu > 0:
					r = Inventory.Err.OK
					if op["op"] == Protocol.OP_DROP_AMMO:
						server.loot.spawn_ammo(tipos[a], drop_position(c, c.drops), saiu, c.id, server.tick)
					else:
						server.loot.spawn_material(tipos[a], drop_position(c, c.drops), saiu, c.id, server.tick)
					c.drops += 1
				else:
					r = Inventory.Err.EMPTY
		Protocol.OP_PICKUP:
			var l: Dictionary = server.loot.loot.get(op["loot"], {})
			if l.is_empty():
				r = Inventory.Err.GONE
			elif c.pawn.global_position.distance_to(l["pos"]) > LootServer.PEGAR_DIST + LootServer.FOLGA_DIST:
				r = Inventory.Err.TOO_FAR
			else:
				r = pick_up(c, op["loot"], b if Inventory.valid_slot(b) else -1)
	if r == Inventory.Err.OK:
		# o item na mão mudou (largado/trocado): cancela recarga/uso/golpe
		if inv.current() != antes or inv.current().is_empty():
			_cancelar(c)
		c.dirty = true
	return r


## Onde um item largado cai: 1,6 m à frente (fora do alcance da coleta automática
## de munição), espalhado por i, no chão da frente; parede no caminho -> aos pés.
func drop_position(c: GameServer.Cliente, i: int) -> Vector3:
	var p := c.pawn
	var frente := Basis(Vector3.UP, c.ultimo_cmd.yaw) * Vector3(0, 0, -1)
	var ang := (i % 5 - 2) * 0.35
	var alvo := p.global_position + (Basis(Vector3.UP, ang) * frente) * 1.6
	var espaco := server.world.get_world_3d().direct_space_state
	var peito := p.global_position + Vector3(0, 1.0, 0)
	var q := PhysicsRayQueryParameters3D.create(peito, alvo + Vector3(0, 1.0, 0), Pawn.LAYER_WORLD)
	if not espaco.intersect_ray(q).is_empty():
		alvo = p.global_position
	var desce := PhysicsRayQueryParameters3D.create(alvo + Vector3(0, 1.2, 0), alvo + Vector3(0, -3.0, 0), Pawn.LAYER_WORLD)
	var chao := espaco.intersect_ray(desce)
	return (chao["position"] as Vector3) + Vector3(0, 0.02, 0) if not chao.is_empty() else alvo


# ---------- disparo ----------

func _disparar(c: GameServer.Cliente, cmd: Protocol.InputCmd, s: Inventory.Slot, w: Dictionary) -> void:
	var p := c.pawn
	var raio := Combat.aim_ray(p.global_position, p.crouched, cmd.yaw, cmd.pitch)
	var movendo := Vector2(p.velocity.x, p.velocity.z).length() > 0.5
	var disp := Combat.spread_deg(w, cmd.has(Protocol.BTN_AIM), movendo, p.crouched, p.grounded)
	var dirs := Combat.pellet_dirs(raio["dir"], disp, int(w["projeteis"]), Combat.shot_seed(c.id, cmd.seq))
	var alcance := float(w["alcance"])
	var espaco := server.world.get_world_3d().direct_space_state
	var alvos := _alvos(c, cmd.view_tick)
	var danos := {}                       # alvo_id -> {"dano", "cabeca", "pos"}
	var danos_pecas := {}                 # peca_id -> dano (tiros destroem construções)
	var fins := []
	for d: Vector3 in dirs:
		var origem: Vector3 = raio["origin"]
		var fim := origem + d * alcance
		var q := PhysicsRayQueryParameters3D.create(origem, fim, Pawn.LAYER_WORLD)
		var parede := espaco.intersect_ray(q)
		var t_parede := origem.distance_to(parede["position"]) if not parede.is_empty() else alcance
		var peca := -1
		if not parede.is_empty() and parede["collider"] is Node and (parede["collider"] as Node).has_meta("peca_id"):
			peca = int((parede["collider"] as Node).get_meta("peca_id"))
		var melhor: Dictionary = {}
		for a in alvos:
			var h := Hitbox.test(origem, d, a["pos"], a["crouched"])
			if not h.is_empty() and h["t"] <= t_parede and (melhor.is_empty() or h["t"] < melhor["t"]):
				melhor = h
				melhor["alvo"] = a
		if melhor.is_empty():
			fins.append({"end": origem + d * t_parede, "hit": false})
			if peca >= 0:
				danos_pecas[peca] = int(danos_pecas.get(peca, 0)) + Combat.pellet_damage(s.item, s.rarity, false)
			continue
		var ponto: Vector3 = origem + d * float(melhor["t"])
		fins.append({"end": ponto, "hit": true})
		var aid: int = melhor["alvo"]["id"]
		var reg: Dictionary = danos.get(aid, {"dano": 0, "cabeca": false, "pos": ponto, "alvo": melhor["alvo"]})
		reg["dano"] += Combat.pellet_damage(s.item, s.rarity, melhor["head"])
		reg["cabeca"] = reg["cabeca"] or melhor["head"]
		danos[aid] = reg
	server.broadcast_near(raio["origin"], Protocol.pack_shot(c.id, raio["origin"], fins), false, c.peer_id)
	server.bots_hear(c)
	for reg in danos.values():
		_aplicar_dano(c, reg["alvo"], reg["dano"], reg["cabeca"], reg["pos"], s.item)
	for pid in danos_pecas:
		server.build.damage(pid, danos_pecas[pid] * float(Grade.config()["dano_armas"]), c)


## Alvos possíveis (outros jogadores vivos e bonecos), na posição que o atirador via.
func _alvos(atirador: GameServer.Cliente, view_tick: int) -> Array:
	var out := []
	for o: GameServer.Cliente in server.clientes.values():
		if o == atirador or o.pawn == null or o.dead:
			continue
		var r := rewound(o.id, view_tick, o.pawn.global_position, o.pawn.crouched)
		out.append({"id": o.id, "pos": r[0], "crouched": r[1], "cliente": o})
	for b in server.bonecos:
		out.append({"id": b["id"], "pos": (b["pawn"] as Pawn).global_position, "crouched": false, "boneco": b})
	return out


func _aplicar_dano(atirador: GameServer.Cliente, alvo: Dictionary, dano: int, cabeca: bool, pos: Vector3, arma: String) -> void:
	if server.partida and alvo.has("cliente") and not server.partida.dano_ativo():
		return                          # espera/contagem/fim: sem dano entre jogadores
	var vit: Vitals = alvo["cliente"].vit if alvo.has("cliente") else alvo["boneco"]["vit"]
	var r := vit.take_damage(dano)
	GameServer.add_stat(atirador, "dano", dano)
	if alvo.has("cliente") and (alvo["cliente"] as GameServer.Cliente).bot:
		(alvo["cliente"] as GameServer.Cliente).bot.on_damaged(atirador.id, atirador.pawn.global_position)
	var flags := (Protocol.HIT_HEAD if cabeca else 0) | (Protocol.HIT_SHIELD if r["shield"] > 0 else 0) | (Protocol.HIT_KILL if r["killed"] else 0)
	server.send_to(atirador.peer_id, Protocol.pack_hit(alvo["id"], dano, flags, pos), true)
	if alvo.has("cliente"):
		var v: GameServer.Cliente = alvo["cliente"]
		v.dirty = true
		server.send_to(v.peer_id, Protocol.pack_damaged(dano, atirador.pawn.global_position), true)
		if r["killed"]:
			eliminate(v, atirador.id, arma)
	else:
		var b: Dictionary = alvo["boneco"]
		b["last_hit"] = server.tick
		if r["killed"]:
			server.broadcast(Protocol.pack_elim(atirador.id, b["id"], ItemDB.index_of(arma)), true)
			vit.reset()


func eliminate(v: GameServer.Cliente, quem: int, arma: String) -> void:
	if v.dead:
		return
	if server.partida and server.partida.on_elimination(v, quem):
		# fora da partida em andamento (espera): só volta para a área de espera
		v.vit.reset()
		server.respawn_lobby(v)
		return
	v.dead = true
	v.respawn_tick = server.tick + RESPAWN_TICKS
	_cancelar(v)
	server.loot.drop_inventory(v.inv, v.pawn.global_position)   # a picareta fica com o jogador
	server.broadcast(Protocol.pack_elim(quem, v.id, ItemDB.index_of(arma)), true)
	v.dirty = true


## Bonecos regeneram a vida 3 s depois do último acerto.
func update_dummies() -> void:
	for b in server.bonecos:
		if server.tick - int(b["last_hit"]) > 3 * Protocol.TICK_RATE:
			(b["vit"] as Vitals).reset()
			(b["vit"] as Vitals).shield = 50
