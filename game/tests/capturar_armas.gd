extends SceneTree
## Prancha: personagem segurando cada arma (precisa de janela / xvfb-run).
## Uso: godot --path game --rendering-driver opengl3 -s res://tests/capturar_armas.gd -- saida.png [yaw_graus]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var saida := args[0]
	var yaw := float(args[1]) if args.size() > 1 else 60.0
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("8fd3ff")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("b9c6ff")
	env.ambient_light_energy = 0.45
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sol := DirectionalLight3D.new()
	sol.rotation_degrees = Vector3(-40, -60, 0)
	root.add_child(sol)
	var armas := ["faisca", "rajada", "trovao", "zumbido", "gaviao"]
	for i in armas.size():
		var v := PawnVisual.new()
		v.position = Vector3((i - 2) * 1.7, 0, 0)
		root.add_child(v)
		v.set_weapon(ItemDB.index_of(armas[i]))
		v.update_state(Vector3.ZERO, Protocol.F_ON_FLOOR, deg_to_rad(yaw))
	var cam := Camera3D.new()
	cam.fov = 38
	root.add_child(cam)
	cam.look_at_from_position(Vector3(0, 1.5, 10.5), Vector3(0, 1.1, 0), Vector3.UP)
	for i in 40:
		await process_frame
	root.get_texture().get_image().save_png(saida)
	print("ARMAS_OK")
	quit()
