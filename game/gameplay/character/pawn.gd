class_name Pawn
extends CharacterBody3D
## Corpo físico do jogador (cápsula). Sem visual: o visual é PawnVisual.
## Mesmo nó no servidor e no cliente (predição do jogador local).

const RADIUS := 0.35
const HEIGHT_STAND := 1.8
const HEIGHT_CROUCH := 1.15
const LAYER_WORLD := 1
const LAYER_PAWN := 2

var entity_id := 0
var yaw := 0.0
var crouched := false
var grounded := false     # resultado do último passo (vem do servidor na reconciliação)
var sprinting := false
## Entrada na partida: 0 normal, QUEDA_LIVRE, PLANADOR, NO_ONIBUS (viaja no ônibus).
var queda := 0
const QUEDA_LIVRE := 1
const PLANADOR := 2
const NO_ONIBUS := 3
var _shape: CollisionShape3D
var _capsula: CapsuleShape3D


func _init() -> void:
	collision_layer = LAYER_PAWN
	collision_mask = LAYER_WORLD          # jogadores não se bloqueiam (evita erros de predição)
	floor_max_angle = deg_to_rad(50.0)    # rampas da construção têm 45°
	floor_snap_length = 0.0               # snap feito em Movement (determinístico)
	floor_constant_speed = true           # rampas: mesma velocidade ao longo do piso que no plano
	safe_margin = 0.02
	motion_mode = MOTION_MODE_GROUNDED
	_capsula = CapsuleShape3D.new()
	_capsula.radius = RADIUS
	_shape = CollisionShape3D.new()
	_shape.shape = _capsula
	add_child(_shape)
	_aplicar_altura(HEIGHT_STAND)


func _aplicar_altura(h: float) -> void:
	_capsula.height = h
	_shape.position = Vector3(0, h / 2.0, 0)


func set_crouched(v: bool) -> void:
	crouched = v
	_aplicar_altura(HEIGHT_CROUCH if v else HEIGHT_STAND)


## Há espaço para ficar de pé?
func can_stand() -> bool:
	var teste := PhysicsShapeQueryParameters3D.new()
	var c := CapsuleShape3D.new()
	c.radius = RADIUS - 0.02
	c.height = HEIGHT_STAND
	teste.shape = c
	teste.transform = Transform3D(Basis(), global_position + Vector3(0, HEIGHT_STAND / 2.0 + 0.02, 0))
	teste.collision_mask = LAYER_WORLD
	return get_world_3d().direct_space_state.intersect_shape(teste, 1).is_empty()


func flags() -> int:
	var f := 0
	if grounded:
		f |= Protocol.F_ON_FLOOR
	if crouched:
		f |= Protocol.F_CROUCHED
	if sprinting:
		f |= Protocol.F_SPRINTING
	return f


func to_state() -> Protocol.EntityState:
	var e := Protocol.EntityState.new()
	e.id = entity_id
	e.position = global_position
	e.velocity = velocity
	e.yaw = yaw
	e.flags = flags()
	e.queda = queda
	return e


## Aplica o estado autoritativo do servidor (reconciliação).
func apply_state(e: Protocol.EntityState) -> void:
	global_position = e.position
	velocity = e.velocity
	yaw = e.yaw
	grounded = e.flags & Protocol.F_ON_FLOOR != 0
	var agachado := e.flags & Protocol.F_CROUCHED != 0
	if agachado != crouched:
		set_crouched(agachado)
	sprinting = e.flags & Protocol.F_SPRINTING != 0
	queda = e.queda
