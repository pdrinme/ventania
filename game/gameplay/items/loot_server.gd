class_name LootServer
extends RefCounted
## Loot no servidor: itens no chão, baús e munição. Envia as mudanças para todos
## pela função `broadcast(dados: PackedByteArray)` fornecida pelo GameServer.

const PEGAR_DIST := 2.2
const FOLGA_DIST := 0.8              # tolerância de latência para pegar pela tela de loot
const PROXIMOS_DIST := 3.2           # itens listados na interface de loot
const BLOQUEIO_DONO_TICKS := 2 * Protocol.TICK_RATE   # quem largou não recoleta na hora
const BAU_DIST := 2.4
const MUNICAO_AUTO_DIST := 1.3
const ABRIR_BAU_PASSOS := 15         # segurar interagir 0,5 s
const REABASTECER_BAU_TICKS := 45 * Protocol.TICK_RATE

var broadcast: Callable
var loot := {}                       # id -> {"id","item","rarity","count","mag","ammo","mat","pos","dono","ate"}
var chests: Array = []               # [{"pos","open","reopen_tick"}]
var rng := RandomNumberGenerator.new()
var reabastecer := true              # treino: baús fecham e reabastecem; BR: não
var _pontos: Array = []
var _proximo := 1


func _init(mundo: Mapa, enviar: Callable, semente := 0) -> void:
	broadcast = enviar
	rng.seed = semente if semente != 0 else int(Time.get_unix_time_from_system())
	for c in (mundo.chests() if mundo else CampoTreino.CHESTS):
		chests.append({"pos": c[0], "rot": c[1], "open": false, "reopen_tick": 0})
	_pontos = mundo.loot_points() if mundo else CampoTreino.LOOT_POINTS
	for p in _pontos:
		if rng.randf() < 0.75:
			_sortear_chao(p)


## Partida nova: remove todo o loot, fecha os baús e sorteia de novo (vazio = só limpa).
func reset(semente: int, vazio := false) -> void:
	for id in loot.keys():
		remove(id)
	for i in chests.size():
		if chests[i]["open"]:
			chests[i]["open"] = false
			broadcast.call(Protocol.pack_u16_msg(Protocol.S_CHEST, i, 0))
		chests[i]["reopen_tick"] = 0
		chests[i]["abrindo"] = 0
	if vazio:
		return
	rng.seed = semente
	for p in _pontos:
		if rng.randf() < 0.75:
			_sortear_chao(p)


func _sortear_chao(p: Vector3) -> void:
	if rng.randf() < 0.6:
		var arma := ItemDB.roll_weapon(rng)
		spawn_item(arma, ItemDB.roll_rarity(rng, false), 1, -1, p)
		spawn_ammo(ItemDB.weapon(arma)["municao"], p + Vector3(0.6, 0, 0.3))
	else:
		var c := ItemDB.roll_consumable(rng)
		spawn_item(c, 0, int(ItemDB.consumable(c)["quantidade"]), -1, p)


## dono/ate: quem largou o item não o recoleta automaticamente até o tick "ate".
func spawn_item(item: String, raridade: int, count: int, mag: int, pos: Vector3, dono := 0, tick := 0) -> int:
	assert(ItemDB.is_slot_item(item), "só armas e consumíveis vão ao chão")
	return _criar({"item": ItemDB.index_of(item), "rarity": raridade, "count": count, "mag": mag, "ammo": 0, "mat": 0,
			"pos": pos, "dono": dono, "ate": tick + BLOQUEIO_DONO_TICKS if dono else 0})


func spawn_ammo(tipo: String, pos: Vector3, quantidade := -1, dono := 0, tick := 0) -> int:
	var n := quantidade if quantidade > 0 else int(ItemDB.ammo(tipo)["caixa"])
	return _criar({"item": 0, "rarity": 0, "count": n, "mag": -1, "ammo": ItemDB.ammo_types().find(tipo) + 1, "mat": 0,
			"pos": pos, "dono": dono, "ate": tick + BLOQUEIO_DONO_TICKS if dono else 0})


func spawn_material(tipo: String, pos: Vector3, quantidade: int, dono := 0, tick := 0) -> int:
	return _criar({"item": 0, "rarity": 0, "count": quantidade, "mag": -1, "ammo": 0, "mat": ItemDB.material_types().find(tipo) + 1,
			"pos": pos, "dono": dono, "ate": tick + BLOQUEIO_DONO_TICKS if dono else 0})


static func is_reserve(l: Dictionary) -> bool:
	return l["ammo"] != 0 or l.get("mat", 0) != 0


## Itens (de espaço) perto de uma posição, do mais perto ao mais longe.
func loot_near(pos: Vector3, raio := PROXIMOS_DIST) -> Array:
	var out := loot.values().filter(func(l): return not is_reserve(l) and pos.distance_to(l["pos"]) <= raio)
	out.sort_custom(func(a, b): return pos.distance_to(a["pos"]) < pos.distance_to(b["pos"]))
	return out


func _criar(l: Dictionary) -> int:
	l["id"] = _proximo
	_proximo = (_proximo % 65000) + 1
	loot[l["id"]] = l
	broadcast.call(Protocol.pack_loot(l))
	return l["id"]


func remove(id: int) -> void:
	if loot.erase(id):
		broadcast.call(Protocol.pack_u16_msg(Protocol.S_LOOT_GONE, id))


## Mensagens para um jogador que acabou de entrar (estado completo).
func full_state() -> Array[PackedByteArray]:
	var out: Array[PackedByteArray] = []
	for l in loot.values():
		out.append(Protocol.pack_loot(l))
	for i in chests.size():
		if chests[i]["open"]:
			out.append(Protocol.pack_u16_msg(Protocol.S_CHEST, i, 1))
	return out


func nearest_loot(pos: Vector3) -> int:
	var melhor := -1
	var dist := PEGAR_DIST
	for l in loot.values():
		if is_reserve(l):
			continue
		var d := pos.distance_to(l["pos"])
		if d < dist:
			dist = d
			melhor = l["id"]
	return melhor


func nearest_chest(pos: Vector3) -> int:
	for i in chests.size():
		if not chests[i]["open"] and pos.distance_to(chests[i]["pos"]) < BAU_DIST:
			return i
	return -1


## Pega um item do chão para o inventário. Nunca perde item: o que não coube fica
## no chão (a mesma entrada, com a quantidade atualizada) e o item trocado (só com
## `troca` explícita) cai em `pos_troca`. Retorna Inventory.Err.
func pick_up(id: int, inv: Inventory, pos: Vector3, troca := -1, pos_troca := Vector3.INF) -> int:
	var l: Dictionary = loot.get(id, {})
	if l.is_empty():
		return Inventory.Err.GONE
	if is_reserve(l):
		return Inventory.Err.INVALID
	var item := ItemDB.id_of(l["item"])
	var r := inv.add_item(item, l["rarity"], l["count"], l["mag"], troca)
	if r["taken"] <= 0:
		return r["error"]
	if r["taken"] < l["count"]:
		l["count"] -= r["taken"]
		broadcast.call(Protocol.pack_loot(l))
	else:
		remove(id)
	var trocado: Inventory.Slot = r["dropped"]
	if trocado:
		var onde: Vector3 = pos_troca if pos_troca != Vector3.INF else pos + Vector3(0, 0.02, 0)
		spawn_item(trocado.item, trocado.rarity, maxi(1, trocado.count), trocado.mag, onde)
	return Inventory.Err.OK


## Coleta munição (e materiais) automaticamente ao passar perto. Retorna true se
## mudou o inventário. Quem largou o item só recoleta depois de "ate".
func auto_ammo(inv: Inventory, pos: Vector3, jogador := 0, tick := 0) -> bool:
	var mudou := false
	for l in loot.values().duplicate():
		if not is_reserve(l) or pos.distance_to(l["pos"]) > MUNICAO_AUTO_DIST:
			continue
		if jogador != 0 and l.get("dono", 0) == jogador and tick < int(l.get("ate", 0)):
			continue
		var municao: bool = l["ammo"] != 0
		var tipo: String = ItemDB.ammo_types()[l["ammo"] - 1] if municao else ItemDB.material_types()[l["mat"] - 1]
		var coube := inv.add_ammo(tipo, l["count"]) if municao else inv.add_material(tipo, l["count"])
		if coube > 0:
			mudou = true
			if coube < l["count"]:
				l["count"] -= coube
				broadcast.call(Protocol.pack_loot(l))
			else:
				remove(l["id"])
	return mudou


func open_chest(i: int) -> void:
	var c: Dictionary = chests[i]
	if c["open"]:
		return
	c["open"] = true
	broadcast.call(Protocol.pack_u16_msg(Protocol.S_CHEST, i, 1))
	var frente := Basis(Vector3.UP, deg_to_rad(c["rot"])) * Vector3(0, 0, 1.2)
	var lado := frente.cross(Vector3.UP).normalized() * 0.8
	var base: Vector3 = c["pos"] + frente
	var arma := ItemDB.roll_weapon(rng)
	spawn_item(arma, ItemDB.roll_rarity(rng, true), 1, -1, base)
	spawn_ammo(ItemDB.weapon(arma)["municao"], base + lado)
	var cons := ItemDB.roll_consumable(rng)
	spawn_item(cons, 0, int(ItemDB.consumable(cons)["quantidade"]), -1, base - lado)
	spawn_ammo(ItemDB.ammo_types()[rng.randi() % ItemDB.ammo_types().size()], base + lado * 2.0)


## Treino: baús fecham e reabastecem depois de um tempo.
func update(tick: int) -> void:
	if not reabastecer:
		return
	for i in chests.size():
		var c: Dictionary = chests[i]
		if c["open"]:
			if c["reopen_tick"] == 0:
				c["reopen_tick"] = tick + REABASTECER_BAU_TICKS
			elif tick >= c["reopen_tick"]:
				c["open"] = false
				c["reopen_tick"] = 0
				broadcast.call(Protocol.pack_u16_msg(Protocol.S_CHEST, i, 0))


## Espalha o inventário de um jogador eliminado (a picareta não cai: é permanente).
func drop_inventory(inv: Inventory, pos: Vector3) -> void:
	var i := 0
	for s: Inventory.Slot in inv.drop_all():
		var ang := i * TAU / 6.0
		spawn_item(s.item, s.rarity, maxi(1, s.count), s.mag, pos + Vector3(cos(ang), 0.05, sin(ang)) * 1.2)
		i += 1
	for tipo in inv.ammo:
		if inv.ammo[tipo] > 0:
			var ang := i * TAU / 6.0
			spawn_ammo(tipo, pos + Vector3(cos(ang), 0.05, sin(ang)) * 1.6, inv.ammo[tipo])
			inv.ammo[tipo] = 0
			i += 1
	for tipo in inv.materials:
		if inv.materials[tipo] > 0:
			var ang := i * TAU / 6.0
			spawn_material(tipo, pos + Vector3(cos(ang), 0.05, sin(ang)) * 1.8, inv.materials[tipo])
			inv.materials[tipo] = 0
			i += 1
