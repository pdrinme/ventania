class_name AimPoseModifier
extends SkeletonModifier3D
## Inclina coluna, peito, pescoço e cabeça para onde o jogador mira (para cima/baixo),
## somando ao que a animação de locomoção já faz. Também aplica o "tranco" do recuo
## no peito e a inclinação extra da cabeça (ex.: beber uma célula de escudo).
## Espaço do esqueleto: frente = +Z, esquerda = +X, cima = +Y.

const PESOS := {"Spine": 0.22, "Chest": 0.33, "Neck": 0.17, "Head": 0.28}

var pitch := 0.0          # rad, positivo = olhando para cima
var head_extra := 0.0     # rad, inclinação extra da cabeça para trás
var chest_kick := 0.0     # rad, recuo do disparo
var _idx := {}


func _process_modification_with_delta(_delta: float) -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	if _idx.is_empty():
		for nome in PESOS:
			_idx[nome] = sk.find_bone(nome)
	for nome in PESOS:
		var b: int = _idx[nome]
		if b < 0:
			continue
		var ang: float = pitch * PESOS[nome]
		if nome == "Head":
			ang += head_extra
		elif nome == "Chest":
			ang += chest_kick
		if absf(ang) < 0.0005:
			continue
		var g := sk.get_bone_global_pose(b)
		var pai := sk.get_bone_parent(b)
		var pg := sk.get_bone_global_pose(pai) if pai >= 0 else Transform3D()
		var r := Basis(Vector3.RIGHT, -ang)          # +ang levanta a frente (+Z) para +Y
		var local := pg.basis.orthonormalized().inverse() * (r * g.basis.orthonormalized())
		sk.set_bone_pose_rotation(b, local.get_rotation_quaternion())
