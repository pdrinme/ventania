class_name EliminacaoVisual
extends Node3D
## Eliminação (só visual, em todos os clientes): uma cópia do personagem, com o
## traje dele, toca o clipe "eliminado" (o golpe joga o tronco para trás, ele
## cambaleia, cai de joelhos e tomba) e, deitado, é levado por uma rajada de vento
## (gira, encolhe e some num redemoinho de folhas e poeira) — o tema do jogo.
## Não interfere na partida: o servidor já removeu o jogador.

const DURACAO_QUEDA := 1.6          # duração do clipe "eliminado"
const ESPERA := 0.35                # deitado antes do vento
const DURACAO_VENTO := 0.7

var _modelo: Node3D
var _t := 0.0
var _vento := false
var _redemoinho: CPUParticles3D


## Cria a cena da eliminação no lugar (transform do personagem) com o traje.
static func spawn(pai: Node, traje: String, xf: Transform3D) -> EliminacaoVisual:
	var e := EliminacaoVisual.new()
	e.name = "Eliminacao"
	pai.add_child(e)
	e.global_transform = Transform3D(Basis(Vector3.UP, xf.basis.get_euler().y), xf.origin)
	e._montar(traje)
	return e


func _montar(traje: String) -> void:
	_modelo = (load(Cosmeticos.outfit_scene(traje)) as PackedScene).instantiate() as Node3D
	_modelo.rotation.y = PI
	add_child(_modelo)
	TrajeFx.attach(_modelo, traje)
	var ap := _modelo.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	if ap.has_animation("eliminado"):
		ap.play("eliminado", 0.08)
	_redemoinho = _particulas()
	add_child(_redemoinho)
	var audio := get_node_or_null("/root/Audio")
	if audio:
		audio.play_at("eliminado", global_position + Vector3(0, 1, 0), -2.0, randf_range(0.95, 1.05))


func _process(delta: float) -> void:
	_t += delta
	if not _vento and _t >= DURACAO_QUEDA + ESPERA:
		_vento = true
		_redemoinho.emitting = true
		var audio := get_node_or_null("/root/Audio")
		if audio:
			audio.play_at("rajada", global_position + Vector3(0, 0.5, 0), -4.0, randf_range(0.95, 1.1))
	if _vento:
		var k := clampf((_t - DURACAO_QUEDA - ESPERA) / DURACAO_VENTO, 0.0, 1.0)
		var e := k * k * (3.0 - 2.0 * k)
		# o vento levanta, gira e encolhe o corpo até sumir
		_modelo.position = Vector3(0.0, e * 1.6, 0.0)
		_modelo.rotation.y = PI + e * TAU * 1.5
		_modelo.scale = Vector3.ONE * maxf(0.001, 1.0 - e)
		if k >= 1.0:
			_modelo.visible = false
	if _t > DURACAO_QUEDA + ESPERA + DURACAO_VENTO + 1.2:
		queue_free()


## Redemoinho de folhas e poeira (barato: CPUParticles, poucas partículas).
func _particulas() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.one_shot = true
	p.explosiveness = 0.6
	var fator := 1.0
	var st := get_node_or_null("/root/Settings")
	if st and st.has_method("particle_factor"):
		fator = st.particle_factor()
	p.amount = maxi(6, int(28 * fator))
	p.lifetime = 1.1
	p.position = Vector3(0, 0.4, 0)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.6
	p.direction = Vector3(0, 1, 0)
	p.spread = 35.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 4.0
	p.gravity = Vector3(0, 0.6, 0)
	p.orbit_velocity_min = 0.6
	p.orbit_velocity_max = 1.1
	p.angular_velocity_min = -360.0
	p.angular_velocity_max = 360.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	var curva := Curve.new()
	curva.add_point(Vector2(0, 1))
	curva.add_point(Vector2(1, 0))
	p.scale_amount_curve = curva
	var q := QuadMesh.new()
	q.size = Vector2(0.12, 0.08)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	q.material = m
	p.mesh = q
	var g := Gradient.new()
	g.set_color(0, Color("86db5c"))
	g.add_point(0.5, Color("f0dca2"))
	g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0.0))
	p.color_ramp = g
	p.color_initial_ramp = null
	return p
