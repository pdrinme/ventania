extends SceneTree
## Verificação visual da Etapa 4 numa partida BR local real (Ilha Ventania):
## vista aérea, POIs no chão, parede da Tormenta, HUD da partida com minimapa,
## mapa completo e tela de resultado.
## Uso: xvfb-run godot --path game --rendering-driver opengl3 --resolution 960x540 -s res://tests/capturar_ilha.gd -- <pasta>

var pasta := ""
var jogo
var cli: GameServer.Cliente
var cam: Camera3D


func _init() -> void:
	pasta = OS.get_cmdline_user_args()[0]
	await process_frame
	root.theme = VentaniaTheme.build(false)
	await root.get_node("SceneManager").go("game", {"modo": "br_local"})
	jogo = current_scene
	for i in 300:
		await physics_frame
		if jogo.pawn:
			break
	cli = jogo.server.clientes.values()[0]
	await _quadros(20)
	await _foto("ilha_espera")
	for i in 30 * 20:
		await physics_frame
		if jogo._partida.get("estado", -1) == Protocol.MATCH_JOGO:
			break
	await _quadros(20)
	cam = Camera3D.new()
	cam.far = 1500
	cam.fov = 55
	jogo.add_child(cam)
	jogo.combat_hud.visible = false
	cam.current = true
	# vista aérea: sem neblina e com tudo visível (só para a foto)
	var env: Environment = get_nodes_in_group("ambiente")[0].environment
	env.fog_enabled = false
	for gi in jogo.mundo.find_children("*", "GeometryInstance3D", true, false):
		(gi as GeometryInstance3D).visibility_range_end = 0.0
	cam.look_at_from_position(Vector3(-330, 260, 330), Vector3(0, 0, 0), Vector3.UP)
	await _foto("ilha_aerea")
	cam.look_at_from_position(Vector3(0, 520, 1), Vector3(0, 0, 0), Vector3.UP)
	await _foto("ilha_topo")
	env.fog_enabled = true
	for p in jogo.mundo.points_of_interest():
		var c: Vector3 = p["pos"]
		cam.look_at_from_position(c + Vector3(38, 26, 46), c, Vector3.UP)
		await _foto("poi_" + String(p["nome"]).to_lower().replace(" ", "_"))
	jogo.combat_hud.visible = true
	jogo.camera.camera().current = true
	# no chão, na Vila Brisa, olhando para as casas
	var vila: Vector3 = jogo.mundo.points_of_interest()[0]["pos"]
	await _teleportar(vila + Vector3(0, 0.3, 26), 0.0)
	await _foto("vila_chao")
	# perto da parede da Tormenta (força um raio pequeno só no visual do cliente)
	var d: Dictionary = jogo.tormenta.dados.duplicate()
	d["c_de"] = Vector2(vila.x, vila.z - 10)
	d["r_de"] = 30.0
	d["fechando"] = false
	jogo.tormenta.set_state(d)
	await _teleportar(vila + Vector3(0, 0.3, 32), 0.0)
	await _foto("tormenta_de_fora")
	await _teleportar(vila + Vector3(0, 0.3, 10), 180.0)
	await _foto("tormenta_de_dentro")
	jogo.match_hud.toggle_map(true)
	await _quadros(4)
	await _foto("mapa_completo")
	jogo.match_hud.toggle_map(false)
	jogo.server.combat.eliminate(cli, cli.id, "")
	await _quadros(40)
	await _foto("resultado")
	print("ILHA_OK")
	quit()


func _quadros(n: int) -> void:
	for i in n:
		await physics_frame


func _foto(nome: String) -> void:
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png("%s/%s.png" % [pasta, nome])
	print("FOTO ", nome)


func _teleportar(pos: Vector3, yaw: float) -> void:
	var y: float = jogo.mundo.ground_height(pos.x, pos.z) + 0.3
	pos.y = y
	cli.pawn.global_position = pos
	cli.pawn.velocity = Vector3.ZERO
	jogo.pawn.global_position = pos
	jogo.camera.yaw = yaw
	jogo.camera.pitch = -6.0
	await _quadros(12)
