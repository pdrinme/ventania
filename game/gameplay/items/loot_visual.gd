class_name LootVisual
extends Node3D
## Item no chão (cliente): modelo girando sobre um anel na cor da raridade.

var data := {}
var _modelo: Node3D
var _anel: MeshInstance3D
var _t := 0.0
var _salto_de := Vector3.INF
var _salto_t := 1.0
const DURACAO_SALTO := 0.45


static func model_path(l: Dictionary) -> String:
	if l["ammo"] != 0:
		return "res://assets/baus_coletaveis/municao_01.glb"
	var id := ItemDB.id_of(l["item"])
	if ItemDB.is_weapon(id):
		return "res://assets/armas/%s.glb" % ItemDB.weapon(id)["modelo"]
	return "res://assets/baus_coletaveis/%s.glb" % ItemDB.consumable(id)["modelo"]


## origem: se informada (ex.: baú que acabou de abrir), o item salta dela até o chão.
func setup(l: Dictionary, origem := Vector3.INF) -> void:
	data = l
	position = l["pos"]
	if origem != Vector3.INF:
		_salto_de = origem
		_salto_t = 0.0
		position = origem
		Audio.play_at("loot_pop", origem, -4.0, randf_range(0.9, 1.15))
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
	_anel = anel
	anel.visible = _salto_t >= 1.0          # o anel só aparece quando o item pousa
	_modelo = (load(model_path(l)) as PackedScene).instantiate() as Node3D
	_modelo.position.y = 0.35
	add_child(_modelo)


func _process(delta: float) -> void:
	if _salto_t < 1.0:
		_salto_t = minf(1.0, _salto_t + delta / DURACAO_SALTO)
		var k := _salto_t
		position = (_salto_de as Vector3).lerp(data["pos"], k) + Vector3(0, sin(k * PI) * 0.9, 0)
		if _salto_t >= 1.0 and _anel:
			_anel.visible = true
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
