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
var _anexo: BoneAttachment3D
var _arma_atual := 0
var _arma_pedida := 0
var _modelo: Node3D
var com_arma := false

## Ajuste da arma na mão (osso RightHand: o eixo Y do osso segue o antebraço).
const ARMA_ROT := Vector3(-90, 0, 0)
const ARMA_POS := Vector3(0, 0.06, 0.02)


func _ready() -> void:
	var modelo := (load(MODELO) as PackedScene).instantiate() as Node3D
	modelo.rotation.y = PI   # o modelo olha para +Z; o jogo usa -Z como frente
	add_child(modelo)
	_modelo = modelo
	var esqueletos := modelo.find_children("*", "Skeleton3D", true, false)
	if not esqueletos.is_empty():
		_anexo = BoneAttachment3D.new()
		_anexo.bone_name = "RightHand"
		(esqueletos[0] as Skeleton3D).add_child(_anexo)
	var aps := modelo.find_children("*", "AnimationPlayer", true, false)
	if not aps.is_empty():
		_ap = aps[0]
		_tocar("idle", 1.0)
	if _arma_pedida != 0:
		set_weapon(_arma_pedida)


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


## Mostra a arma (índice ItemDB; 0 = nenhuma) na mão direita.
func set_weapon(indice: int) -> void:
	_arma_pedida = indice
	if indice == _arma_atual or _anexo == null:
		return
	_arma_atual = indice
	for c in _anexo.get_children():
		c.queue_free()
	var id := ItemDB.id_of(indice)
	com_arma = ItemDB.is_weapon(id)
	if com_arma:
		var m := (load("res://assets/armas/%s.glb" % ItemDB.weapon(id)["modelo"]) as PackedScene).instantiate() as Node3D
		m.rotation_degrees = ARMA_ROT
		m.position = ARMA_POS
		_anexo.add_child(m)
	# reescolhe a animação atual com/sem a variante "arma_"
	if _ap and not _atual.is_empty():
		var base := _atual.trim_prefix("arma_")
		_atual = ""
		_tocar(base, _ap.speed_scale)


func _tocar(nome: String, velocidade: float) -> void:
	if com_arma and _ap.has_animation("arma_" + nome):
		nome = "arma_" + nome
	_ap.speed_scale = velocidade
	if nome != _atual and _ap.has_animation(nome):
		_ap.play(nome, MISTURA)
		_atual = nome


func current_animation() -> String:
	return _atual
