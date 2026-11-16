class_name CombatFx
extends Node3D
## Efeitos visuais de combate no cliente: traçantes e números de dano.
## Objetos reaproveitados (pool) para não alocar durante o tiroteio.

const VIDA_TRACANTE := 0.09
const VIDA_NUMERO := 0.8
const POOL := 32

var _tracantes: Array[MeshInstance3D] = []
var _tempos: Array[float] = []
var _numeros: Array[Label3D] = []
var _num_tempo: Array[float] = []
var _mat_normal: StandardMaterial3D
var _mat_acerto: StandardMaterial3D


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_mat_normal = _material(Color(1.0, 0.93, 0.6, 0.9))
	_mat_acerto = _material(Color(1.0, 0.45, 0.35, 0.95))
	var malha := BoxMesh.new()
	malha.size = Vector3(0.03, 0.03, 1.0)
	for i in POOL:
		var t := MeshInstance3D.new()
		t.mesh = malha
		t.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		t.visible = false
		add_child(t)
		_tracantes.append(t)
		_tempos.append(0.0)
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


func _material(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


func tracer(de: Vector3, ate: Vector3, acerto := false) -> void:
	var i := _tempos.find(_tempos.min())
	var t := _tracantes[i]
	var comp := de.distance_to(ate)
	if comp < 0.05:
		return
	t.material_override = _mat_acerto if acerto else _mat_normal
	t.global_transform = Transform3D(Basis.looking_at(ate - de, Vector3.UP if absf((ate - de).normalized().y) < 0.99 else Vector3.RIGHT), de.lerp(ate, 0.5))
	t.scale = Vector3(1, 1, comp)
	t.visible = true
	_tempos[i] = VIDA_TRACANTE


func damage_number(pos: Vector3, dano: int, cabeca: bool, escudo: bool) -> void:
	var i := _num_tempo.find(_num_tempo.min())
	var l := _numeros[i]
	l.text = str(dano)
	l.modulate = Color("ffd23c") if cabeca else (Color("6fc8ff") if escudo else Color.WHITE)
	l.global_position = pos + Vector3(randf_range(-0.2, 0.2), 0.3, 0)
	l.visible = true
	_num_tempo[i] = VIDA_NUMERO


func _process(delta: float) -> void:
	for i in POOL:
		if _tempos[i] > 0.0:
			_tempos[i] -= delta
			if _tempos[i] <= 0.0:
				_tracantes[i].visible = false
	for i in _numeros.size():
		if _num_tempo[i] > 0.0:
			_num_tempo[i] -= delta
			_numeros[i].position.y += delta * 0.8
			_numeros[i].modulate.a = clampf(_num_tempo[i] / 0.3, 0.0, 1.0)
			if _num_tempo[i] <= 0.0:
				_numeros[i].visible = false
