class_name ItemRig
extends SkeletonModifier3D
## Posiciona o item na mão (arma ou consumível) e os ALVOS das mãos para o IK.
## Roda depois da animação e do AimPoseModifier e antes dos dois TwoBoneIK3D:
## o item é colocado primeiro (pose da categoria + ações procedurais) e as mãos são
## puxadas até os marcadores reais do modelo (grip_r, grip_l, mag, mao). Assim a
## arma nunca fica solta: são as mãos que seguem a arma.
##
## Espaço do esqueleto: frente = +Z, esquerda = +X, cima = +Y.
## Espaço de mira (offsets abaixo): x = esquerda, y = cima, z = frente.

enum Cat { NENHUM, RIFLE, PRECISAO, PISTOLA, CONSUMIVEL }

## Poses por categoria: posição do grip_r relativa aos ombros (no espaço de mira).
## Armas longas junto ao corpo (coronha no ombro direito): com o braço curto do
## personagem (~0,58 m do ombro ao centro da mão), o guarda-mão precisa ficar a
## no máximo ~0,56 m do ombro esquerdo para a mão esquerda alcançá-lo.
const POSES := {
	Cat.RIFLE: {"quadril": Vector3(-0.11, -0.10, 0.12), "mira": Vector3(-0.07, 0.03, 0.13)},
	Cat.PRECISAO: {"quadril": Vector3(-0.11, -0.10, 0.08), "mira": Vector3(-0.07, -0.04, 0.10)},
	Cat.PISTOLA: {"quadril": Vector3(-0.06, -0.06, 0.40), "mira": Vector3(-0.03, 0.03, 0.44)},
}
const OMBROS := Vector3(0, 0.12, 0.0)        # acima da origem do osso Chest
const BOLSO := Vector3(0.20, -0.50, 0.10)    # onde a mão esquerda "pega" munição (quadril esquerdo)
const POLO_D := Vector3(-0.65, -0.55, -0.15)
const POLO_E := Vector3(0.65, -0.55, -0.05)

# --- estado definido pelo PawnVisual a cada quadro ---
var item := ""                 # id ItemDB
var item_node: Node3D          # modelo instanciado (filho de holder)
var pitch := 0.0
var ads := 0.0                 # 0..1 mirando
var sprint := 0.0              # 0..1 correndo
var recoil := 0.0              # 0..1+ (decai)
var equip := 1.0               # 0..1 progresso de sacar
var action := Protocol.ACT_NONE
var progress := 0.0            # 0..1 da ação
var reach_pos := Vector3.ZERO  # alvo do alcance (espaço do esqueleto)
var reach_w := 0.0             # 0..1

# --- nós (filhos do Skeleton3D) ---
var holder: Node3D
var alvo_d: Node3D
var alvo_e: Node3D
var polo_d: Node3D
var polo_e: Node3D
var ik_d: TwoBoneIK3D
var ik_e: TwoBoneIK3D
var aim: AimPoseModifier

var _chest := -1
var _head := -1
var _w_d := 0.0
var _w_e := 0.0
var _abaixar := 0.0                # 0..1 arma abaixada (corrida/alcance)


static func categoria(id: String) -> int:
	if ItemDB.is_consumable(id):
		return Cat.CONSUMIVEL
	if not ItemDB.is_weapon(id):
		return Cat.NENHUM
	match String(ItemDB.weapon(id).get("tipo", "")):
		"Pistola":
			return Cat.PISTOLA
		"Rifle de Precisão":
			return Cat.PRECISAO
	return Cat.RIFLE


func _marcador(nome: String) -> Transform3D:
	if item_node == null:
		return Transform3D()
	var m := item_node.find_child(nome, true, false) as Node3D
	return item_node.global_transform.affine_inverse() * m.global_transform if m else Transform3D()


static func _suave(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## Interpola uma trilha de chaves [[t, valor], ...] (t crescente) com suavização.
static func _trilha(chaves: Array, t: float) -> Variant:
	if t <= chaves[0][0]:
		return chaves[0][1]
	for i in range(chaves.size() - 1):
		var a: Array = chaves[i]
		var b: Array = chaves[i + 1]
		if t <= b[0]:
			var k := _suave((t - a[0]) / maxf(0.0001, b[0] - a[0]))
			return a[1].lerp(b[1], k) if a[1] is Vector3 else lerpf(a[1], b[1], k)
	return chaves[-1][1]


## "Sobe, fica, desce" em 0..1 (para entrar/sair de uma ação suavemente).
static func _envelope(p: float, entrada := 0.12, saida := 0.12) -> float:
	return _suave(p / entrada) * _suave((1.0 - p) / saida)


func _process_modification_with_delta(delta: float) -> void:
	var sk := get_skeleton()
	if sk == null or holder == null:
		return
	if _chest < 0:
		_chest = sk.find_bone("Chest")
		_head = sk.find_bone("Head")
	var cat := categoria(item)
	var chest := sk.get_bone_global_pose(_chest)
	var ombros := chest.origin + OMBROS
	var mira := Basis(Vector3.RIGHT, -pitch)
	var alvo_dw := 0.0
	var alvo_ew := 0.0
	aim.head_extra = move_toward(aim.head_extra, 0.0, delta * 2.0)

	# arma abaixada ao correr ou enquanto a mão esquerda alcança algo
	var quer_abaixar := maxf(sprint, reach_w if cat != Cat.CONSUMIVEL else 0.0)
	_abaixar = move_toward(_abaixar, quer_abaixar, delta * 5.0)

	if cat == Cat.RIFLE or cat == Cat.PRECISAO or cat == Cat.PISTOLA:
		var pose: Dictionary = POSES[cat]
		var off: Vector3 = (pose["quadril"] as Vector3).lerp(pose["mira"], ads)
		var rot := Basis()
		# corrida/alcance: "pronto baixo" (cano para baixo e para dentro)
		off = off.lerp(Vector3(-0.10, -0.24, 0.20), _abaixar)
		rot = Basis(Vector3.UP, deg_to_rad(28.0) * _abaixar) * Basis(Vector3.RIGHT, deg_to_rad(42.0) * _abaixar)
		# sacar: sobe de baixo
		var e := _suave(equip)
		off += Vector3(0, -0.32, -0.05) * (1.0 - e)
		rot = rot * Basis(Vector3.RIGHT, deg_to_rad(65.0) * (1.0 - e))
		# recuo: para trás e cano para cima
		off += Vector3(0, 0.015, -0.06) * recoil
		rot = rot * Basis(Vector3.RIGHT, -deg_to_rad(9.0) * recoil)
		aim.chest_kick = -0.05 * recoil
		# recarga: arma inclinada (gira no próprio eixo e levanta a boca)
		var r_w := _envelope(progress, 0.12, 0.14) if action == Protocol.ACT_RELOAD else 0.0
		off += Vector3(0.06, -0.07, -0.07) * r_w
		rot = rot * Basis(Vector3.FORWARD, deg_to_rad(-36.0) * r_w) * Basis(Vector3.RIGHT, -deg_to_rad(18.0) * r_w)
		var grip := ombros + mira * off
		var base := mira * rot
		var g_r := _marcador("grip_r")
		holder.transform = Transform3D(base, grip) * g_r.affine_inverse()
		alvo_d.transform = holder.transform * g_r
		alvo_dw = 1.0
		# mão esquerda: no guarda-mão; na recarga, vai ao carregador e ao bolso
		var gl := holder.transform * _marcador("grip_l").origin
		var mag := holder.transform * _marcador("mag").origin
		var bolso := chest.origin + BOLSO
		var mao_e := gl
		if action == Protocol.ACT_RELOAD:
			mao_e = _mao_recarga(cat, progress, gl, mag, bolso, base)
		if reach_w > 0.0:
			mao_e = mao_e.lerp(reach_pos, reach_w)
		alvo_e.transform = Transform3D(Basis(), mao_e)
		alvo_ew = 1.0
	elif cat == Cat.CONSUMIVEL:
		_consumivel(sk, chest, ombros, delta)
		alvo_dw = 1.0
		alvo_ew = _w_e_consumivel
	else:
		aim.chest_kick = 0.0
		holder.transform = Transform3D(Basis(), chest.origin)
		# sem item: a mão direita alcança (baú/item) quando pedido
		if reach_w > 0.0:
			alvo_d.transform = Transform3D(Basis(), reach_pos)
			alvo_dw = reach_w

	polo_d.transform = Transform3D(Basis(), chest.origin + POLO_D)
	polo_e.transform = Transform3D(Basis(), chest.origin + POLO_E)
	_w_d = move_toward(_w_d, alvo_dw, delta * 8.0)
	_w_e = move_toward(_w_e, alvo_ew, delta * 8.0)
	ik_d.influence = _w_d
	ik_e.influence = _w_e
	ik_d.active = _w_d > 0.001
	ik_e.active = _w_e > 0.001


func _mao_recarga(cat: int, p: float, gl: Vector3, mag: Vector3, bolso: Vector3, base: Basis) -> Vector3:
	var baixo := base * Vector3(0, -0.12, 0)
	if cat == Cat.PISTOLA:
		return _trilha([[0.0, gl], [0.18, mag], [0.32, mag + baixo], [0.45, bolso], [0.6, bolso], [0.76, mag + baixo], [0.86, mag], [1.0, gl]], p)
	if item == "trovao":
		# espingarda: 3 cartuchos (bolso -> entrada) e depois a bomba
		var porta := mag + base * Vector3(0, -0.03, 0)
		var trilha := [[0.0, gl]]
		for i in 3:
			var t0 := 0.06 + i * 0.24
			trilha.append([t0 + 0.06, bolso])
			trilha.append([t0 + 0.16, porta])
		trilha.append([0.84, gl])
		trilha.append([0.91, gl + base * Vector3(0, 0, -0.12)])   # puxa a bomba
		trilha.append([1.0, gl])
		return _trilha(trilha, p)
	# carregador: tira, guarda, pega outro, encaixa, bate na lateral, volta
	return _trilha([[0.0, gl], [0.14, mag], [0.28, mag + baixo], [0.42, bolso], [0.55, bolso], [0.68, mag + baixo],
			[0.78, mag], [0.86, mag + base * Vector3(0.06, 0.06, 0.02)], [1.0, gl]], p)


var _w_e_consumivel := 0.0


func _consumivel(sk: Skeleton3D, chest: Transform3D, ombros: Vector3, delta: float) -> void:
	var usando := action == Protocol.ACT_USE
	var p := progress if usando else 0.0
	var env := _envelope(p, 0.15, 0.1) if usando else 0.0
	var mao_m := _marcador("mao")
	# segurando (sem usar): na frente do quadril direito
	var pos_seg := chest.origin + Vector3(-0.20, -0.36, 0.24)
	var rot_seg := Basis(Vector3.RIGHT, deg_to_rad(-20.0))
	var pos := pos_seg
	var rot := rot_seg
	_w_e_consumivel = 0.0
	match item:
		"celula_p", "celula_g":
			# beber: leva à boca, inclina o frasco e a cabeça
			var cabeca := sk.get_bone_global_pose(_head).origin
			var boca := cabeca + Vector3(-0.02, -0.06, 0.17)
			var gole := sin(p * TAU * 3.0) * 0.5 + 0.5
			pos = pos_seg.lerp(boca, env)
			rot = rot_seg.slerp(Basis(Vector3.RIGHT, deg_to_rad(-70.0 - 20.0 * gole)), env)
			aim.head_extra = deg_to_rad(18.0 + 8.0 * gole) * env
		"curativo":
			# enrola a atadura no antebraço esquerdo: mão direita circula, esquerda parada
			var centro := chest.origin + Vector3(0.06, -0.12, 0.30)
			var ang := p * TAU * 5.0
			var circulo := centro + Vector3(cos(ang) * 0.07, sin(ang) * 0.07, -0.02)
			pos = pos_seg.lerp(circulo, env)
			rot = rot_seg.slerp(Basis(Vector3.UP, ang * 0.3), env)
			alvo_e.transform = Transform3D(Basis(), centro + Vector3(0.10, -0.03, 0.02))
			_w_e_consumivel = env
		"kit_cura":
			# abre a maleta à frente do peito e aplica com toques
			var frente := chest.origin + Vector3(0.0, -0.18, 0.32)
			var toque := absf(sin(p * TAU * 6.0)) * 0.05
			pos = pos_seg.lerp(frente, env)
			rot = rot_seg.slerp(Basis(), env)
			alvo_e.transform = Transform3D(Basis(), frente + Vector3(0.14, 0.06 + toque, 0.02))
			_w_e_consumivel = env
	# sacar o consumível também sobe de baixo
	var e := _suave(equip)
	pos += Vector3(0, -0.25, 0) * (1.0 - e)
	holder.transform = Transform3D(rot, pos) * mao_m.affine_inverse()
	alvo_d.transform = holder.transform * mao_m
	aim.chest_kick = 0.0
