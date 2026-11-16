extends SceneTree
## Verificação visual da picareta e do inventário dentro de uma partida local real.
## 1) Manequins (PawnVisual) congelados em cada fase: repouso, sacar, golpe A
##    (preparação, impacto, continuação) e golpe B, vistos de lado e de frente.
## 2) Na partida: barra com a picareta, golpe na madeira, pedra e metal (partículas)
##    e a tela de inventário com itens próximos.
## Uso: xvfb-run godot --path game --rendering-driver opengl3 --resolution 960x540 -s res://tests/capturar_picareta.gd -- <pasta>

var pasta := ""
var jogo
var cli: GameServer.Cliente
var cam_extra: Camera3D
var manequins: Array = []


func _init() -> void:
	pasta = OS.get_cmdline_user_args()[0]
	await process_frame
	root.theme = VentaniaTheme.build(false)
	await root.get_node("SceneManager").go("game", {"modo": "local"})
	jogo = current_scene
	for i in 150:
		await physics_frame
		if jogo.pawn:
			break
	await _quadros(20)
	cli = jogo.server.clientes.values()[0]
	cam_extra = Camera3D.new()
	cam_extra.fov = 38
	jogo.add_child(cam_extra)

	await _poses()
	await _barra_e_golpes()
	await _tela_inventario()
	print("PICARETA_OK")
	quit()


func _quadros(n: int) -> void:
	for i in n:
		await physics_frame


func _foto(nome: String) -> void:
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png("%s/%s.png" % [pasta, nome])
	print("FOTO ", nome)


## [rótulo, ação, progresso, equip]
const FASES := [
	["repouso", Protocol.ACT_NONE, 0.0, 1.0],
	["sacar", Protocol.ACT_NONE, 0.0, 0.45],
	["A preparação", Protocol.ACT_SWING, 0.30, 1.0],
	["A impacto", Protocol.ACT_SWING, 0.42, 1.0],
	["A continuação", Protocol.ACT_SWING, 0.54, 1.0],
	["B preparação", Protocol.ACT_SWING_B, 0.30, 1.0],
	["B impacto", Protocol.ACT_SWING_B, 0.42, 1.0],
]


func _poses() -> void:
	var base := Vector3(60, 0, 60)
	jogo.pawn.global_position = Vector3(60, 0, 40)
	cli.pawn.global_position = Vector3(60, 0, 40)
	for i in FASES.size():
		var v := PawnVisual.new()
		v.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		jogo.mundo.add_child(v)
		v.global_position = base + Vector3(i * 4.0, 0, 0)
		v.set_held(ItemDB.index_of("picareta"))
		var rotulo := Label3D.new()
		rotulo.text = FASES[i][0]
		rotulo.pixel_size = 0.004
		rotulo.font_size = 40
		rotulo.outline_size = 10
		rotulo.position = Vector3(0, 2.3, 0)
		rotulo.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		v.add_child(rotulo)
		manequins.append(v)
	await _quadros(20)
	for i in FASES.size():
		var v: PawnVisual = manequins[i]
		v.set_process(false)          # congela: a fase vem só daqui
		v.update_state(Vector3.ZERO, Protocol.F_ON_FLOOR, 0.0)
	for frame in 8:
		for i in FASES.size():
			var v: PawnVisual = manequins[i]
			v.rig.equip = FASES[i][3]
			v.rig.sprint = 0.0
			v.set_action(FASES[i][1], FASES[i][2])
		await process_frame
	cam_extra.current = true
	cam_extra.fov = 40
	jogo.combat_hud.visible = false
	jogo.hud.visible = false
	# o personagem olha para -Z e a mão direita fica em +X: 3/4 de frente pela direita e de lado
	for i in FASES.size():
		var v: PawnVisual = manequins[i]
		var alvo := v.global_position + Vector3(0, 1.1, -0.2)
		cam_extra.look_at_from_position(alvo + Vector3(1.9, 0.5, -2.4), alvo, Vector3.UP)
		await _foto("fase_%d_frente" % i)
		cam_extra.look_at_from_position(alvo + Vector3(3.0, 0.3, 0.2), alvo, Vector3.UP)
		await _foto("fase_%d_lado" % i)
	jogo.combat_hud.visible = true
	jogo.hud.visible = true
	for v in manequins:
		v.queue_free()
	manequins.clear()


func _teleportar(pos: Vector3, yaw: float, pitch := -4.0) -> void:
	cli.pawn.global_position = pos
	cli.pawn.velocity = Vector3.ZERO
	jogo.pawn.global_position = pos
	jogo.pawn.velocity = Vector3.ZERO
	jogo.camera.yaw = yaw
	jogo.camera.pitch = pitch
	await _quadros(10)


func _barra_e_golpes() -> void:
	jogo.camera.camera().current = true
	cli.inv = Inventory.new()
	for it in [["rajada", 3], ["trovao", 1], ["curativo", 0, 5]]:
		cli.inv.add_item(it[0], it[1], it[2] if it.size() > 2 else 1)
	cli.inv.add_ammo("media", 90)
	cli.inv.select(Inventory.PICKAXE)
	cli.dirty = true
	await _quadros(15)
	# madeira (cabana), pedra (rampa), metal (caixa)
	for alvo in [["madeira", Vector3(-16.55, 0.1, -10.2), 0.0], ["pedra", Vector3(-0.55, 0.0, -11.5), 0.0], ["metal", Vector3(15.45, 0.1, -10.2), 0.0]]:
		await _teleportar(alvo[1], alvo[2], -6.0)
		Input.action_press("fire")
		# o impacto é no passo melee_impact_step(); fotografa logo depois (partículas no ar)
		await _quadros(Combat.melee_impact_step() + 3)
		await _foto("golpe_" + alvo[0])
		print("IMPACTOS locais=%d confirmados=%d fx=%d" % [jogo.melee_local, jogo.melee_confirmed, jogo.fx.melee_impacts])
		Input.action_release("fire")
		await _quadros(Combat.melee_swing_steps())
	# sequência do golpe vista pela câmera do jogo (a cada 2 passos)
	await _teleportar(Vector3(8, 0.05, 14), 0.0, -6.0)
	Input.action_press("fire")
	for f in 10:
		await _quadros(2)
		await _foto("seq_%02d" % f)
	Input.action_release("fire")
	await _quadros(Combat.melee_swing_steps())
	# HUD: barra com 6 espaços e a picareta selecionada
	await _teleportar(Vector3(4, 0.05, 12), 180.0)
	await _foto("hud_barra_picareta")


func _tela_inventario() -> void:
	cli.inv = Inventory.new()
	for it in [["rajada", 3], ["trovao", 4], ["curativo", 0, 12], ["celula_p", 0, 3], ["gaviao", 5]]:
		cli.inv.add_item(it[0], it[1], it[2] if it.size() > 2 else 1)
	for t in ItemDB.ammo_types():
		cli.inv.add_ammo(t, 45)
	cli.inv.select(0)
	cli.dirty = true
	await _teleportar(Vector3(40, 0.0, 30), 0.0)
	jogo.server.loot.spawn_item("zumbido", 2, 1, -1, Vector3(40.8, 0.0, 29.4))
	jogo.server.loot.spawn_item("kit_cura", 0, 2, -1, Vector3(39.4, 0.0, 29.0))
	await _quadros(12)
	jogo._inventario(true)
	await _quadros(6)
	await _foto("inventario_tela")
	# foco num consumível (detalhes + divisão por quantidade)
	jogo.inventario._tocar_espaco(2)
	jogo.inventario._set_qtd(5)
	await _quadros(3)
	await _foto("inventario_dividir")
	# "Mover": origem marcada
	jogo.inventario._tocar_espaco(0)
	jogo.inventario._mover()
	await _quadros(3)
	await _foto("inventario_mover")
	jogo.inventario._tocar_espaco(4)
	await _quadros(10)
	# foco na picareta: permanente, Largar desativado
	jogo.inventario._tocar_espaco(Inventory.PICKAXE)
	await _quadros(3)
	await _foto("inventario_picareta")
	jogo._inventario(false)
