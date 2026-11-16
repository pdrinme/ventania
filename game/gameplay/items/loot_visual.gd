class_name LootVisual
extends Node3D
## Item no chão (cliente): modelo girando sobre um anel na cor da raridade.

var data := {}
var _modelo: Node3D
var _t := 0.0


static func model_path(l: Dictionary) -> String:
	if l["ammo"] != 0:
		return "res://assets/baus_coletaveis/municao_01.glb"
	var id := ItemDB.id_of(l["item"])
	if ItemDB.is_weapon(id):
		return "res://assets/armas/%s.glb" % ItemDB.weapon(id)["modelo"]
	return "res://assets/baus_coletaveis/%s.glb" % ItemDB.consumable(id)["modelo"]


func setup(l: Dictionary) -> void:
	data = l
	position = l["pos"]
	_t = randf() * TAU
	var anel := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = 0.42
	m.bottom_radius = 0.42
	m.height = 0.03
	m.radial_segments = 16
	m.rings = 1
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = ItemDB.rarity_color(l["rarity"]) if l["ammo"] == 0 else Color("9a9a9a")
	m.material = mat
	anel.mesh = m
	anel.position.y = 0.02
	anel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(anel)
	_modelo = (load(model_path(l)) as PackedScene).instantiate() as Node3D
	_modelo.position.y = 0.35
	add_child(_modelo)


func _process(delta: float) -> void:
	_t += delta
	if _modelo:
		_modelo.rotation.y = _t * 1.2
		_modelo.position.y = 0.35 + sin(_t * 2.0) * 0.05


func label() -> String:
	if data["ammo"] != 0:
		return ItemDB.ammo(ItemDB.ammo_types()[data["ammo"] - 1])["nome"]
	var id := ItemDB.id_of(data["item"])
	var n := ItemDB.display_name(id, data["rarity"] if ItemDB.is_weapon(id) else -1)
	return n if data["count"] <= 1 else "%s x%d" % [n, data["count"]]
