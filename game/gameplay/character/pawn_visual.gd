class_name PawnVisual
extends Node3D
## Visual do personagem (modelo + animações). Só existe no cliente.
## Escolhe a animação pelo estado (velocidade e flags) e ajusta a velocidade do ciclo.

const MODELO := "res://assets/personagens/recruta_base_01.glb"
const REF_ANDAR := 4.5
const REF_CORRER := 6.5
const REF_AGACHADO := 2.5
const MISTURA := 0.15

var _ap: AnimationPlayer
var _atual := ""


func _ready() -> void:
	var modelo := (load(MODELO) as PackedScene).instantiate() as Node3D
	modelo.rotation.y = PI   # o modelo olha para +Z; o jogo usa -Z como frente
	add_child(modelo)
	var aps := modelo.find_children("*", "AnimationPlayer", true, false)
	if not aps.is_empty():
		_ap = aps[0]
		_tocar("idle", 1.0)


## velocidade: m/s (mundo); flags: Protocol.F_*
func update_state(velocidade: Vector3, flags: int, yaw: float) -> void:
	rotation.y = yaw
	if _ap == null:
		return
	var h := Vector2(velocidade.x, velocidade.z).length()
	var agachado := flags & Protocol.F_CROUCHED != 0
	var no_chao := flags & Protocol.F_ON_FLOOR != 0
	if not no_chao and absf(velocidade.y) > 1.0:
		_tocar("no_ar", 1.0)
	elif agachado:
		if h > 0.3:
			_tocar("agachado_andar", clampf(h / REF_AGACHADO, 0.5, 1.6))
		else:
			_tocar("agachado", 1.0)
	elif h > 5.2:
		_tocar("correr", clampf(h / REF_CORRER, 0.6, 1.5))
	elif h > 0.3:
		_tocar("andar", clampf(h / REF_ANDAR, 0.5, 1.6))
	else:
		_tocar("idle", 1.0)


func _tocar(nome: String, velocidade: float) -> void:
	_ap.speed_scale = velocidade
	if nome != _atual and _ap.has_animation(nome):
		_ap.play(nome, MISTURA)
		_atual = nome


func current_animation() -> String:
	return _atual
