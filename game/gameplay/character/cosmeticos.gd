class_name Cosmeticos
extends RefCounted
## Tabela de visuais dos cosméticos (game/data/cosmeticos.json). Só aparência:
## nenhum cosmético muda hitbox, velocidade ou visibilidade.

static var _cfg := {}


static func config() -> Dictionary:
	if _cfg.is_empty():
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/cosmeticos.json"))
		_cfg = d if d is Dictionary else {"traje_padrao": "traje_recruta", "trajes": {"traje_recruta": "res://assets/personagens/recruta_base_01.glb"}}
	return _cfg


static func default_outfit() -> String:
	return config()["traje_padrao"]


## Cena do traje; id desconhecido (ou vazio) usa o padrão.
static func outfit_scene(id: String) -> String:
	var t: Dictionary = config()["trajes"]
	return t.get(id, t[default_outfit()])


static func valid_id(id: String) -> bool:
	if id.is_empty() or id.length() > 32:
		return false
	for ch in id:
		if not (ch >= "a" and ch <= "z") and not (ch >= "0" and ch <= "9") and ch != "_":
			return false
	return true


static func bot_outfits() -> Array:
	return config().get("trajes_dos_bots", [default_outfit()])
