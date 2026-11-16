class_name Inventory
extends RefCounted
## Inventário de partida de um jogador (autoridade: servidor).
## 5 espaços (armas ou pilhas de consumíveis) + munição por tipo, fora dos espaços.

const SLOTS := 5

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
var selected := 0


func _init() -> void:
	for i in SLOTS:
		slots.append(Slot.new())
	for t in ItemDB.ammo_types():
		ammo[t] = 0


func current() -> Slot:
	return slots[selected]


func select(i: int) -> bool:
	if i < 0 or i >= SLOTS or i == selected:
		return false
	selected = i
	return true


func first_free() -> int:
	for i in SLOTS:
		if slots[i].is_empty():
			return i
	return -1


func add_ammo(tipo: String, n: int) -> int:
	## Retorna quanto coube.
	if not ammo.has(tipo) or n <= 0:
		return 0
	var cabe := mini(n, int(ItemDB.ammo(tipo)["max"]) - int(ammo[tipo]))
	ammo[tipo] += cabe
	return cabe


## Tenta guardar um item. Consumíveis completam pilhas existentes primeiro.
## Retorna {"taken": int (quanto entrou), "dropped": Slot ou null (item trocado que deve ir ao chão)}.
## Se não houver espaço livre, troca com o espaço selecionado.
func add_item(item: String, rarity: int, count := 1, mag := -1) -> Dictionary:
	var restante := count
	if ItemDB.is_consumable(item):
		var pilha := int(ItemDB.consumable(item)["pilha"])
		for s in slots:
			if s.item == item and s.count < pilha and restante > 0:
				var n := mini(pilha - s.count, restante)
				s.count += n
				restante -= n
		if restante == 0:
			return {"taken": count, "dropped": null}
	var livre := first_free()
	var trocado: Slot = null
	if livre == -1:
		livre = selected
		trocado = slots[livre].copy()
	var novo := Slot.new()
	novo.item = item
	novo.rarity = rarity
	if ItemDB.is_weapon(item):
		novo.mag = mag if mag >= 0 else int(ItemDB.weapon(item)["pente"])
		restante = 0
	else:
		var pilha := int(ItemDB.consumable(item)["pilha"])
		novo.count = mini(restante, pilha)
		restante -= novo.count
	slots[livre] = novo
	return {"taken": count - restante, "dropped": trocado}


func remove_slot(i: int) -> Slot:
	var s := slots[i]
	slots[i] = Slot.new()
	return s


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


## Tudo que deve cair no chão ao ser eliminado.
func drop_all() -> Array:
	var out := []
	for i in SLOTS:
		if not slots[i].is_empty():
			out.append(remove_slot(i))
	return out
