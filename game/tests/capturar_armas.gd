extends SceneTree
## Prancha: personagem segurando cada item (IK nas mãos). Precisa de janela / xvfb-run.
## Uso: godot --path game --rendering-driver opengl3 -s res://tests/capturar_armas.gd -- saida.png [yaw] [mirando 0/1] [acao] [progresso]

var ITENS := ["faisca", "rajada", "trovao", "zumbido", "gaviao", "curativo", "celula_p"]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var saida := args[0]
	var yaw := float(args[1]) if args.size() > 1 else -60.0
	var mirando := args.size() > 2 and args[2] == "1"
	var acao := int(args[3]) if args.size() > 3 else 0
	var prog := float(args[4]) if args.size() > 4 else 0.0
	var zoom := args.size() > 5
	if zoom:
		ITENS = args[5].split(",")
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("8fd3ff")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("c8d2ff")
	env.ambient_light_energy = 0.55
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sol := DirectionalLight3D.new()
	sol.rotation_degrees = Vector3(-40, -60, 0)
	root.add_child(sol)
	var vis := []
	for i in ITENS.size():
		var v := PawnVisual.new()
		v.position = Vector3((i - 3) * 1.45, 0, 0)
		root.add_child(v)
		vis.append(v)
	await process_frame
	for i in ITENS.size():
		var v: PawnVisual = vis[i]
		v.set_held(ItemDB.index_of(ITENS[i]))
		v.update_state(Vector3.ZERO, Protocol.F_ON_FLOOR, deg_to_rad(yaw))
	for f in 50:
		for v: PawnVisual in vis:
			v.set_aim(0.0, mirando)
			v.set_action(acao, prog)
		await process_frame
	var cam := Camera3D.new()
	cam.fov = 34
	root.add_child(cam)
	if zoom:
		cam.fov = 30
		var meio := (ITENS.size() - 1) / 2.0 - 3.0
		cam.look_at_from_position(Vector3(meio * 1.45, 1.5, 4.2), Vector3(meio * 1.45, 1.25, 0), Vector3.UP)
	else:
		cam.look_at_from_position(Vector3(0, 1.6, 11), Vector3(0, 1.15, 0), Vector3.UP)
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png(saida)
	print("ARMAS_OK")
	quit()
