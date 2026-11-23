class_name LootVisual
extends Node3D
## Item no chão (cliente): modelo flutuando e girando sobre um anel na cor da
## raridade, que pulsa; de incomum para cima, uma coluna de luz suave (mais alta
## quanto mais raro) ajuda a achar o item de longe. Sem luzes reais: só malhas
## sem sombreamento e aditivas, baratas em qualquer perfil.

var data := {}
var _modelo: Node3D
var _anel: MeshInstance3D
var _coluna: MeshInstance3D
var _mat_anel: StandardMaterial3D
var _t := 0.0
var _salto_de := Vector3.INF
var _salto_t := 1.0
const DURACAO_SALTO := 0.45


static func model_path(l: Dictionary) -> String:
	if l.get("mat", 0) != 0:
		return Grade.asset_path(Grade.PISO, l["mat"] - 1)    # pilha de material: placa da peça, reduzida
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
		# busca o autoload em tempo de execução (o script também é usado em ferramentas
		# de captura, rodadas sem os autoloads compilados)
		var audio := (Engine.get_main_loop() as SceneTree).root.get_node_or_null("Audio")
		if audio:
			audio.play_at("loot_pop", origem, -4.0, randf_range(0.9, 1.15))
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
	var tem_raridade: bool = l["ammo"] == 0 and l.get("mat", 0) == 0
	var cor := ItemDB.rarity_color(l["rarity"]) if tem_raridade else Color("9a9a9a")
	mat.albedo_color = cor
	m.material = mat
	_mat_anel = mat
	anel.mesh = m
	anel.position.y = 0.02
	anel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(anel)
	_anel = anel
	anel.visible = _salto_t >= 1.0          # o anel só aparece quando o item pousa
	if tem_raridade and int(l["rarity"]) >= 1:
		_coluna = _coluna_de_luz(cor, 1.2 + 0.7 * int(l["rarity"]))
		_coluna.visible = anel.visible
		add_child(_coluna)
	_modelo = (load(model_path(l)) as PackedScene).instantiate() as Node3D
	_modelo.position.y = 0.35
	if l.get("mat", 0) != 0:
		_modelo.scale = Vector3.ONE * 0.14
	elif tem_raridade and ItemDB.is_weapon(ItemDB.id_of(l["item"])):
		_modelo.scale = Vector3.ONE * 1.3     # arma no chão um pouco maior: lê de longe
	add_child(_modelo)


func _process(delta: float) -> void:
	if _salto_t < 1.0:
		_salto_t = minf(1.0, _salto_t + delta / DURACAO_SALTO)
		var k := _salto_t
		position = (_salto_de as Vector3).lerp(data["pos"], k) + Vector3(0, sin(k * PI) * 0.9, 0)
		if _salto_t >= 1.0 and _anel:
			_anel.visible = true
			if _coluna:
				_coluna.visible = true
	_t += delta
	if _modelo:
		_modelo.rotation.y = _t * 1.2
		_modelo.position.y = 0.35 + sin(_t * 2.0) * 0.05
	if _anel:
		var pulso := 1.0 + 0.08 * sin(_t * 3.0)
		_anel.scale = Vector3(pulso, 1.0, pulso)


static var _shader_coluna: Shader


## Coluna de luz: cilindro aberto, aditivo, que some para cima.
static func _coluna_de_luz(cor: Color, altura: float) -> MeshInstance3D:
	if _shader_coluna == null:
		_shader_coluna = Shader.new()
		_shader_coluna.code = """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 cor : source_color;
uniform float altura = 2.0;
varying float y;
void vertex() { y = VERTEX.y / altura + 0.5; }
void fragment() {
	float faixa = 0.75 + 0.25 * sin(y * 18.0 - TIME * 3.0);
	ALBEDO = cor.rgb;
	ALPHA = pow(1.0 - clamp(y, 0.0, 1.0), 1.6) * 0.35 * faixa;
}
"""
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.18
	c.bottom_radius = 0.32
	c.height = altura
	c.radial_segments = 10
	c.rings = 1
	c.cap_top = false
	c.cap_bottom = false
	var sm := ShaderMaterial.new()
	sm.shader = _shader_coluna
	sm.set_shader_parameter("cor", cor)
	sm.set_shader_parameter("altura", altura)
	c.material = sm
	mi.mesh = c
	mi.position.y = altura * 0.5 + 0.03
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func label() -> String:
	if data.get("mat", 0) != 0:
		return "%s x%d" % [ItemDB.material(ItemDB.material_types()[data["mat"] - 1])["nome"], data["count"]]
	if data["ammo"] != 0:
		return ItemDB.ammo(ItemDB.ammo_types()[data["ammo"] - 1])["nome"]
	var id := ItemDB.id_of(data["item"])
	var n := ItemDB.display_name(id, data["rarity"] if ItemDB.is_weapon(id) else -1)
	return n if data["count"] <= 1 else "%s x%d" % [n, data["count"]]
