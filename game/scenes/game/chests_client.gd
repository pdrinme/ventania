class_name ChestsClient
extends Node
## Baús no cliente: destaque quando dá para interagir, abertura sincronizada
## (tampa + partículas + som) e o ponto da alça que a mão do personagem alcança.

var mundo: Mapa
var abertos := {}                  # i -> true
var _desde_abertura := {}          # i -> segundos desde que abriu
var _destacado := -1
var _overlay: ShaderMaterial

const SHADER_DESTAQUE := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back;
uniform vec4 cor : source_color = vec4(1.0, 0.82, 0.3, 1.0);
void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.2);
	float pulso = 0.65 + 0.35 * sin(TIME * 4.0);
	ALBEDO = cor.rgb * (rim * 1.3 + 0.06) * pulso;
}
"""


func setup(m: Mapa) -> void:
	mundo = m
	var sh := Shader.new()
	sh.code = SHADER_DESTAQUE
	_overlay = ShaderMaterial.new()
	_overlay.shader = sh


func count() -> int:
	return mundo.chest_nodes.size()


func is_open(i: int) -> bool:
	return abertos.has(i)


## Segundos desde a abertura (INF se fechado).
func time_since_open(i: int) -> float:
	return _desde_abertura.get(i, INF)


func position(i: int) -> Vector3:
	return mundo.chest_nodes[i].global_position


## Ponto da alça na borda da tampa (acompanha a tampa enquanto ela abre).
func handle_position(i: int) -> Vector3:
	var h := mundo.chest_nodes[i].find_child("alca_tampa", true, false) as Node3D
	return h.global_position if h else position(i) + Vector3(0, 0.62, 0)


func highlight(i: int) -> void:
	if i == _destacado:
		return
	if _destacado >= 0:
		_aplicar_overlay(_destacado, null)
	_destacado = i
	if i >= 0:
		_aplicar_overlay(i, _overlay)


func _aplicar_overlay(i: int, mat: Material) -> void:
	for mi: MeshInstance3D in mundo.chest_nodes[i].find_children("*", "MeshInstance3D", true, false):
		mi.material_overlay = mat


func open(i: int, com_efeitos := true) -> void:
	if i < 0 or i >= count() or abertos.has(i):
		return
	abertos[i] = true
	_desde_abertura[i] = 0.0
	if _destacado == i:
		highlight(-1)
	var ap := _anim(i)
	if ap:
		ap.play("abrir")
		if not com_efeitos:
			ap.seek(ap.get_animation("abrir").length, true)
	if com_efeitos:
		Audio.play_at("bau_abrir", position(i) + Vector3(0, 0.5, 0))
		_faiscas(position(i) + Vector3(0, 0.6, 0))


func close(i: int) -> void:
	abertos.erase(i)
	_desde_abertura.erase(i)
	var ap := _anim(i)
	if ap:
		ap.stop()
		ap.play("abrir")
		ap.seek(0.0, true)
		ap.pause()


func _anim(i: int) -> AnimationPlayer:
	var aps := mundo.chest_nodes[i].find_children("*", "AnimationPlayer", true, false)
	return aps[0] if not aps.is_empty() else null


func _faiscas(pos: Vector3) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = 28
	p.lifetime = 0.9
	p.explosiveness = 0.9
	p.direction = Vector3.UP
	p.spread = 55.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 4.0
	p.gravity = Vector3(0, -6.0, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.0
	var malha := SphereMesh.new()
	malha.radius = 0.035
	malha.height = 0.07
	malha.radial_segments = 6
	malha.rings = 3
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	malha.material = m
	p.mesh = malha
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.9, 0.45, 1.0))
	g.set_color(1, Color(1.0, 0.7, 0.2, 0.0))
	p.color_ramp = g
	mundo.add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(1.5).timeout.connect(p.queue_free)


func _process(delta: float) -> void:
	for i in _desde_abertura:
		_desde_abertura[i] += delta
