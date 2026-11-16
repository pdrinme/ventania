extends SceneTree
## Verificação visual dos traçantes e impactos numa partida local real (xvfb-run).
## Uso: godot --path game --rendering-driver opengl3 --resolution 960x540 -s res://tests/capturar_tracantes.gd -- <pasta>

var pasta := ""
var jogo
var cli: GameServer.Cliente


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
	await _q(20)
	cli = jogo.server.clientes.values()[0]

	# 1) rifle automático nos bonecos (~10 m)
	await _dar("rajada")
	await _posicionar(Vector3(0, 0.05, 7), CampoTreino.DUMMIES[1] + Vector3(0, 1.1, 0))
	Input.action_press("fire")
	await _q(4)
	await _foto("tracante_rifle_bonecos_a")
	await _q(2)
	await _foto("tracante_rifle_bonecos_b")
	Input.action_release("fire")
	await _q(15)
	# 2) tiro longo na caixa de metal (~25 m)
	await _posicionar(Vector3(-4, 0.05, 12), Vector3(16, 1.6, -9))
	Input.action_press("fire")
	await _q(3)
	await _foto("tracante_rifle_longe_a")
	await _q(3)
	await _foto("tracante_rifle_longe_b")
	Input.action_release("fire")
	await _q(15)
	# 3) espingarda na parede da cabana (~9 m)
	await _dar("trovao")
	await _posicionar(Vector3(-16, 0.05, -2), Vector3(-16, 1.4, -11.8))
	Input.action_press("fire")
	await _q(2)
	Input.action_release("fire")
	await _foto("tracante_espingarda")
	await _q(4)
	await _foto("tracante_espingarda_impacto")
	await _q(20)
	# 4) vista lateral: o traçante sai do cano
	await _dar("rajada")
	await _posicionar(Vector3(20, 0.05, 20), Vector3(20, 1.4, 0))
	var cam := Camera3D.new()
	cam.fov = 45
	jogo.add_child(cam)
	cam.look_at_from_position(Vector3(23.5, 1.6, 17.5), Vector3(20, 1.4, 16.5), Vector3.UP)
	cam.current = true
	Input.action_press("fire")
	await _q(3)
	await _foto("tracante_lateral_cano")
	Input.action_release("fire")
	print("TRACANTES_OK em voo=%d" % jogo.fx.active_tracers())
	quit()


func _q(n: int) -> void:
	for i in n:
		await physics_frame


func _foto(nome: String) -> void:
	await process_frame
	root.get_texture().get_image().save_png("%s/%s.png" % [pasta, nome])
	print("FOTO ", nome)


func _dar(arma: String) -> void:
	cli.inv = Inventory.new()
	cli.inv.add_item(arma, 2)
	for t in ItemDB.ammo_types():
		cli.inv.add_ammo(t, 300)
	cli.dirty = true
	await _q(12)


func _posicionar(pos: Vector3, alvo: Vector3) -> void:
	cli.pawn.global_position = pos
	jogo.pawn.global_position = pos
	cli.pawn.velocity = Vector3.ZERO
	jogo.pawn.velocity = Vector3.ZERO
	var olho := pos + Vector3(0, Combat.EYE_STAND, 0)
	var d := alvo - olho
	jogo.camera.yaw = rad_to_deg(atan2(-d.x, -d.z))
	jogo.camera.pitch = rad_to_deg(atan2(d.y, Vector2(d.x, d.z).length()))
	await _q(10)
