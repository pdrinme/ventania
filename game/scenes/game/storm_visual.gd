class_name StormVisual
extends Node3D
## Parede da Tormenta (cliente): cilindro aberto, roxo translúcido com faixas
## animadas, no círculo seguro atual. O estado vem do servidor (S_STORM) e o
## cliente só interpola o fechamento pelo tempo. Também informa se um ponto está
## fora da zona (aviso e tela roxa no HUD).

const ALTURA := 220.0
const SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled;
uniform vec4 cor : source_color = vec4(0.55, 0.25, 0.95, 0.42);
void fragment() {
	float faixa = sin(UV.y * 90.0 - TIME * 2.4 + UV.x * 40.0) * 0.5 + 0.5;
	float base = smoothstep(0.0, 0.08, UV.y) * (1.0 - smoothstep(0.75, 1.0, UV.y));
	ALBEDO = mix(cor.rgb, vec3(0.85, 0.6, 1.0), faixa * 0.35);
	ALPHA = cor.a * (0.65 + faixa * 0.35) * mix(0.35, 1.0, base);
}
"""

var dados := {}
var _recebido := 0.0
var _parede: MeshInstance3D


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var cil := CylinderMesh.new()
	cil.top_radius = 1.0
	cil.bottom_radius = 1.0
	cil.height = 1.0
	cil.radial_segments = 96
	cil.rings = 1
	cil.cap_top = false
	cil.cap_bottom = false
	var sh := Shader.new()
	sh.code = SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	cil.material = m
	_parede = MeshInstance3D.new()
	_parede.mesh = cil
	_parede.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_parede.extra_cull_margin = 16384.0
	add_child(_parede)
	visible = false


func set_state(t: Dictionary) -> void:
	dados = t
	_recebido = Time.get_ticks_msec() / 1000.0
	visible = true


func clear() -> void:
	dados = {}
	visible = false


func active() -> bool:
	return not dados.is_empty()


## Círculo seguro agora: [centro Vector2, raio].
func current() -> Array:
	if dados.is_empty():
		return [Vector2.ZERO, 1e6]
	if not dados["fechando"] or dados["total_ms"] <= 0:
		return [dados["c_de"], dados["r_de"]]
	var passou := (Time.get_ticks_msec() / 1000.0 - _recebido) * 1000.0
	var k := clampf(1.0 - (dados["resta_ms"] - passou) / float(dados["total_ms"]), 0.0, 1.0)
	return [(dados["c_de"] as Vector2).lerp(dados["c_para"], k), lerpf(dados["r_de"], dados["r_para"], k)]


## Próxima zona: [centro, raio].
func next_zone() -> Array:
	if dados.is_empty():
		return [Vector2.ZERO, 0.0]
	return [dados["c_para"], dados["r_para"]]


func seconds_left() -> float:
	if dados.is_empty():
		return 0.0
	return maxf(0.0, dados["resta_ms"] / 1000.0 - (Time.get_ticks_msec() / 1000.0 - _recebido))


func is_outside(p: Vector3) -> bool:
	var c := current()
	return active() and Vector2(p.x, p.z).distance_to(c[0]) > float(c[1])


func _process(_delta: float) -> void:
	if dados.is_empty():
		return
	var c := current()
	var r := maxf(0.5, float(c[1]))
	_parede.scale = Vector3(r, ALTURA, r)
	_parede.position = Vector3(c[0].x, ALTURA * 0.5 - 30.0, c[0].y)
