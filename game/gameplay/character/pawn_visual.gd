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

const MODELO := "res://assets/personagens/recruta_base_01.glb"   # traje padrão (ver Cosmeticos)
const DURACAO_TROCA := 0.22
const DURACAO_GUARDAR := 0.12      # guarda o item atual antes de sacar o próximo
const DURACAO_RECUO := 0.18

var _modelo: Node3D
var _sk: Skeleton3D
var _ap: AnimationPlayer
var _tree: AnimationTree
var aim: AimPoseModifier
var rig: ItemRig
var _item_idx := -1
var _item_pedido := 0
var _guardando := false            # guardando o item antigo (equip 1 -> 0) antes de trocar
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
var queda := 0                    # Pawn.QUEDA_LIVRE / PLANADOR / NO_ONIBUS
var _planador: Node3D
var planador_id := ""             # planador cosmético equipado (vazio = padrão)
var preparando := false           # agachado na porta do ônibus (só o próprio jogador)
var _w_entrada := 0.0             # 0 = locomoção normal, 1 = poses de entrada (ar/ônibus)
var _w_mergulho := 0.0
var _w_planador := 0.0
var _w_preparar := 0.0
var _inclinacao := Basis()        # orientação procedural do corpo no ar (deitado, mergulho, curvas)
var _t_ar := 0.0
var _yaw_ant := 0.0
var _vel_ant := Vector3.ZERO
var _giro := 0.0                  # velocidade de giro suavizada (rad/s) para inclinar nas curvas
var _acel := 0.0                  # aceleração para a frente suavizada (m/s²)
var traje := ""                   # id do traje equipado (defina antes de entrar na árvore)
var picareta_id := ""             # picareta cosmética (mesmos marcadores; gameplay igual)
var fx: TrajeFx                   # efeito do traje (ex.: aquário), se houver


func _ready() -> void:
	_modelo = (load(Cosmeticos.outfit_scene(traje)) as PackedScene).instantiate() as Node3D
	_modelo.rotation.y = PI   # o modelo olha para +Z; o jogo usa -Z como frente
	add_child(_modelo)
	fx = TrajeFx.attach(_modelo, traje)
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
	# entrada na partida (Ônibus de Batalha): ver set_fall e _entrada
	var saltar := AnimationNodeOneShot.new()
	saltar.fadein_time = 0.04
	saltar.fadeout_time = 0.3
	var abrir := AnimationNodeOneShot.new()
	abrir.fadein_time = 0.06
	abrir.fadeout_time = 0.2
	var pesado := AnimationNodeOneShot.new()
	pesado.fadein_time = 0.03
	pesado.fadeout_time = 0.25
	bt.add_node("queda_livre", _anim("queda_livre"))
	bt.add_node("mergulho", _anim("mergulho"))
	bt.add_node("ar", AnimationNodeBlend2.new())
	bt.add_node("saltar_anim", _anim("saltar"))
	bt.add_node("saltar", saltar)
	bt.add_node("planador_anim", _anim("planador"))
	bt.add_node("abrir_anim", _anim("planador_abrir"))
	bt.add_node("abrir", abrir)
	bt.add_node("plan", AnimationNodeBlend2.new())
	bt.add_node("preparar_anim", _anim("preparar"))
	bt.add_node("prep", AnimationNodeBlend2.new())
	bt.add_node("entrada", AnimationNodeBlend2.new())
	bt.add_node("pesado_anim", _anim("aterrissar_pesado"))
	bt.add_node("pesado", pesado)
	bt.connect_node("ar", 0, "queda_livre")
	bt.connect_node("ar", 1, "mergulho")
	bt.connect_node("saltar", 0, "ar")
	bt.connect_node("saltar", 1, "saltar_anim")
	bt.connect_node("abrir", 0, "planador_anim")
	bt.connect_node("abrir", 1, "abrir_anim")
	bt.connect_node("plan", 0, "saltar")
	bt.connect_node("plan", 1, "abrir")
	bt.connect_node("prep", 0, "plan")
	bt.connect_node("prep", 1, "preparar_anim")
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
	bt.connect_node("pesado", 0, "acenar")
	bt.connect_node("pesado", 1, "pesado_anim")
	bt.connect_node("entrada", 0, "pesado")
	bt.connect_node("entrada", 1, "prep")
	bt.connect_node("output", 0, "entrada")
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

## Item na mão (índice ItemDB; 0 = nenhum). Trocar primeiro GUARDA o item atual
## (equip 1 -> 0, DURACAO_GUARDAR) e só então saca o novo (equip 0 -> 1).
func set_held(indice: int) -> void:
	_item_pedido = indice
	if _sk == null or indice == _item_idx:
		_guardando = false
		return
	if rig.item_node and _item_idx > 0 and not _guardando and rig.equip > 0.05:
		_guardando = true
		return
	if _guardando and rig.equip > 0.0:
		return
	_trocar_modelo(indice)


func _trocar_modelo(indice: int) -> void:
	_guardando = false
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
	elif id == Inventory.PICKAXE_ID:
		caminho = Cosmeticos.pickaxe_scene(picareta_id)        # picareta cosmética: só o visual muda
	elif ItemDB.is_tool_item(id):
		caminho = "res://assets/armas/%s.glb" % ItemDB.tool_def(id)["modelo"]
	elif ItemDB.is_consumable(id):
		caminho = "res://assets/baus_coletaveis/%s.glb" % ItemDB.consumable(id)["modelo"]
	if not caminho.is_empty():
		rig.item_node = (load(caminho) as PackedScene).instantiate() as Node3D
		rig.holder.add_child(rig.item_node)
		_cano = rig.item_node.find_child("muzzle", true, false) as Node3D
	rig.equip = 0.0


## Item que está de fato na mão agora (pode estar guardando o anterior).
func held_index() -> int:
	return _item_idx


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


## Ponta da picareta no mundo (ou Vector3.INF se não estiver na mão).
func pickaxe_tip() -> Vector3:
	if not ItemDB.is_tool_item(rig.item) or rig.item_node == null:
		return Vector3.INF
	return _sk.global_transform * rig.pickaxe_tip()


## Posição do cano da arma na mão (origem dos traçantes); sem arma, à frente do peito.
func muzzle_position() -> Vector3:
	if _cano and is_instance_valid(_cano):
		return _cano.global_position
	return global_transform * Vector3(-0.2, 1.35, -0.4)


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
	if _guardando:
		rig.equip = move_toward(rig.equip, 0.0, delta / DURACAO_GUARDAR)
		if rig.equip <= 0.0:
			_trocar_modelo(_item_pedido)
	else:
		rig.equip = move_toward(rig.equip, 1.0, delta / DURACAO_TROCA)
	rig.recoil = move_toward(rig.recoil, 0.0, delta / DURACAO_RECUO * maxf(rig.recoil, 0.3))
	if _flash_t > 0.0:
		if _cano:
			_flash.global_position = _cano.global_position
		_flash_t -= delta
		if _flash_t <= 0.0:
			_flash.visible = false
	_anim_estado = _estado(h)
	_entrada(delta)
	if fx:
		fx.velocidade = Basis(Vector3.UP, rotation.y).inverse() * _vel


## Pose de entrada a partir do que vem pela rede (estado de queda e velocidade).
## Função pura: usada pelo visual e pelos testes.
static func fall_pose(q: int, vel: Vector3) -> String:
	match q:
		Pawn.NO_ONIBUS:
			return "onibus"
		Pawn.QUEDA_LIVRE:
			return "mergulho" if -vel.y > Movement.QUEDA_TERMINAL + 2.0 else "queda_livre"
		Pawn.PLANADOR:
			return "planador"
	return "chao"


## Orientação do corpo no ar (função pura, testável): deitado de bruços na queda
## livre, de cabeça para baixo no mergulho, quase em pé no planador; inclina nas
## curvas (roll) conforme a velocidade lateral. Retorna (deitar, rolar) em radianos.
static func air_tilt(pose: String, vel_local: Vector3, mergulho: float) -> Vector2:
	var lado := clampf(vel_local.x / Movement.QUEDA_HORIZONTAL, -1.0, 1.0)
	var frente := clampf(-vel_local.z / Movement.QUEDA_HORIZONTAL, -1.0, 1.0)
	if pose == "queda_livre" or pose == "mergulho":
		return Vector2(lerpf(deg_to_rad(72.0 + 10.0 * frente), deg_to_rad(158.0), mergulho), -lado * deg_to_rad(28.0))
	if pose == "planador":
		return Vector2(deg_to_rad(6.0 + 8.0 * frente), -lado * deg_to_rad(20.0))
	return Vector2.ZERO


## Inclinação no chão (função pura): (frente, lado) em radianos. Curva rápida
## correndo inclina para dentro; arrancada inclina para a frente, freada para trás.
static func ground_lean(vel_h: float, giro: float, acel: float) -> Vector2:
	var lado := clampf(giro * vel_h * 0.028, -0.2, 0.2)          # até ~11°
	var frente := clampf(acel * 0.006, -0.1, 0.12)               # até ~7°
	return Vector2(frente, lado)


func _entrada(delta: float) -> void:
	var pose := fall_pose(queda, _vel)
	var no_ar := queda == Pawn.QUEDA_LIVRE or queda == Pawn.PLANADOR
	_w_entrada = move_toward(_w_entrada, 1.0 if (no_ar or preparando) else 0.0, delta * (6.0 if no_ar or preparando else 3.0))
	_w_mergulho = move_toward(_w_mergulho, 1.0 if pose == "mergulho" else 0.0, delta * 2.5)
	_w_planador = move_toward(_w_planador, 1.0 if pose == "planador" else 0.0, delta * 5.0)
	_w_preparar = move_toward(_w_preparar, 1.0 if preparando and not no_ar else 0.0, delta * 6.0)
	_tree.set("parameters/entrada/blend_amount", _w_entrada)
	_tree.set("parameters/ar/blend_amount", _w_mergulho)
	_tree.set("parameters/plan/blend_amount", _w_planador)
	_tree.set("parameters/prep/blend_amount", _w_preparar)
	_t_ar += delta
	var local := Basis(Vector3.UP, rotation.y).inverse() * _vel      # frente = -Z
	var inc := air_tilt(pose, local, _w_mergulho)
	var osc := 0.0
	if pose != "chao" and pose != "onibus":
		osc = sin(_t_ar * (2.3 if pose != "planador" else 1.7)) * deg_to_rad(3.0 if pose != "planador" else 2.0)
	if pose == "chao" and delta > 0.0:
		# no chão: peso nas curvas (inclina para dentro) e nas arrancadas/freadas
		var giro := wrapf(rotation.y - _yaw_ant, -PI, PI) / delta
		_giro = lerpf(_giro, clampf(giro, -8.0, 8.0), clampf(delta * 8.0, 0.0, 1.0))
		var frente := -(Basis(Vector3.UP, rotation.y).z)
		var a := (_vel - _vel_ant).dot(frente) / delta
		_acel = lerpf(_acel, clampf(a, -30.0, 30.0), clampf(delta * 6.0, 0.0, 1.0))
		inc += ground_lean(Vector2(_vel.x, _vel.z).length(), _giro, _acel)
	_yaw_ant = rotation.y
	_vel_ant = _vel
	var alvo := Basis(Vector3(1, 0, 0), -inc.x) * Basis(Vector3(0, 0, 1), inc.y + osc)
	_inclinacao = _inclinacao.slerp(alvo, clampf(delta * 5.0, 0.0, 1.0)).orthonormalized()
	# no ar gira em torno do centro do corpo (~1 m); no chão, em torno dos pés
	var centro := Vector3(0, 1.0 * _w_entrada, 0)
	var t := Transform3D(_inclinacao, centro - _inclinacao * centro)
	_modelo.transform = t * Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)


## Entrada na partida: no ônibus (invisível), queda livre (sem item na mão) e
## planador (asa delta sobre a cabeça).
func set_fall(q: int) -> void:
	if q == queda or _sk == null:
		return
	var antes := queda
	queda = q
	rig.holder.visible = q == 0
	# transições viram animações de uma vez (para os outros jogadores também: vêm do estado replicado)
	if antes == Pawn.NO_ONIBUS and q == Pawn.QUEDA_LIVRE:
		_tree.set("parameters/saltar/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	if q == Pawn.PLANADOR:
		_tree.set("parameters/abrir/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	if q == 0 and (antes == Pawn.PLANADOR or antes == Pawn.QUEDA_LIVRE):
		_tree.set("parameters/pesado/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
		_w_entrada = 0.0          # a aterrissagem aparece na hora (sem esperar a pose do ar sumir)
		_inclinacao = Basis()
	if q == Pawn.PLANADOR and _planador == null:
		_planador = (load(Cosmeticos.glider_scene(planador_id)) as PackedScene).instantiate() as Node3D
		_modelo.add_child(_planador)           # dentro do modelo: acompanha a inclinação do corpo
	if _planador:
		_planador.visible = q == Pawn.PLANADOR
		if q == Pawn.PLANADOR:
			# abre da mochila: sobe e cresce com um leve "estalo"
			_planador.position = Vector3(0, 1.45, -0.25)
			_planador.scale = Vector3.ONE * 0.08
			var tw := _planador.create_tween().set_parallel()
			tw.tween_property(_planador, "position", Vector3(0, 2.45, 0), 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_property(_planador, "scale", Vector3.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if q == Pawn.PLANADOR:
		# segura a barra do planador com as duas mãos
		set_reach(global_position + Vector3(0, 1.45, 0), 1.0)


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
