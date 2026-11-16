class_name OrbitCamera
extends Camera3D
## Câmera orbital: arrastar (mouse/toque) gira, roda/pinça aproxima,
## analógico direito do controle gira. Usa as sensibilidades das configurações.

@export var alvo := Vector3(1.5, 1.6, -3.0)
var yaw := 0.0
var pitch := -12.0
var distancia := 17.0
var automatico := false  # benchmark: a câmera gira sozinha
var _toques := {}


func _ready() -> void:
	add_to_group("camera_principal")
	_atualizar()


func _unhandled_input(e: InputEvent) -> void:
	if automatico:
		return
	var inv := -1.0 if Settings.get_value("controls", "invert_y") else 1.0
	if e is InputEventMouseMotion and (e.button_mask & (MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_RIGHT)) and _toques.size() < 2:
		var s: float = Settings.get_value("controls", "touch_sensitivity" if Settings.is_mobile else "mouse_sensitivity")
		yaw -= e.relative.x * 0.3 * s
		pitch = clampf(pitch - e.relative.y * 0.3 * s * inv, -70.0, -2.0)
		_atualizar()
	elif e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP:
			distancia = maxf(5.0, distancia * 0.9)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distancia = minf(80.0, distancia * 1.1)
		_atualizar()
	elif e is InputEventScreenTouch:
		if e.pressed:
			_toques[e.index] = e.position
		else:
			_toques.erase(e.index)
	elif e is InputEventScreenDrag and _toques.size() == 2:
		var outros := _toques.keys().filter(func(k): return k != e.index)
		if outros.is_empty():
			return
		var outro: Vector2 = _toques[outros[0]]
		var antes: float = (_toques[e.index] as Vector2).distance_to(outro)
		var depois: float = e.position.distance_to(outro)
		_toques[e.index] = e.position
		if antes > 1.0:
			distancia = clampf(distancia * antes / depois, 5.0, 80.0)
			_atualizar()


func _process(delta: float) -> void:
	if automatico:
		yaw += delta * 18.0
		_atualizar()
		return
	var eixo := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if eixo.length() > 0.05:
		var s: float = Settings.get_value("controls", "gamepad_sensitivity")
		yaw -= eixo.x * 120.0 * delta * s
		pitch = clampf(pitch - eixo.y * 90.0 * delta * s, -70.0, -2.0)
		_atualizar()


func _atualizar() -> void:
	var dir := Basis.from_euler(Vector3(deg_to_rad(pitch), deg_to_rad(yaw), 0)) * Vector3(0, 0, 1)
	look_at_from_position(alvo + dir * distancia, alvo, Vector3.UP)
