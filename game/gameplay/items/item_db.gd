class_name ItemDB
extends RefCounted
## Definições de itens (data/itens.json), carregadas uma vez. Cada item tem um
## índice pequeno (u8) usado na rede: 0 = vazio, depois armas, consumíveis e
## ferramentas em ordem. Regras de inventário (pilha, coleta, descarte) vêm de
## "regras" por categoria e podem ser sobrescritas no próprio item.

const ARQUIVO := "res://data/itens.json"

static var _dados := {}
static var _ids: Array[String] = [""]      # índice -> id
static var _indices := {}                  # id -> índice


static func _carregar() -> void:
	if not _dados.is_empty():
		return
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(ARQUIVO))
	if not (d is Dictionary):
		push_error("itens.json inválido")
		return
	_dados = d
	for id in _dados["armas"]:
		_ids.append(id)
	for id in _dados["consumiveis"]:
		_ids.append(id)
	for id in _dados["ferramentas"]:
		_ids.append(id)
	for i in _ids.size():
		_indices[_ids[i]] = i


static func data() -> Dictionary:
	_carregar()
	return _dados


static func index_of(id: String) -> int:
	_carregar()
	return _indices.get(id, 0)


static func id_of(index: int) -> String:
	_carregar()
	return _ids[index] if index >= 0 and index < _ids.size() else ""


static func is_weapon(id: String) -> bool:
	return data()["armas"].has(id)


static func is_consumable(id: String) -> bool:
	return data()["consumiveis"].has(id)


static func is_tool_item(id: String) -> bool:
	return data()["ferramentas"].has(id)


static func tool_def(id: String) -> Dictionary:
	return data()["ferramentas"].get(id, {})


## Item que ocupa um dos 5 espaços (arma ou consumível).
static func is_slot_item(id: String) -> bool:
	return is_weapon(id) or is_consumable(id)


static func category(id: String) -> String:
	if is_weapon(id):
		return "armas"
	if is_consumable(id):
		return "consumiveis"
	if is_tool_item(id):
		return "ferramentas"
	if data()["municao"].has(id):
		return "municao"
	if data()["materiais"].has(id):
		return "materiais"
	return ""


## Regra de inventário do item: o próprio item sobrescreve a da categoria.
static func rule(id: String, campo: String, padrao: Variant = null) -> Variant:
	var d := def(id)
	if d.has(campo):
		return d[campo]
	return data()["regras"].get(category(id), {}).get(campo, padrao)


## Máximo por pilha (armas/ferramentas 1; consumíveis "pilha"; munição/materiais "max").
static func stack_limit(id: String) -> int:
	match category(id):
		"municao", "materiais":
			return int(def(id).get("max", 0))
		"consumiveis":
			return int(consumable(id).get("pilha", 1))
	return int(rule(id, "pilha", 1))


static func can_drop(id: String) -> bool:
	return bool(rule(id, "descartavel", false))


static func material_types() -> Array:
	return data()["materiais"].keys().filter(func(k): return not k.begins_with("_"))


static func material(tipo: String) -> Dictionary:
	return data()["materiais"].get(tipo, {})


static func weapon(id: String) -> Dictionary:
	return data()["armas"].get(id, {})


static func consumable(id: String) -> Dictionary:
	return data()["consumiveis"].get(id, {})


static func def(id: String) -> Dictionary:
	for cat in ["armas", "consumiveis", "ferramentas", "municao", "materiais"]:
		if data()[cat].has(id):
			return data()[cat][id]
	return {}


static func rarities() -> Array:
	return data()["raridades"]


static func rarity(i: int) -> Dictionary:
	var r := rarities()
	return r[clampi(i, 0, r.size() - 1)]


static func rarity_color(i: int) -> Color:
	return Color(rarity(i)["cor"])


static func ammo_types() -> Array:
	return data()["municao"].keys().filter(func(k): return not k.begins_with("_"))


static func ammo(tipo: String) -> Dictionary:
	return data()["municao"].get(tipo, {})


## Dano por projétil considerando a raridade.
static func damage(id: String, raridade: int) -> float:
	return float(weapon(id)["dano"]) * float(rarity(raridade)["dano"])


static func reload_time(id: String, raridade: int) -> float:
	return float(weapon(id)["recarga_s"]) * float(rarity(raridade)["recarga"])


## Nome completo e consistente em todo o jogo. Armas: "<tipo> <nome>"
## (ex.: "Rifle de Assalto Rajada"); com raridade: "Rifle de Assalto Rajada (Raro)".
static func display_name(id: String, raridade := -1) -> String:
	if not is_weapon(id):
		return def(id).get("nome", id)
	var w := weapon(id)
	var n := "%s %s" % [w["tipo"], w["nome"]]
	return n if raridade < 0 else "%s (%s)" % [n, rarity(raridade)["nome"]]


## Nome curto (espaço apertado do inventário): só o nome próprio.
static func short_name(id: String) -> String:
	return def(id).get("nome", id)


## Raridades sorteáveis (as com peso > 0).
static func rarity_count_droppable() -> int:
	return rarities().filter(func(r): return float(r["peso_bau"]) > 0.0).size()


# ---------- sorteios (servidor) ----------

static func _escolher_peso(rng: RandomNumberGenerator, opcoes: Array, campo: String) -> int:
	var total := 0.0
	for o in opcoes:
		total += float(o[campo])
	var x := rng.randf() * total
	var ultimo_valido := 0
	for i in opcoes.size():
		var peso := float(opcoes[i][campo])
		if peso <= 0.0:
			continue          # peso zero nunca é sorteado (ex.: Mítico)
		ultimo_valido = i
		x -= peso
		if x <= 0.0:
			return i
	return ultimo_valido


static func roll_rarity(rng: RandomNumberGenerator, de_bau: bool) -> int:
	return _escolher_peso(rng, rarities(), "peso_bau" if de_bau else "peso_chao")


static func roll_weapon(rng: RandomNumberGenerator) -> String:
	var ids: Array = data()["armas"].keys()
	return ids[_escolher_peso(rng, ids.map(func(i): return data()["armas"][i]), "peso")]


static func roll_consumable(rng: RandomNumberGenerator) -> String:
	var ids: Array = data()["consumiveis"].keys()
	return ids[_escolher_peso(rng, ids.map(func(i): return data()["consumiveis"][i]), "peso")]
