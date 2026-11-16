class_name Protocol
extends RefCounted
## Protocolo binário da partida (ENet). Little-endian, um byte de tipo no início.
## Cliente envia ENTRADAS (não posições); servidor envia SNAPSHOTS do estado.
## Ver ARCHITECTURE §4.

const GAME_PROTOCOL := 5
const DEFAULT_PORT := 24800
const TICK_RATE := 30            # simulação (Hz)
const SNAPSHOT_EVERY := 2        # snapshot a cada N ticks (15 Hz)
const MAX_PLAYERS := 16
const MAX_NAME := 16

# canais ENet
const CH_RELIABLE := 0
const CH_INPUT := 1
const CH_SNAPSHOT := 2

# cliente -> servidor
const C_HELLO := 1
const C_INPUT := 2
const C_INV := 3             # operação de inventário (trocar, dividir, largar, pegar); o servidor valida
# servidor -> cliente
const S_WELCOME := 10
const S_REJECT := 11
const S_SNAPSHOT := 12
const S_PLAYER_INFO := 13
const S_PLAYER_LEFT := 14
const S_STATUS := 15         # só para o dono: vida, escudo, inventário, ação em andamento
const S_SHOT := 16           # para os outros: traçantes de um disparo
const S_HIT := 17            # para quem atirou: acerto confirmado (marcador/dano)
const S_DAMAGED := 18        # para a vítima: levou dano (indicador de direção)
const S_ELIM := 19           # para todos: eliminação
const S_LOOT := 20           # para todos: item no chão apareceu/mudou
const S_LOOT_GONE := 21      # para todos: item no chão sumiu
const S_CHEST := 22          # para todos: baú aberto/fechado
const S_INV_RESULT := 23     # para o dono: resultado de uma operação de inventário (Inventory.Err)
const S_MELEE := 24          # para todos: impacto de um golpe de picareta (efeito por material)
const S_MATCH := 25          # para todos: estado da partida BR (espera, contagem, jogo, fim), vivos, vencedor
const S_STORM := 26          # para todos: Tormenta (fase, círculos de/para, tempos, dano)
const S_RESULT := 27         # para um jogador: colocação, eliminações e tempo vivo (ao ser eliminado ou vencer)

# estados da partida (S_MATCH)
const MATCH_TREINO := 0
const MATCH_ESPERA := 1
const MATCH_CONTAGEM := 2
const MATCH_JOGO := 3
const MATCH_FIM := 4

# operações de inventário (C_INV)
const OP_SWAP := 1           # a, b: espaços 0..4
const OP_SPLIT := 2          # a: espaço, n: quantidade separada
const OP_DROP := 3           # a: espaço (255 = picareta: recusado), n: quantidade
const OP_DROP_AMMO := 4      # a: tipo de munição (índice), n
const OP_PICKUP := 5         # loot: id no chão, b: espaço a trocar (255 = nenhum)
const OP_DROP_MATERIAL := 6  # a: tipo de material (índice), n
const SEM_ESPACO := 255      # a/b "nenhum" (ou picareta)

## InputCmd.slot: 0 = manter, 1..5 = espaços, 6 = picareta
const SLOT_PICKAXE := 6
## status["selected"] quando a picareta está na mão
const SELECTED_PICKAXE := 255

# botões
const BTN_JUMP := 1
const BTN_SPRINT := 2
const BTN_CROUCH := 4
const BTN_FIRE := 8
const BTN_AIM := 16
const BTN_RELOAD := 32
const BTN_INTERACT := 64
const BTN_ALL := 127

# flags de estado no snapshot
const F_ON_FLOOR := 1
const F_CROUCHED := 2
const F_SPRINTING := 4
const F_DEAD := 8
const F_DUMMY := 16
const F_AIMING := 32

# ação em andamento (EntityState.action): anima o personagem para todos
const ACT_NONE := 0
const ACT_RELOAD := 1
const ACT_USE := 2
const ACT_CHEST := 3
const ACT_SWING := 4         # golpe de picareta (progress = fase do golpe)
const ACT_SWING_B := 5       # golpe seguinte da sequência (alterna o lado)

const INPUT_REDUNDANCY := 3      # cada pacote repete as últimas N entradas (perda de pacote)


## Desliga o "throttle" do ENet, que descarta pacotes não confiáveis quando estima
## congestionamento. Entradas e snapshots são pequenos e já têm redundância/correção;
## descartá-los causava "buracos" de quase 1 s (medido no teste de fumaça).
static func configure_peer(p: ENetPacketPeer) -> void:
	if p:
		p.throttle_configure(5000, ENetPacketPeer.PACKET_THROTTLE_SCALE, 0)


class InputCmd:
	var seq := 0
	var move := Vector2.ZERO     # x = direita, y = frente; comprimento <= 1
	var yaw := 0.0               # radianos
	var pitch := 0.0             # radianos
	var buttons := 0
	var slot := 0                # 0 = manter; 1..5 = selecionar espaço; 6 = picareta
	var view_tick := 0           # tick dos outros jogadores que o cliente via (compensação de latência)

	func has(b: int) -> bool:
		return buttons & b != 0


class EntityState:
	var id := 0
	var position := Vector3.ZERO
	var velocity := Vector3.ZERO
	var yaw := 0.0
	var flags := 0
	var weapon := 0              # índice ItemDB do item na mão (arma ou consumível; 0 = nenhum)
	var pitch := 0.0             # inclinação da mira (rad)
	var action := 0              # ACT_*
	var progress := 0.0          # 0..1 da ação


static func _buf() -> StreamPeerBuffer:
	var b := StreamPeerBuffer.new()
	b.big_endian = false
	return b


static func _reader(data: PackedByteArray) -> StreamPeerBuffer:
	var b := _buf()
	b.data_array = data
	return b


static func msg_type(data: PackedByteArray) -> int:
	return data[0] if data.size() > 0 else -1


static func _yaw_u16(yaw: float) -> int:
	return int(round(fposmod(yaw, TAU) / TAU * 65535.0)) & 0xFFFF


static func _u16_yaw(v: int) -> float:
	return v / 65535.0 * TAU


# ---------- cliente -> servidor ----------

static func pack_hello(name: String) -> PackedByteArray:
	var b := _buf()
	b.put_u8(C_HELLO)
	b.put_u16(GAME_PROTOCOL)
	b.put_utf8_string(name.substr(0, MAX_NAME))
	return b.data_array


## Retorna {"protocol": int, "name": String} ou {} se inválido.
static func unpack_hello(data: PackedByteArray) -> Dictionary:
	if data.size() < 7 or data[0] != C_HELLO:
		return {}
	var b := _reader(data)
	b.seek(1)
	var proto := b.get_u16()
	var tam := b.get_u32()
	if tam > 64 or b.get_position() + tam > data.size():
		return {}
	b.seek(3)
	return {"protocol": proto, "name": b.get_utf8_string()}


static func pack_inputs(cmds: Array) -> PackedByteArray:
	var b := _buf()
	b.put_u8(C_INPUT)
	b.put_u8(cmds.size())
	for c: InputCmd in cmds:
		b.put_u32(c.seq)
		b.put_8(clampi(roundi(c.move.x * 127.0), -127, 127))
		b.put_8(clampi(roundi(c.move.y * 127.0), -127, 127))
		b.put_u16(_yaw_u16(c.yaw))
		b.put_16(clampi(roundi(rad_to_deg(c.pitch) * 100.0), -9000, 9000))
		b.put_u8(c.buttons & 0xFF)
		b.put_u8(clampi(c.slot, 0, SLOT_PICKAXE))
		b.put_u32(c.view_tick)
	return b.data_array


const INPUT_SIZE := 16  # bytes por entrada


## Retorna as entradas ou [] se o pacote for inválido. Valores são saneados.
static func unpack_inputs(data: PackedByteArray) -> Array:
	if data.size() < 2 or data[0] != C_INPUT:
		return []
	var n: int = data[1]
	if n == 0 or n > 8 or data.size() != 2 + n * INPUT_SIZE:
		return []
	var b := _reader(data)
	b.seek(2)
	var out: Array = []
	for i in n:
		var c := InputCmd.new()
		c.seq = b.get_u32()
		var mx := b.get_8() / 127.0
		var my := b.get_8() / 127.0
		c.move = Vector2(mx, my).limit_length(1.0)
		c.yaw = _u16_yaw(b.get_u16())
		c.pitch = deg_to_rad(clampf(b.get_16() / 100.0, -89.0, 89.0))
		c.buttons = b.get_u8() & BTN_ALL
		var slot := b.get_u8()
		c.slot = slot if slot <= SLOT_PICKAXE else 0
		c.view_tick = b.get_u32()
		out.append(c)
	return out


# ---------- servidor -> cliente ----------

static func pack_welcome(my_id: int, server_tick: int, map_name: String) -> PackedByteArray:
	var b := _buf()
	b.put_u8(S_WELCOME)
	b.put_u16(my_id)
	b.put_u16(TICK_RATE)
	b.put_u32(server_tick)
	b.put_utf8_string(map_name)
	return b.data_array


static func unpack_welcome(data: PackedByteArray) -> Dictionary:
	if data.size() < 13 or data[0] != S_WELCOME:
		return {}
	var b := _reader(data)
	b.seek(1)
	return {"id": b.get_u16(), "tick_rate": b.get_u16(), "tick": b.get_u32(), "map": b.get_utf8_string()}


static func pack_reject(reason: String) -> PackedByteArray:
	var b := _buf()
	b.put_u8(S_REJECT)
	b.put_utf8_string(reason)
	return b.data_array


static func unpack_reject(data: PackedByteArray) -> String:
	var b := _reader(data)
	b.seek(1)
	return b.get_utf8_string() if data.size() > 5 else "recusado"


static func pack_player_info(id: int, name: String) -> PackedByteArray:
	var b := _buf()
	b.put_u8(S_PLAYER_INFO)
	b.put_u16(id)
	b.put_utf8_string(name)
	return b.data_array


static func unpack_player_info(data: PackedByteArray) -> Dictionary:
	var b := _reader(data)
	b.seek(1)
	return {"id": b.get_u16(), "name": b.get_utf8_string()}


static func pack_player_left(id: int) -> PackedByteArray:
	var b := _buf()
	b.put_u8(S_PLAYER_LEFT)
	b.put_u16(id)
	return b.data_array


static func unpack_player_left(data: PackedByteArray) -> int:
	var b := _reader(data)
	b.seek(1)
	return b.get_u16()


const ENTITY_SIZE := 2 + 12 + 12 + 2 + 1 + 1 + 1 + 1 + 1


static func pack_snapshot(tick: int, ack_seq: int, entities: Array) -> PackedByteArray:
	var b := _buf()
	b.put_u8(S_SNAPSHOT)
	b.put_u32(tick)
	b.put_u32(ack_seq)
	b.put_u16(entities.size())
	for e: EntityState in entities:
		b.put_u16(e.id)
		b.put_float(e.position.x)
		b.put_float(e.position.y)
		b.put_float(e.position.z)
		b.put_float(e.velocity.x)
		b.put_float(e.velocity.y)
		b.put_float(e.velocity.z)
		b.put_u16(_yaw_u16(e.yaw))
		b.put_u8(e.flags)
		b.put_u8(e.weapon)
		b.put_8(clampi(roundi(rad_to_deg(e.pitch) / 0.75), -120, 120))
		b.put_u8(e.action)
		b.put_u8(clampi(roundi(e.progress * 255.0), 0, 255))
	return b.data_array


## {"tick", "ack", "entities": Array[EntityState]} ou {} se inválido.
static func unpack_snapshot(data: PackedByteArray) -> Dictionary:
	if data.size() < 11 or data[0] != S_SNAPSHOT:
		return {}
	var b := _reader(data)
	b.seek(1)
	var tick := b.get_u32()
	var ack := b.get_u32()
	var n := b.get_u16()
	if data.size() != 11 + n * ENTITY_SIZE:
		return {}
	var lista: Array = []
	for i in n:
		var e := EntityState.new()
		e.id = b.get_u16()
		e.position = Vector3(b.get_float(), b.get_float(), b.get_float())
		e.velocity = Vector3(b.get_float(), b.get_float(), b.get_float())
		e.yaw = _u16_yaw(b.get_u16())
		e.flags = b.get_u8()
		e.weapon = b.get_u8()
		e.pitch = deg_to_rad(b.get_8() * 0.75)
		e.action = b.get_u8()
		e.progress = b.get_u8() / 255.0
		lista.append(e)
	return {"tick": tick, "ack": ack, "entities": lista}



# ---------- combate e loot ----------

static func _put_v3(b: StreamPeerBuffer, v: Vector3) -> void:
	b.put_float(v.x)
	b.put_float(v.y)
	b.put_float(v.z)


static func _get_v3(b: StreamPeerBuffer) -> Vector3:
	return Vector3(b.get_float(), b.get_float(), b.get_float())


## status: {"hp","shield","selected"(0..4; SELECTED_PICKAXE = picareta),"action"(0 nada,1 recarga,2 uso),
##          "action_left_ms","action_total_ms", "slots": [{"item","rarity","mag","count"} x5],
##          "ammo": [int x tipos], "materials": [int x tipos]}
static func pack_status(st: Dictionary) -> PackedByteArray:
	var b := _buf()
	b.put_u8(S_STATUS)
	b.put_u8(st["hp"])
	b.put_u8(st["shield"])
	b.put_u8(st["selected"])
	b.put_u8(st["action"])
	b.put_u16(st["action_left_ms"])
	b.put_u16(st["action_total_ms"])
	for s in st["slots"]:
		b.put_u8(s["item"])
		b.put_u8(s["rarity"])
		b.put_u16(s["mag"])
		b.put_u16(s["count"])
	b.put_u8(st["ammo"].size())
	for a in st["ammo"]:
		b.put_u16(a)
	var mats: Array = st.get("materials", [])
	b.put_u8(mats.size())
	for m in mats:
		b.put_u16(m)
	return b.data_array


static func unpack_status(data: PackedByteArray) -> Dictionary:
	if data.size() < 9 + 5 * 6 + 1 or data[0] != S_STATUS:
		return {}
	var b := _reader(data)
	b.seek(1)
	var st := {"hp": b.get_u8(), "shield": b.get_u8(), "selected": b.get_u8(), "action": b.get_u8(),
			"action_left_ms": b.get_u16(), "action_total_ms": b.get_u16(), "slots": [], "ammo": []}
	for i in 5:
		st["slots"].append({"item": b.get_u8(), "rarity": b.get_u8(), "mag": b.get_u16(), "count": b.get_u16()})
	var n := b.get_u8()
	if b.get_position() + n * 2 + 1 > data.size():
		return {}
	for i in n:
		st["ammo"].append(b.get_u16())
	st["materials"] = []
	var m := b.get_u8()
	if b.get_position() + m * 2 != data.size():
		return {}
	for i in m:
		st["materials"].append(b.get_u16())
	return st


## fins: Array de {"end": Vector3, "hit": bool}
static func pack_shot(shooter: int, origem: Vector3, fins: Array) -> PackedByteArray:
	var b := _buf()
	b.put_u8(S_SHOT)
	b.put_u16(shooter)
	_put_v3(b, origem)
	b.put_u8(fins.size())
	for f in fins:
		_put_v3(b, f["end"])
		b.put_u8(1 if f["hit"] else 0)
	return b.data_array


static func unpack_shot(data: PackedByteArray) -> Dictionary:
	var b := _reader(data)
	b.seek(1)
	var r := {"shooter": b.get_u16(), "origin": _get_v3(b), "ends": []}
	var n := b.get_u8()
	if data.size() != 16 + n * 13:
		return {}
	for i in n:
		r["ends"].append({"end": _get_v3(b), "hit": b.get_u8() == 1})
	return r


const HIT_HEAD := 1
const HIT_SHIELD := 2
const HIT_KILL := 4


static func pack_hit(alvo: int, dano: int, flags: int, pos: Vector3) -> PackedByteArray:
	var b := _buf()
	b.put_u8(S_HIT)
	b.put_u16(alvo)
	b.put_u16(dano)
	b.put_u8(flags)
	_put_v3(b, pos)
	return b.data_array


static func unpack_hit(data: PackedByteArray) -> Dictionary:
	var b := _reader(data)
	b.seek(1)
	return {"target": b.get_u16(), "damage": b.get_u16(), "flags": b.get_u8(), "pos": _get_v3(b)}


static func pack_damaged(dano: int, de: Vector3) -> PackedByteArray:
	var b := _buf()
	b.put_u8(S_DAMAGED)
	b.put_u16(dano)
	_put_v3(b, de)
	return b.data_array


static func unpack_damaged(data: PackedByteArray) -> Dictionary:
	var b := _reader(data)
	b.seek(1)
	return {"damage": b.get_u16(), "from": _get_v3(b)}


static func pack_elim(quem: int, vitima: int, arma: int) -> PackedByteArray:
	var b := _buf()
	b.put_u8(S_ELIM)
	b.put_u16(quem)
	b.put_u16(vitima)
	b.put_u8(arma)
	return b.data_array


static func unpack_elim(data: PackedByteArray) -> Dictionary:
	var b := _reader(data)
	b.seek(1)
	return {"killer": b.get_u16(), "victim": b.get_u16(), "weapon": b.get_u8()}


## loot: {"id","item"(índice ItemDB, 0 = reserva),"rarity","count","ammo"(0 = não é munição; 1.. = tipo),
##        "mat"(0 = não é material; 1.. = tipo),"pos"}
static func pack_loot(l: Dictionary) -> PackedByteArray:
	var b := _buf()
	b.put_u8(S_LOOT)
	b.put_u16(l["id"])
	b.put_u8(l["item"])
	b.put_u8(l["rarity"])
	b.put_u16(l["count"])
	b.put_u8(l["ammo"])
	b.put_u8(l.get("mat", 0))
	_put_v3(b, l["pos"])
	return b.data_array


static func unpack_loot(data: PackedByteArray) -> Dictionary:
	if data.size() != 21:
		return {}
	var b := _reader(data)
	b.seek(1)
	return {"id": b.get_u16(), "item": b.get_u8(), "rarity": b.get_u8(), "count": b.get_u16(), "ammo": b.get_u8(),
			"mat": b.get_u8(), "pos": _get_v3(b)}


static func pack_u16_msg(tipo: int, v: int, extra := -1) -> PackedByteArray:
	var b := _buf()
	b.put_u8(tipo)
	b.put_u16(v)
	if extra >= 0:
		b.put_u8(extra)
	return b.data_array


static func unpack_u16_msg(data: PackedByteArray) -> Array:
	var b := _reader(data)
	b.seek(1)
	var v := b.get_u16()
	return [v, b.get_u8() if data.size() > 3 else -1]


# ---------- inventário ----------

## {"req","op","a","b","n","loot"}
static func pack_inv(op: Dictionary) -> PackedByteArray:
	var b := _buf()
	b.put_u8(C_INV)
	b.put_u16(int(op.get("req", 0)) & 0xFFFF)
	b.put_u8(op["op"])
	b.put_u8(clampi(int(op.get("a", SEM_ESPACO)), 0, 255))
	b.put_u8(clampi(int(op.get("b", SEM_ESPACO)), 0, 255))
	b.put_u16(clampi(int(op.get("n", 0)), 0, 65535))
	b.put_u16(clampi(int(op.get("loot", 0)), 0, 65535))
	return b.data_array


const INV_SIZE := 10


static func unpack_inv(data: PackedByteArray) -> Dictionary:
	if data.size() != INV_SIZE or data[0] != C_INV:
		return {}
	var b := _reader(data)
	b.seek(1)
	var r := {"req": b.get_u16(), "op": b.get_u8(), "a": b.get_u8(), "b": b.get_u8(), "n": b.get_u16(), "loot": b.get_u16()}
	if r["op"] < OP_SWAP or r["op"] > OP_DROP_MATERIAL:
		return {}
	return r


static func pack_inv_result(req: int, op: int, code: int) -> PackedByteArray:
	var b := _buf()
	b.put_u8(S_INV_RESULT)
	b.put_u16(req & 0xFFFF)
	b.put_u8(op)
	b.put_u8(code)
	return b.data_array


static func unpack_inv_result(data: PackedByteArray) -> Dictionary:
	if data.size() != 5:
		return {}
	var b := _reader(data)
	b.seek(1)
	return {"req": b.get_u16(), "op": b.get_u8(), "code": b.get_u8()}


# ---------- golpe de picareta ----------

const MELEE_PLAYER := 1      # flags: acertou um jogador/boneco


## {"swinger","pos","normal","material","flags","target"}
static func pack_melee(m: Dictionary) -> PackedByteArray:
	var b := _buf()
	b.put_u8(S_MELEE)
	b.put_u16(m["swinger"])
	_put_v3(b, m["pos"])
	var nrm: Vector3 = m["normal"]
	b.put_8(clampi(roundi(nrm.x * 127.0), -127, 127))
	b.put_8(clampi(roundi(nrm.y * 127.0), -127, 127))
	b.put_8(clampi(roundi(nrm.z * 127.0), -127, 127))
	b.put_u8(m["material"])
	b.put_u8(m.get("flags", 0))
	b.put_u16(m.get("target", 0))
	return b.data_array


static func unpack_melee(data: PackedByteArray) -> Dictionary:
	if data.size() != 22:
		return {}
	var b := _reader(data)
	b.seek(1)
	var r := {"swinger": b.get_u16(), "pos": _get_v3(b)}
	r["normal"] = Vector3(b.get_8(), b.get_8(), b.get_8()) / 127.0
	r["material"] = b.get_u8()
	r["flags"] = b.get_u8()
	r["target"] = b.get_u16()
	return r


# ---------- partida Battle Royale ----------

## {"estado","vivos","total","resta_ms","vencedor","espectadores"}
static func pack_match(m: Dictionary) -> PackedByteArray:
	var b := _buf()
	b.put_u8(S_MATCH)
	b.put_u8(m["estado"])
	b.put_u8(clampi(m["vivos"], 0, 255))
	b.put_u8(clampi(m["total"], 0, 255))
	b.put_u32(clampi(m["resta_ms"], 0, 0x7FFFFFFF))
	b.put_u16(m.get("vencedor", 0))
	return b.data_array


static func unpack_match(data: PackedByteArray) -> Dictionary:
	if data.size() != 10:
		return {}
	var b := _reader(data)
	b.seek(1)
	return {"estado": b.get_u8(), "vivos": b.get_u8(), "total": b.get_u8(), "resta_ms": b.get_u32(), "vencedor": b.get_u16()}


## Tormenta.to_dict()
static func pack_storm(t: Dictionary) -> PackedByteArray:
	var b := _buf()
	b.put_u8(S_STORM)
	b.put_u8(t["fase"])
	b.put_u8(t["fases"])
	b.put_u8((1 if t["fechando"] else 0) | (2 if t["terminou"] else 0))
	b.put_float(t["c_de"].x)
	b.put_float(t["c_de"].y)
	b.put_float(t["r_de"])
	b.put_float(t["c_para"].x)
	b.put_float(t["c_para"].y)
	b.put_float(t["r_para"])
	b.put_u32(t["total_ms"])
	b.put_u32(t["resta_ms"])
	b.put_u8(clampi(t["dano"], 0, 255))
	return b.data_array


static func unpack_storm(data: PackedByteArray) -> Dictionary:
	if data.size() != 37:
		return {}
	var b := _reader(data)
	b.seek(1)
	var r := {"fase": b.get_u8(), "fases": b.get_u8()}
	var f := b.get_u8()
	r["fechando"] = f & 1 != 0
	r["terminou"] = f & 2 != 0
	r["c_de"] = Vector2(b.get_float(), b.get_float())
	r["r_de"] = b.get_float()
	r["c_para"] = Vector2(b.get_float(), b.get_float())
	r["r_para"] = b.get_float()
	r["total_ms"] = b.get_u32()
	r["resta_ms"] = b.get_u32()
	r["dano"] = b.get_u8()
	return r


## {"colocacao","total","eliminacoes","tempo_s","vencedor"}
static func pack_result(r: Dictionary) -> PackedByteArray:
	var b := _buf()
	b.put_u8(S_RESULT)
	b.put_u8(r["colocacao"])
	b.put_u8(r["total"])
	b.put_u8(clampi(r["eliminacoes"], 0, 255))
	b.put_u16(clampi(r["tempo_s"], 0, 65535))
	b.put_u16(r.get("vencedor", 0))
	return b.data_array


static func unpack_result(data: PackedByteArray) -> Dictionary:
	if data.size() != 8:
		return {}
	var b := _reader(data)
	b.seek(1)
	return {"colocacao": b.get_u8(), "total": b.get_u8(), "eliminacoes": b.get_u8(), "tempo_s": b.get_u16(), "vencedor": b.get_u16()}
