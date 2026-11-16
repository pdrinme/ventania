class_name PlayerCamera
extends Node3D
## Câmera em terceira pessoa por cima do ombro. Segue a posição INTERPOLADA do
## pawn (física a 30 Hz, câmera a cada frame). Olhar: mouse (capturado),
## analógico direito ou arrastar no toque (add_look). SpringArm evita atravessar paredes.

const ALTURA_PE := 1.55
const ALTURA_AGACHADO := 1.05
const OMBRO := 0.55
const DIST := 3.2
const DIST_MIRA := 1.7
const FOV := 70.0
const FOV_MIRA := 55.0
const PITCH_MIN := -80.0
const PITCH_MAX := 70.0

var alvo: Node3D             # Pawn (jogando) ou PawnVisual de outro jogador (espectador)
var yaw := 0.0
var pitch := -10.0          # graus
var mirando := false
var bloqueado := false      # pausa: ignora o olhar
var _braco: SpringArm3D
var _cam: Camera3D
var _altura := ALTURA_PE


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_braco = SpringArm3D.new()
	_braco.spring_length = DIST
	_braco.margin = 0.2
	_braco.collision_mask = Pawn.LAYER_WORLD
	var esfera := SphereShape3D.new()
	esfera.radius = 0.25
	_braco.shape = esfera
	add_child(_braco)
	_cam = Camera3D.new()
	_cam.fov = FOV
	_cam.current = true
	_cam.add_to_group("camera_principal")
	_braco.add_child(_cam)


func yaw_rad() -> float:
	return deg_to_rad(yaw)


func pitch_rad() -> float:
	return deg_to_rad(pitch)


## delta em pixels de tela (mouse ou dedo) já multiplicado pela sensibilidade.
func add_look(delta: Vector2) -> void:
	if bloqueado:
		return
	var inv := -1.0 if Settings.get_value("controls", "invert_y") else 1.0
	var fator := 0.5 if mirando else 1.0
	yaw = fposmod(yaw - delta.x * 0.15 * fator, 360.0)
	pitch = clampf(pitch - delta.y * 0.15 * fator * inv, PITCH_MIN, PITCH_MAX)


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		add_look(e.relative * float(Settings.get_value("controls", "mouse_sensitivity")))


func _process(delta: float) -> void:
	var eixo := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if eixo.length() > 0.08 and not bloqueado:
		var s: float = Settings.get_value("controls", "gamepad_sensitivity")
		add_look(eixo * 900.0 * delta * s)
	if alvo == null:
		return
	mirando = Input.is_action_pressed("aim") and not bloqueado
	var agachado: bool = alvo is Pawn and (alvo as Pawn).crouched
	var altura_alvo := ALTURA_AGACHADO if agachado else ALTURA_PE
	_altura = lerpf(_altura, altura_alvo, minf(1.0, delta * 12.0))
	global_position = alvo.get_global_transform_interpolated().origin + Vector3(0, _altura, 0)
	rotation = Vector3(deg_to_rad(pitch), deg_to_rad(yaw), 0)
	_braco.spring_length = lerpf(_braco.spring_length, DIST_MIRA if mirando else DIST, minf(1.0, delta * 10.0))
	_braco.position = Vector3(OMBRO, 0, 0)
	_cam.fov = lerpf(_cam.fov, FOV_MIRA if mirando else FOV, minf(1.0, delta * 10.0))
	if alvo is CollisionObject3D:
		_braco.add_excluded_object((alvo as CollisionObject3D).get_rid())


func camera() -> Camera3D:
	return _cam
