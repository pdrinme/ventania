extends Node
## Cliente simulado para testes de partida completa: conecta por ENet como um
## jogador de verdade (GameClient) e decide as entradas sozinho, só com o que o
## servidor envia (snapshots, status, loot, Tormenta). Não é a IA da Etapa 6:
## é um "jogador de teste" simples.
##  - sem arma: vai até a arma mais próxima no chão e aperta Interagir;
##  - com arma: seleciona, mira no inimigo mais próximo (até 35 m) e atira;
##  - inimigo colado e sem arma: golpe de picareta;
##  - fora disso: anda para o centro da próxima zona segura.

var client := GameClient.new()
var nome := ""
var seq := 0
var pos := Vector3.ZERO
var vel := Vector3.ZERO
var entidades := {}                 # id -> {"pos", "flags"}
var loot := {}                      # id -> dados
var status := {}
var tormenta := {}
var partida := {}
var resultado := {}
var morto := false
var atirou := 0
var pegou := 0
var golpes := 0
var _alterna := false
var _parado := 0
var _ultima_pos := Vector3.ZERO
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_child(client)
	_rng.seed = hash(nome)
	client.snapshot_received.connect(_snap)
	client.status_received.connect(func(st): status = st)
	client.loot_spawned.connect(func(l): loot[l["id"]] = l)
	client.loot_removed.connect(func(id): loot.erase(id))
	client.storm.connect(func(t): tormenta = t)
	client.match_state.connect(func(m): partida = m)
	client.result.connect(func(r): resultado = r)


func conectar(porta: int) -> void:
	client.connect_to("127.0.0.1", porta, nome)


func _snap(s: Dictionary) -> void:
	entidades.clear()
	for e: Protocol.EntityState in s["entities"]:
		if e.id == client.my_id:
			pos = e.position
			vel = e.velocity
			morto = e.flags & Protocol.F_DEAD != 0
		else:
			entidades[e.id] = {"pos": e.position, "flags": e.flags}


func _arma() -> int:
	for i in status.get("slots", []).size():
		var id := ItemDB.id_of(status["slots"][i]["item"])
		if ItemDB.is_weapon(id):
			var w := ItemDB.weapon(id)
			var reserva: int = status["ammo"][ItemDB.ammo_types().find(w["municao"])]
			if status["slots"][i]["mag"] > 0 or reserva > 0:
				return i
	return -1


func _inimigo() -> Dictionary:
	var melhor := {}
	var dist := 1e9
	for id in entidades:
		var e: Dictionary = entidades[id]
		if e["flags"] & Protocol.F_DEAD != 0:
			continue
		var d := pos.distance_to(e["pos"])
		if d < dist:
			dist = d
			melhor = {"id": id, "pos": e["pos"], "dist": d}
	return melhor


func _mirar(c: Protocol.InputCmd, alvo: Vector3) -> void:
	var d := alvo - (pos + Vector3(0, Combat.EYE_STAND, 0))
	c.yaw = atan2(-d.x, -d.z)
	c.pitch = atan2(d.y, Vector2(d.x, d.z).length())
	var r := Combat.aim_ray(pos, false, c.yaw, c.pitch)
	d = alvo - (r["origin"] as Vector3)          # corrige o ombro
	c.yaw = atan2(-d.x, -d.z)
	c.pitch = atan2(d.y, Vector2(d.x, d.z).length())


func _andar(c: Protocol.InputCmd, alvo: Vector3) -> void:
	var d := alvo - pos
	c.yaw = atan2(-d.x, -d.z)
	c.move = Vector2(0, 1)
	c.buttons |= Protocol.BTN_SPRINT
	# preso (parede/árvore): pula e desvia
	if pos.distance_to(_ultima_pos) < 0.05:
		_parado += 1
	else:
		_parado = 0
	if _parado > 10:
		c.buttons |= Protocol.BTN_JUMP
		c.move = Vector2(1 if _rng.randf() < 0.5 else -1, 1).normalized()
	_ultima_pos = pos


func _physics_process(_dt: float) -> void:
	client.poll()
	if not client.connected:
		return
	seq += 1
	var c := Protocol.InputCmd.new()
	c.seq = seq
	_alterna = not _alterna
	if partida.get("estado", 0) == Protocol.MATCH_JOGO and not morto and not status.is_empty():
		_decidir(c)
	client.send_inputs([c])


func _decidir(c: Protocol.InputCmd) -> void:
	var arma := _arma()
	var inimigo := _inimigo()
	var na_mao: int = status.get("selected", Protocol.SELECTED_PICKAXE)
	if arma >= 0 and not inimigo.is_empty() and inimigo["dist"] < 35.0:
		if na_mao != arma:
			c.slot = arma + 1
		_mirar(c, inimigo["pos"] + Vector3(0, 1.1, 0))
		if _alterna:
			c.buttons |= Protocol.BTN_FIRE
			atirou += 1
		if inimigo["dist"] > 12.0:
			c.move = Vector2(0, 0.6)
		return
	if arma < 0 and not inimigo.is_empty() and inimigo["dist"] < 2.6:
		if na_mao != Protocol.SELECTED_PICKAXE:
			c.slot = Protocol.SLOT_PICKAXE
		_mirar(c, inimigo["pos"] + Vector3(0, 1.1, 0))
		c.buttons |= Protocol.BTN_FIRE
		golpes += 1
		return
	if arma < 0:
		var alvo := {}
		var dist := 90.0
		for l in loot.values():
			if l["ammo"] != 0 or l.get("mat", 0) != 0 or not ItemDB.is_weapon(ItemDB.id_of(l["item"])):
				continue
			var d := pos.distance_to(l["pos"])
			if d < dist:
				dist = d
				alvo = l
		if not alvo.is_empty():
			if dist < 1.6:
				if _alterna:
					c.buttons |= Protocol.BTN_INTERACT
					pegou += 1
				return
			_andar(c, alvo["pos"])
			return
	# zona segura
	if not tormenta.is_empty():
		var centro: Vector2 = tormenta["c_para"]
		var alvo3 := Vector3(centro.x, pos.y, centro.y)
		if pos.distance_to(alvo3) > maxf(4.0, float(tormenta["r_para"]) * 0.5):
			_andar(c, alvo3)
		elif not inimigo.is_empty():
			_andar(c, inimigo["pos"])
