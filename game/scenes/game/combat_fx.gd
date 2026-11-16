class_name CombatFx
extends Node3D
## Efeitos visuais de combate no cliente:
##  - TRAÇANTES que viajam do cano até o alvo (faixa luminosa voltada para a câmera,
##    cabeça brilhante e cauda que esmaece), deixando um rastro fraco que some rápido;
##  - IMPACTOS ao chegar: faíscas + poeira no cenário, clarão vermelho no jogador;
##  - números de dano.
## Tudo em pools (sem alocar durante o tiroteio) e com um shader simples (GLES3).

const VELOCIDADE := 190.0           # m/s do traçante (visível viajando, não instantâneo)
const COMP_MAX := 11.0              # comprimento máximo da faixa (m)
const VIDA_RASTRO := 0.28           # quanto o rastro dura depois da passagem
const VIDA_NUMERO := 0.8
const POOL := 48
const POOL_IMPACTO := 16

const SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;
// Mistura com transparência (e não aditiva): contra céu claro, somar cor vira branco
// e o traçante "some". Cor âmbar saturada + miolo branco contrasta com céu e grama.
uniform vec4 cor : source_color = vec4(1.0, 0.8, 0.22, 1.0);
uniform float largura = 0.11;      // largura base (m)
uniform float largura_dist = 0.006; // + largura por metro de distância da câmera
uniform float brilho = 1.0;
uniform float cabeca = 1.0;        // 1 = cabeça brilhante na ponta (+Z); 0 = uniforme
varying float v_ao_longo;
void vertex() {
	vec3 eixo = MODEL_MATRIX[2].xyz;            // inclui o comprimento (escala Z)
	vec3 centro = MODEL_MATRIX[3].xyz;
	vec3 p = centro + eixo * VERTEX.z;
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 para_cam = normalize(cam - p);
	vec3 lado = normalize(cross(normalize(eixo), para_cam));
	float w = largura + distance(cam, p) * largura_dist;
	p += lado * VERTEX.x * w;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(p, 1.0);
	v_ao_longo = VERTEX.z + 0.5;                // 0 = cauda, 1 = cabeça
	UV = vec2(VERTEX.x + 0.5, v_ao_longo);
}
void fragment() {
	float borda = 1.0 - abs(UV.x * 2.0 - 1.0);           // 0 nas bordas, 1 no centro
	float corpo = smoothstep(0.0, 0.35, borda);
	float miolo = smoothstep(0.35, 0.9, borda);
	float cauda = mix(1.0, smoothstep(0.0, 1.0, v_ao_longo), cabeca);
	float ponta = mix(0.0, smoothstep(0.8, 1.0, v_ao_longo), cabeca);
	ALBEDO = mix(cor.rgb, vec3(1.0, 0.98, 0.9), clamp(miolo + ponta * 0.6, 0.0, 1.0));
	ALPHA = clamp(corpo * cauda * brilho + ponta * 0.3 * brilho, 0.0, 1.0);
}
"""

class Tracante:
	var faixa: MeshInstance3D
	var rastro: MeshInstance3D
	var de := Vector3.ZERO
	var ate := Vector3.ZERO
	var dist := 0.0
	var percorrido := 0.0
	var rastro_t := 0.0
	var comp := 0.0
	var acerto := false
	var normal := Vector3.ZERO
	var ativo := false

var _tracantes: Array[Tracante] = []
var _proximo := 0
var _impactos: Array[CPUParticles3D] = []
var _clarões: Array[MeshInstance3D] = []
var _clarao_t: Array[float] = []
var _prox_imp := 0
var _numeros: Array[Label3D] = []
var _num_tempo: Array[float] = []
var _malha: ArrayMesh
var _grad_jogador: Gradient
var _grad_cenario: Gradient


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_malha = _quad()
	_grad_jogador = Gradient.new()
	_grad_jogador.set_color(0, Color(1.0, 0.35, 0.3, 1.0))
	_grad_jogador.set_color(1, Color(1.0, 0.6, 0.4, 0.0))
	_grad_cenario = Gradient.new()
	_grad_cenario.set_color(0, Color(1.0, 0.9, 0.55, 1.0))
	_grad_cenario.set_color(1, Color(0.75, 0.7, 0.6, 0.0))
	var sh := Shader.new()
	sh.code = SHADER
	for i in POOL:
		var t := Tracante.new()
		t.faixa = _instancia(sh, Color(1.0, 0.8, 0.22), 1.0, 1.0, 0.11)
		t.rastro = _instancia(sh, Color(1.0, 0.88, 0.5), 0.45, 0.0, 0.03)
		(t.rastro.material_override as ShaderMaterial).set_shader_parameter("largura_dist", 0.0025)
		_tracantes.append(t)
	for i in POOL_IMPACTO:
		_impactos.append(_criar_particulas())
		var f := _instancia(sh, Color(1.0, 0.75, 0.4), 1.0, 0.0, 0.0)
		f.mesh = _disco()
		_clarões.append(f)
		_clarao_t.append(0.0)
	for i in 12:
		var l := Label3D.new()
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.fixed_size = true
		l.pixel_size = 0.0018
		l.font = load("res://assets/ui/fontes/fredoka_700.woff2")
		l.font_size = 30
		l.outline_size = 10
		l.outline_modulate = Color("24252c")
		l.visible = false
		add_child(l)
		_numeros.append(l)
		_num_tempo.append(0.0)


## Quad de -0.5..0.5 em X (largura) e Z (comprimento); o shader o vira para a câmera.
func _quad() -> ArrayMesh:
	var v := PackedVector3Array([Vector3(-0.5, 0, -0.5), Vector3(0.5, 0, -0.5), Vector3(0.5, 0, 0.5),
			Vector3(-0.5, 0, -0.5), Vector3(0.5, 0, 0.5), Vector3(-0.5, 0, 0.5)])
	var a := []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = v
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	# a forma real depende do shader: evita ser descartado pelo culling
	m.custom_aabb = AABB(Vector3(-50, -50, -50), Vector3(100, 100, 100))
	return m


## Disco do clarão de impacto (billboard comum).
func _disco() -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(0.8, 0.8)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.no_depth_test = false
	m.albedo_texture = PawnVisual._textura_clarao()
	q.material = m
	return q


func _instancia(sh: Shader, cor: Color, brilho: float, cabeca: float, largura: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _malha
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.ignore_occlusion_culling = true
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("cor", cor)
	mat.set_shader_parameter("brilho", brilho)
	mat.set_shader_parameter("cabeca", cabeca)
	mat.set_shader_parameter("largura", largura)
	mi.material_override = mat
	mi.visible = false
	add_child(mi)
	return mi


func _criar_particulas() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = 16
	p.lifetime = 0.5
	p.explosiveness = 1.0
	p.spread = 70.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 4.5
	p.gravity = Vector3(0, -9.0, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	var malha := BoxMesh.new()
	malha.size = Vector3(0.08, 0.08, 0.08)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	malha.material = m
	p.mesh = malha
	add_child(p)
	return p


## Dispara um traçante do cano (`de`) até o ponto final. acerto = atingiu um jogador.
## curto = projéteis de espingarda (faixa menor); normal = da superfície atingida.
func tracer(de: Vector3, ate: Vector3, acerto := false, curto := false, normal := Vector3.ZERO) -> void:
	var dist := de.distance_to(ate)
	if dist < 0.1:
		return
	var t := _tracantes[_proximo]
	_proximo = (_proximo + 1) % POOL
	t.de = de
	t.ate = ate
	t.dist = dist
	t.percorrido = 0.0
	t.rastro_t = 0.0
	t.comp = minf(COMP_MAX * (0.45 if curto else 1.0), dist)
	t.acerto = acerto
	t.normal = normal if normal != Vector3.ZERO else (de - ate).normalized()
	t.ativo = true
	(t.faixa.material_override as ShaderMaterial).set_shader_parameter("cor",
			Color(1.0, 0.45, 0.22) if acerto else Color(1.0, 0.8, 0.22))
	t.faixa.visible = true
	t.rastro.visible = true
	_posicionar(t)


func _posicionar(t: Tracante) -> void:
	var dir := (t.ate - t.de) / t.dist
	var cabeca_d := minf(t.percorrido, t.dist)
	var cauda_d := maxf(0.0, cabeca_d - t.comp)
	var base := Basis.looking_at(-dir, Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT)
	_esticar(t.faixa, t.de + dir * cauda_d, t.de + dir * cabeca_d, base)
	# rastro fraco: do cano até a cabeça (some depois que o projétil chega)
	_esticar(t.rastro, t.de, t.de + dir * cabeca_d, base)


func _esticar(mi: MeshInstance3D, a: Vector3, b: Vector3, base: Basis) -> void:
	var comp := maxf(0.001, a.distance_to(b))
	# escala no eixo LOCAL Z (ao longo do disparo). Basis.scaled() escalaria no eixo
	# Z do mundo e entortaria a faixa (o traçante ia para o lado do alvo).
	mi.global_transform = Transform3D(base * Basis.from_scale(Vector3(1, 1, comp)), a.lerp(b, 0.5))


## Efeito no ponto de impacto: faíscas/poeira no cenário, clarão vermelho no jogador.
func impact(pos: Vector3, normal: Vector3, em_jogador: bool) -> void:
	var i := _prox_imp
	_prox_imp = (_prox_imp + 1) % POOL_IMPACTO
	var p := _impactos[i]
	p.global_position = pos + normal * 0.03
	p.direction = normal if normal != Vector3.ZERO else Vector3.UP
	p.color_ramp = _grad_jogador if em_jogador else _grad_cenario
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 4.5
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	p.restart()
	p.emitting = true
	var f := _clarões[i]
	f.global_position = pos + normal * 0.05
	(f.mesh as QuadMesh).material.albedo_color = Color(1.0, 0.45, 0.4) if em_jogador else Color(1.0, 0.85, 0.5)
	f.visible = true
	_clarao_t[i] = 0.09


## Cores e força das partículas do golpe de picareta, por material.
## [cor inicial, cor final, velocidade mín., máx., escala, cor do clarão]
const GOLPE := {
	ImpactMaterial.MADEIRA: [Color("e0a35e"), Color(0.55, 0.36, 0.18, 0.0), 1.6, 3.8, 1.9, Color(1.0, 0.85, 0.6)],
	ImpactMaterial.PEDRA: [Color("d6d1c6"), Color(0.55, 0.55, 0.52, 0.0), 1.0, 3.0, 1.7, Color(0.95, 0.95, 0.9)],
	ImpactMaterial.METAL: [Color("fff6c8"), Color(1.0, 0.55, 0.15, 0.0), 3.5, 7.0, 0.8, Color(1.0, 0.95, 0.7)],
	ImpactMaterial.TERRA: [Color("9a7846"), Color(0.35, 0.55, 0.25, 0.0), 1.2, 2.8, 1.5, Color(0.9, 0.85, 0.7)],
	ImpactMaterial.NENHUM: [Color("e2dccf"), Color(0.6, 0.6, 0.6, 0.0), 1.2, 3.0, 1.4, Color(1.0, 0.95, 0.85)],
}
var _grad_golpe := {}
var melee_impacts := 0               # testes/diagnóstico


## Impacto da picareta: lascas de madeira, poeira de pedra, faíscas de metal…
func melee_impact(pos: Vector3, normal: Vector3, material: int) -> void:
	melee_impacts += 1
	if material == ImpactMaterial.JOGADOR:
		impact(pos, normal, true)
		return
	var g: Array = GOLPE.get(material, GOLPE[ImpactMaterial.NENHUM])
	if not _grad_golpe.has(material):
		var gr := Gradient.new()
		gr.set_color(0, g[0])
		gr.set_color(1, g[1])
		_grad_golpe[material] = gr
	var i := _prox_imp
	_prox_imp = (_prox_imp + 1) % POOL_IMPACTO
	var p := _impactos[i]
	p.global_position = pos + normal * 0.04
	p.direction = normal if normal != Vector3.ZERO else Vector3.UP
	p.color_ramp = _grad_golpe[material]
	p.initial_velocity_min = g[2]
	p.initial_velocity_max = g[3]
	p.scale_amount_min = 0.6 * g[4]
	p.scale_amount_max = 1.2 * g[4]
	p.restart()
	p.emitting = true
	var f := _clarões[i]
	f.global_position = pos + normal * 0.05
	(f.mesh as QuadMesh).material.albedo_color = g[5]
	f.visible = true
	_clarao_t[i] = 0.10


func damage_number(pos: Vector3, dano: int, cabeca: bool, escudo: bool) -> void:
	var i := _num_tempo.find(_num_tempo.min())
	var l := _numeros[i]
	l.text = str(dano)
	l.modulate = Color("ffd23c") if cabeca else (Color("6fc8ff") if escudo else Color.WHITE)
	l.global_position = pos + Vector3(randf_range(-0.2, 0.2), 0.3, 0)
	l.visible = true
	_num_tempo[i] = VIDA_NUMERO


## Traçantes em voo (testes/diagnóstico).
func active_tracers() -> int:
	return _tracantes.filter(func(t): return t.ativo).size()


func _process(delta: float) -> void:
	for t in _tracantes:
		if not t.ativo:
			continue
		if t.percorrido < t.dist + t.comp:
			var antes := t.percorrido
			t.percorrido += VELOCIDADE * delta
			if antes < t.dist and t.percorrido >= t.dist:
				# chegou: impacto no ponto final
				impact(t.ate, t.normal, t.acerto)
			_posicionar(t)
			var mat_r := t.rastro.material_override as ShaderMaterial
			mat_r.set_shader_parameter("brilho", 0.45)
		else:
			t.faixa.visible = false
			t.rastro_t += delta
			var mat_r := t.rastro.material_override as ShaderMaterial
			mat_r.set_shader_parameter("brilho", 0.45 * (1.0 - t.rastro_t / VIDA_RASTRO))
			if t.rastro_t >= VIDA_RASTRO:
				t.rastro.visible = false
				t.ativo = false
	for i in _clarões.size():
		if _clarao_t[i] > 0.0:
			_clarao_t[i] -= delta
			if _clarao_t[i] <= 0.0:
				_clarões[i].visible = false
	for i in _numeros.size():
		if _num_tempo[i] > 0.0:
			_num_tempo[i] -= delta
			_numeros[i].position.y += delta * 0.8
			_numeros[i].modulate.a = clampf(_num_tempo[i] / 0.3, 0.0, 1.0)
			if _num_tempo[i] <= 0.0:
				_numeros[i].visible = false
