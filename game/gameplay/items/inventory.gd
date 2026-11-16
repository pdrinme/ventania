class_name Inventory
extends RefCounted
## Inventário de partida de um jogador (autoridade: servidor).
##  - Picareta: equipamento PERMANENTE, fora dos espaços (selected = PICKAXE). Não
##    pode ser largada, trocada nem perdida; nenhuma operação a aceita.
##  - 5 espaços: armas (1 por espaço) ou pilhas de consumíveis (limite "pilha").
##  - Reservas fora dos espaços: munição por tipo e materiais (limite "max").
## Toda operação devolve um código (Err) e nunca perde nem duplica itens: o que sai
## do inventário é devolvido ao chamador (que o coloca no chão).

const SLOTS := 5
const PICKAXE := -1
const PICKAXE_ID := "picareta"

enum Err { OK, FULL, INVALID, NOT_DROPPABLE, NO_SPACE, EMPTY, TOO_FAR, GONE, BUSY }

## Mensagem ao jogador para cada código.
const MENSAGENS := {
	Err.OK: "",
	Err.FULL: "Inventário cheio: selecione o espaço que quer trocar.",
	Err.INVALID: "Operação inválida.",
	Err.NOT_DROPPABLE: "A picareta é permanente e não pode ser largada.",
	Err.NO_SPACE: "Sem espaço livre para dividir.",
	Err.EMPTY: "Esse espaço está vazio.",
	Err.TOO_FAR: "Longe demais para pegar.",
	Err.GONE: "O item não está mais aí.",
	Err.BUSY: "Aguarde: muitas ações seguidas.",
}

class Slot:
	var item := ""        # id em itens.json ("" = vazio)
	var rarity := 0
	var mag := 0          # armas: balas no pente
	var count := 0        # consumíveis: quantidade na pilha

	func is_empty() -> bool:
		return item.is_empty()

	func copy() -> Slot:
		var s := Slot.new()
		s.item = item
		s.rarity = rarity
		s.mag = mag
		s.count = count
		return s

var slots: Array[Slot] = []
var ammo := {}            # tipo -> quantidade
var materials := {}       # tipo -> quantidade (Etapa 5)
var selected := PICKAXE
var _picareta := Slot.new()


func _init() -> void:
	for i in SLOTS:
		slots.append(Slot.new())
	for t in ItemDB.ammo_types():
		ammo[t] = 0
	for t in ItemDB.material_types():
		materials[t] = 0
	_picareta.item = PICKAXE_ID
	_picareta.count = 1


## Item na mão. Com a picareta selecionada, devolve o "espaço" fixo da picareta.
func current() -> Slot:
	return _picareta if selected == PICKAXE else slots[selected]


func pickaxe_selected() -> bool:
	return selected == PICKAXE


static func valid_slot(i: int) -> bool:
	return i >= 0 and i < SLOTS


func select(i: int) -> bool:
	if (i != PICKAXE and not valid_slot(i)) or i == selected:
		return false
	selected = i
	return true


func first_free() -> int:
	for i in SLOTS:
		if slots[i].is_empty():
			return i
	return -1


func free_count() -> int:
	return slots.filter(func(s): return s.is_empty()).size()


func add_ammo(tipo: String, n: int) -> int:
	## Retorna quanto coube.
	if not ammo.has(tipo) or n <= 0:
		return 0
	var cabe := mini(n, ItemDB.stack_limit(tipo) - int(ammo[tipo]))
	ammo[tipo] += cabe
	return cabe


func add_material(tipo: String, n: int) -> int:
	if not materials.has(tipo) or n <= 0:
		return 0
	var cabe := mini(n, ItemDB.stack_limit(tipo) - int(materials[tipo]))
	materials[tipo] += cabe
	return cabe


## Quanto deste item ainda cabe (pilhas existentes + espaços livres), sem trocar nada.
func room_for(item: String) -> int:
	if ItemDB.is_weapon(item):
		return 1 if first_free() >= 0 else 0
	if not ItemDB.is_consumable(item):
		return 0
	var pilha := ItemDB.stack_limit(item)
	var n := free_count() * pilha
	for s in slots:
		if s.item == item:
			n += pilha - s.count
	return n


## Guarda um item. Consumíveis completam pilhas existentes e depois ocupam espaços
## livres. Sem espaço: só troca se `replace` for um espaço válido e nada coube
## (o item trocado volta em "dropped" para ir ao chão). Nunca troca em silêncio.
## Retorna {"taken": int, "dropped": Slot ou null, "error": Err, "slot": int}.
func add_item(item: String, rarity: int, count := 1, mag := -1, replace := -1) -> Dictionary:
	var out := {"taken": 0, "dropped": null, "error": Err.OK, "slot": -1}
	if not ItemDB.is_slot_item(item) or count <= 0:
		out["error"] = Err.INVALID
		return out
	var restante := count
	if ItemDB.is_consumable(item):
		var pilha := ItemDB.stack_limit(item)
		for i in SLOTS:
			var s := slots[i]
			if s.item == item and s.count < pilha and restante > 0:
				var n := mini(pilha - s.count, restante)
				s.count += n
				restante -= n
				out["slot"] = i
		while restante > 0 and first_free() >= 0:
			var livre := first_free()
			slots[livre] = _novo(item, rarity, mini(restante, pilha), mag)
			restante -= slots[livre].count
			out["slot"] = livre
		if restante < count:
			out["taken"] = count - restante
			return out
	else:
		var livre := first_free()
		if livre >= 0:
			slots[livre] = _novo(item, rarity, 1, mag)
			out["taken"] = 1
			out["slot"] = livre
			return out
	# nada coube: troca pedida explicitamente?
	if not valid_slot(replace) or slots[replace].is_empty():
		out["error"] = Err.FULL
		return out
	out["dropped"] = slots[replace].copy()
	var qtd := 1 if ItemDB.is_weapon(item) else mini(count, ItemDB.stack_limit(item))
	slots[replace] = _novo(item, rarity, qtd, mag)
	out["taken"] = qtd
	out["slot"] = replace
	return out


func _novo(item: String, rarity: int, count: int, mag: int) -> Slot:
	var s := Slot.new()
	s.item = item
	s.rarity = rarity
	if ItemDB.is_weapon(item):
		s.mag = mag if mag >= 0 else int(ItemDB.weapon(item)["pente"])
		s.count = 1
	else:
		s.count = count
	return s


func remove_slot(i: int) -> Slot:
	var s := slots[i]
	slots[i] = Slot.new()
	return s


## Troca dois espaços (mover para um vazio = trocar com o vazio). A seleção
## acompanha o item que estava na mão.
func swap(a: int, b: int) -> int:
	if not valid_slot(a) or not valid_slot(b) or a == b:
		return Err.INVALID
	if slots[a].is_empty() and slots[b].is_empty():
		return Err.EMPTY
	var t := slots[a]
	slots[a] = slots[b]
	slots[b] = t
	if selected == a:
		selected = b
	elif selected == b:
		selected = a
	return Err.OK


## Divide uma pilha: n unidades do espaço a vão para o primeiro espaço livre.
func split(a: int, n: int) -> int:
	if a == PICKAXE:
		return Err.NOT_DROPPABLE
	if not valid_slot(a):
		return Err.INVALID
	var s := slots[a]
	if s.is_empty():
		return Err.EMPTY
	if not ItemDB.is_consumable(s.item) or n < 1 or n >= s.count:
		return Err.INVALID
	var livre := first_free()
	if livre < 0:
		return Err.NO_SPACE
	slots[livre] = _novo(s.item, s.rarity, n, -1)
	s.count -= n
	return Err.OK


## Tira n unidades de um espaço para largar no mundo (arma: inteira).
## Retorna {"error": Err, "slot": Slot ou null}.
func take_from_slot(a: int, n: int) -> Dictionary:
	if a == PICKAXE:
		return {"error": Err.NOT_DROPPABLE, "slot": null}
	if not valid_slot(a):
		return {"error": Err.INVALID, "slot": null}
	var s := slots[a]
	if s.is_empty():
		return {"error": Err.EMPTY, "slot": null}
	if not ItemDB.can_drop(s.item):
		return {"error": Err.NOT_DROPPABLE, "slot": null}
	if ItemDB.is_weapon(s.item) or n >= s.count:
		return {"error": Err.OK, "slot": remove_slot(a)}
	if n < 1:
		return {"error": Err.INVALID, "slot": null}
	var parte := s.copy()
	parte.count = n
	s.count -= n
	return {"error": Err.OK, "slot": parte}


## Tira n de uma reserva (munição ou material). Retorna quanto saiu.
func take_reserve(tipo: String, n: int) -> int:
	var d: Dictionary = ammo if ammo.has(tipo) else (materials if materials.has(tipo) else {})
	if d.is_empty() or n < 1:
		return 0
	var saiu := mini(n, int(d[tipo]))
	d[tipo] -= saiu
	return saiu


## Quantas balas faltam no pente e quantas há de reserva.
func reload_amount() -> int:
	var s := current()
	if not ItemDB.is_weapon(s.item):
		return 0
	var w := ItemDB.weapon(s.item)
	return mini(int(w["pente"]) - s.mag, int(ammo[w["municao"]]))


## Conclui a recarga: move munição da reserva para o pente.
func finish_reload() -> int:
	var n := reload_amount()
	if n > 0:
		var s := current()
		s.mag += n
		ammo[ItemDB.weapon(s.item)["municao"]] -= n
	return n


## Tudo que deve cair no chão ao ser eliminado (a picareta fica com o jogador).
func drop_all() -> Array:
	var out := []
	for i in SLOTS:
		if not slots[i].is_empty():
			out.append(remove_slot(i))
	selected = PICKAXE
	return out


## Contagem total por item (testes de conservação: nada some nem duplica).
func totals() -> Dictionary:
	var t := {}
	for s in slots:
		if not s.is_empty():
			t[s.item] = int(t.get(s.item, 0)) + s.count
	for k in ammo:
		t["municao:" + k] = ammo[k]
	for k in materials:
		t["material:" + k] = materials[k]
	return t
