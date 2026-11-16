class_name PawnVisual
extends Node3D
## Visual do personagem (só no cliente).
## Camadas, nesta ordem, a cada quadro:
##  1. AnimationTree: parado/andar/correr misturados pela velocidade (passadas
##     sincronizadas), agachado, pulo -> queda e aterrissagem (one-shots).
##  2. AimPoseModifier: tronco e cabeça acompanham a mira.
##  3. ItemRig: arma/consumível na pose da categoria + ações (recarga, uso, troca,
##     recuo, alcançar baú) e alvos das mãos nos marcadores do item.
##  4. TwoBoneIK3D (braço direito e esquerdo): mãos presas aos alvos.

const MODELO := "res://assets/personagens/recruta_base_01.glb"
const DURACAO_TROCA := 0.22
const DURACAO_RECUO := 0.18

var _modelo: Node3D
var _sk: Skeleton3D
var _ap: AnimationPlayer
var _tree: AnimationTree
var aim: AimPoseModifier
var rig: ItemRig
var _item_idx := -1
var _item_pedido := 0
var _agachado := 0.0
var _ar := 0.0
var _tempo_no_ar := 0.0
var _no_chao_antes := true
var _vel := Vector3.ZERO
var _flags := Protocol.F_ON_FLOOR
var _flash: MeshInstance3D
var _flash_t := 0.0
var _cano: Node3D                 # marcador "muzzle" da arma atual (ou null)
var _anim_estado := "idle"
var com_arma := false


func _ready() -> void:
	_modelo = (load(MODELO) as PackedScene).instantiate() as Node3D
	_modelo.rotation.y = PI   # o modelo olha para +Z; o jogo usa -Z como frente
	add_child(_modelo)
	_sk = _modelo.find_children("*", "Skeleton3D", true, false)[0]
	_ap = _modelo.find_children("*", "AnimationPlayer", true, false)[0]
	_montar_arvore()
	_montar_modificadores()
	set_held(_item_pedido)


func _montar_arvore() -> void:
	var bt := AnimationNodeBlendTree.new()
	var pe := AnimationNodeBlendSpace1D.new()
	pe.sync = true
	pe.add_blend_point(_anim("idle"), 0.0)
	pe.add_blend_point(_anim("andar"), Movement.WALK_SPEED)
	pe.add_blend_point(_anim("correr"), Movement.SPRINT_SPEED)
	pe.min_space = 0.0
	pe.max_space = Movement.SPRINT_SPEED
	var ag := AnimationNodeBlendSpace1D.new()
	ag.sync = true
	ag.add_blend_point(_anim("agachado"), 0.0)
	ag.add_blend_point(_anim("agachado_andar"), Movement.CROUCH_SPEED)
	ag.min_space = 0.0
	ag.max_space = Movement.CROUCH_SPEED
	var salto := AnimationNodeOneShot.new()
	salto.fadein_time = 0.05
	salto.fadeout_time = 0.25
	var aterr := AnimationNodeOneShot.new()
	aterr.fadein_time = 0.04
	aterr.fadeout_time = 0.22
	var acenar := AnimationNodeOneShot.new()
	acenar.fadein_time = 0.2
	acenar.fadeout_time = 0.3
	bt.add_node("pe", pe)
	bt.add_node("ag", ag)
	bt.add_node("agachar", AnimationNodeBlend2.new())
	bt.add_node("queda", _anim("queda"))
	bt.add_node("pular", _anim("pular"))
	bt.add_node("salto", salto)
	bt.add_node("solo_ar", AnimationNodeBlend2.new())
	bt.add_node("aterrissar_anim", _anim("aterrissar"))
	bt.add_node("aterrissar", aterr)
	bt.add_node("acenar_anim", _anim("acenar"))
	bt.add_node("acenar", acenar)
	bt.connect_node("agachar", 0, "pe")
	bt.connect_node("agachar", 1, "ag")
	bt.connect_node("salto", 0, "queda")
	bt.connect_node("salto", 1, "pular")
	bt.connect_node("solo_ar", 0, "agachar")
	bt.connect_node("solo_ar", 1, "salto")
	bt.connect_node("aterrissar", 0, "solo_ar")
	bt.connect_node("aterrissar", 1, "aterrissar_anim")
	bt.connect_node("acenar", 0, "aterrissar")
	bt.connect_node("acenar", 1, "acenar_anim")
	bt.connect_node("output", 0, "acenar")
	_tree = AnimationTree.new()
	_modelo.add_child(_tree)
	_tree.anim_player = _tree.get_path_to(_ap)
	_tree.tree_root = bt
	_tree.active = true


func _anim(nome: String) -> AnimationNodeAnimation:
	var a := AnimationNodeAnimation.new()
	a.animation = nome
	return a


func _montar_modificadores() -> void:
	aim = AimPoseModifier.new()
	_sk.add_child(aim)
	rig = ItemRig.new()
	rig.aim = aim
	_sk.add_child(rig)
	rig.holder = Node3D.new()
	rig.holder.name = "Item"
	_sk.add_child(rig.holder)
	for n in ["alvo_d", "alvo_e", "polo_d", "polo_e"]:
		var no := Node3D.new()
		no.name = n
		_sk.add_child(no)
		rig.set(n, no)
	rig.ik_d = _ik("Right", rig.alvo_d, rig.polo_d)
	rig.ik_e = _ik("Left", rig.alvo_e, rig.polo_e)
	_flash = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.22, 0.22)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_texture = _textura_clarao()
	q.material = m
	_flash.mesh = q
	_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flash.visible = false
	# SEMPRE na árvore (filho do personagem). Um nó visual fora da árvore nunca é
	# liberado e deixa uma instância no RenderingServer depois que o mundo 3D some:
	# era o que derrubava a build de release ao fechar o jogo.
	_flash.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_flash)


func _ik(lado: String, alvo: Node3D, polo: Node3D) -> TwoBoneIK3D:
	var ik := TwoBoneIK3D.new()
	ik.setting_count = 1
	_sk.add_child(ik)
	ik.set("settings/0/root_bone_name", lado + "UpperArm")
	ik.set("settings/0/middle_bone_name", lado + "LowerArm")
	ik.set("settings/0/end_bone_name", lado + "Hand")
	ik.set("settings/0/target_node", ik.get_path_to(alvo))
	ik.set("settings/0/pole_node", ik.get_path_to(polo))
	# o "fim" é o centro da mão (luva), não o pulso
	ik.set("settings/0/extend_end_bone", true)
	ik.set("settings/0/end_bone/length", 0.065)
	ik.influence = 0.0
	ik.active = false
	return ik


static func _textura_clarao() -> ImageTexture:
	var n := 32
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var c := (n - 1) / 2.0
	for y in n:
		for x in n:
			var d := Vector2(x - c, y - c)
			var r := d.length() / c
			var raios := absf(cos(d.angle() * 3.0)) * 0.5 + 0.5
			var a := clampf((1.0 - r) * raios * 1.6, 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 0.85, 0.4, a))
	return ImageTexture.create_from_image(img)


# ---------------- API ----------------

## Item na mão (índice ItemDB; 0 = nenhum). Trocar dispara a animação de sacar.
func set_held(indice: int) -> void:
	_item_pedido = indice
	if _sk == null or indice == _item_idx:
		return
	_item_idx = indice
	if rig.item_node:
		rig.item_node.queue_free()
		rig.item_node = null
	_cano = null
	_flash.visible = false
	var id := ItemDB.id_of(indice)
	rig.item = id
	com_arma = ItemDB.is_weapon(id)
	var caminho := ""
	if com_arma:
		caminho = "res://assets/armas/%s.glb" % ItemDB.weapon(id)["modelo"]
	elif ItemDB.is_consumable(id):
		caminho = "res://assets/baus_coletaveis/%s.glb" % ItemDB.consumable(id)["modelo"]
	if not caminho.is_empty():
		rig.item_node = (load(caminho) as PackedScene).instantiate() as Node3D
		rig.holder.add_child(rig.item_node)
		_cano = rig.item_node.find_child("muzzle", true, false) as Node3D
	rig.equip = 0.0


## Compatibilidade com o código antigo.
func set_weapon(indice: int) -> void:
	set_held(indice)


func set_aim(pitch: float, mirando: bool) -> void:
	aim.pitch = lerp_angle(aim.pitch, clampf(pitch, deg_to_rad(-70), deg_to_rad(70)), 0.5)
	rig.pitch = aim.pitch
	rig.ads = move_toward(rig.ads, 1.0 if mirando else 0.0, get_process_delta_time() * 7.0)


func set_action(acao: int, progresso: float) -> void:
	rig.action = acao
	rig.progress = clampf(progresso, 0.0, 1.0)


## Alcança um ponto do mundo (ex.: alça da tampa do baú). peso 0 = soltar.
func set_reach(ponto_mundo: Vector3, peso: float) -> void:
	rig.reach_pos = _sk.global_transform.affine_inverse() * ponto_mundo
	rig.reach_w = move_toward(rig.reach_w, peso, get_process_delta_time() * 4.0)


func fire() -> void:
	var cat := ItemRig.categoria(rig.item)
	rig.recoil = minf(rig.recoil + (1.4 if rig.item == "trovao" or rig.item == "gaviao" else 0.7), 2.0)
	if _cano:
		_flash.global_position = _cano.global_position
		_flash.visible = true
		_flash.rotation.z = randf() * TAU
		_flash.scale = Vector3.ONE * (1.6 if cat == ItemRig.Cat.RIFLE and rig.item == "trovao" else randf_range(0.8, 1.2))
		_flash_t = 0.05


func wave() -> void:
	_tree.set("parameters/acenar/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


## velocidade (m/s, mundo), flags Protocol.F_*, yaw (rad).
func update_state(velocidade: Vector3, flags: int, yaw: float) -> void:
	rotation.y = yaw
	_vel = velocidade
	_flags = flags
	set_crouched(flags & Protocol.F_CROUCHED != 0)


func _process(delta: float) -> void:
	if _tree == null:
		return
	var h := Vector2(_vel.x, _vel.z).length()
	var flags_chao := _flags & Protocol.F_ON_FLOOR != 0
	_ar = move_toward(_ar, 0.0 if flags_chao else 1.0, delta * 7.0)
	if not flags_chao:
		_tempo_no_ar += delta
	# decolou: dispara o pulo
	if _no_chao_antes and _vel.y > 2.0:
		_tree.set("parameters/salto/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	# pousou depois de um tempo no ar: amortece
	if not _no_chao_antes and flags_chao and _tempo_no_ar > 0.35:
		_tree.set("parameters/aterrissar/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	if flags_chao:
		_tempo_no_ar = 0.0
	_no_chao_antes = flags_chao
	_tree.set("parameters/pe/blend_position", h)
	_tree.set("parameters/ag/blend_position", h)
	_tree.set("parameters/agachar/blend_amount", _agachado)
	_tree.set("parameters/solo_ar/blend_amount", _ar)
	rig.sprint = move_toward(rig.sprint, 1.0 if h > Movement.WALK_SPEED + 0.6 and rig.ads < 0.1 else 0.0, delta * 5.0)
	rig.equip = move_toward(rig.equip, 1.0, delta / DURACAO_TROCA)
	rig.recoil = move_toward(rig.recoil, 0.0, delta / DURACAO_RECUO * maxf(rig.recoil, 0.3))
	if _flash_t > 0.0:
		if _cano:
			_flash.global_position = _cano.global_position
		_flash_t -= delta
		if _flash_t <= 0.0:
			_flash.visible = false
	_anim_estado = _estado(h)


func set_crouched(v: bool) -> void:
	_agachado = move_toward(_agachado, 1.0 if v else 0.0, get_process_delta_time() * 8.0)


func _estado(h: float) -> String:
	if _ar > 0.5:
		return "no_ar"
	if _agachado > 0.5:
		return "agachado_andar" if h > 0.3 else "agachado"
	if h > 5.2:
		return "correr"
	return "andar" if h > 0.3 else "idle"


## Nome do estado de locomoção atual (testes/diagnóstico).
func current_animation() -> String:
	return ("arma_" if com_arma else "") + _anim_estado
