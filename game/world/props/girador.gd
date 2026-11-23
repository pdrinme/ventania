class_name Girador
extends Node3D
## Gira continuamente em torno de um eixo local (só visual: hélice do cata-vento,
## etc.). Leve: uma rotação por quadro, sem física.

@export var eixo := Vector3(0, 0, 1)
@export var velocidade := 1.2       # rad/s


func _process(delta: float) -> void:
	rotate_object_local(eixo, velocidade * delta)
