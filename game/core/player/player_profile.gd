class_name PlayerProfile
extends RefCounted
## Perfil do jogador como o cliente o enxerga. É só um CACHE de leitura:
## a fonte da verdade é o meta-servidor (ARCHITECTURE §7). O cliente nunca
## altera moeda, XP ou itens por conta própria.

const CACHE_PATH := "user://cache/perfil.json"
const COSMETIC_SLOTS := ["traje", "ferramenta", "mochila", "planador", "trilha", "acessorio"]
const EMOTE_SLOTS := 6

var player_id := ""
var display_name := ""
var level := 1
var xp := 0
var currency := 0
var equipped := {}            # slot -> cosmetic_id
var emotes: Array[String] = []
var owned: Array[String] = []
var season_id := ""
var pass_level := 0
var pass_xp := 0
var updated_at := 0           # unix (do servidor)


static func from_dict(d: Variant) -> PlayerProfile:
	if not (d is Dictionary):
		return null
	var id: Variant = d.get("player_id")
	var nome: Variant = d.get("display_name")
	if not (id is String) or id.is_empty() or not (nome is String):
		return null
	var p := PlayerProfile.new()
	p.player_id = id
	p.display_name = nome.substr(0, 24)
	p.level = maxi(1, _int(d.get("level"), 1))
	p.xp = maxi(0, _int(d.get("xp"), 0))
	p.currency = maxi(0, _int(d.get("currency"), 0))
	p.season_id = str(d.get("season_id", ""))
	p.pass_level = maxi(0, _int(d.get("pass_level"), 0))
	p.pass_xp = maxi(0, _int(d.get("pass_xp"), 0))
	p.updated_at = maxi(0, _int(d.get("updated_at"), 0))
	var eq: Variant = d.get("equipped", {})
	if eq is Dictionary:
		for slot in eq:
			if slot in COSMETIC_SLOTS and eq[slot] is String:
				p.equipped[slot] = eq[slot]
	p.owned = _strings(d.get("owned", []))
	p.emotes = _strings(d.get("emotes", []))
	p.emotes.resize(mini(p.emotes.size(), EMOTE_SLOTS))
	return p


func to_dict() -> Dictionary:
	return {
		"player_id": player_id, "display_name": display_name, "level": level, "xp": xp,
		"currency": currency, "equipped": equipped.duplicate(), "emotes": emotes.duplicate(),
		"owned": owned.duplicate(), "season_id": season_id, "pass_level": pass_level,
		"pass_xp": pass_xp, "updated_at": updated_at,
	}


func owns(cosmetic_id: String) -> bool:
	return cosmetic_id in owned


func save_cache(path := CACHE_PATH) -> Error:
	return SafeFile.write_json(path, to_dict())


static func load_cache(path := CACHE_PATH) -> PlayerProfile:
	return from_dict(SafeFile.read_json(path))


static func _int(v: Variant, padrao: int) -> int:
	return int(v) if (v is int or v is float) else padrao


static func _strings(v: Variant) -> Array[String]:
	var out: Array[String] = []
	if v is Array:
		for x in v:
			if x is String and not x.is_empty() and not (x in out):
				out.append(x)
	return out
