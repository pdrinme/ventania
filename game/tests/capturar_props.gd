extends SceneTree
## Fileira de props (GLBs) sobre um chão de grama, com a luz do jogo, para revisar
## a arte de perto. Precisa de janela (xvfb-run).
## Uso: godot --path game --rendering-driver opengl3 -s res://tests/capturar_props.gd -- saida.png espacamento distancia caminho1.glb caminho2.glb ...


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var saida := args[0]
	var passo := float(args[1])
	var dist := float(args[2])
	var caminhos := args.slice(3)
	await process_frame
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("8fd3ff")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("b9c6ff")
	env.ambient_light_energy = 0.32
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sol := DirectionalLight3D.new()
	sol.rotation_degrees = Vector3(-50, -35, 0)
	sol.light_color = Color("fff3dc")
	sol.light_energy = 0.85
	sol.shadow_enabled = true
	root.add_child(sol)
	var chao := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(200, 200)
	var mc := StandardMaterial3D.new()
	mc.albedo_color = Color("6cc24a")
	pm.material = mc
	chao.mesh = pm
	root.add_child(chao)
	var n := caminhos.size()
	for i in n:
		var m := (load(caminhos[i]) as PackedScene).instantiate() as Node3D
		m.position = Vector3((i - (n - 1) / 2.0) * passo, 0, 0)
		m.rotation_degrees.y = 20
		root.add_child(m)
	var cam := Camera3D.new()
	cam.fov = 40
	root.add_child(cam)
	cam.current = true
	cam.look_at_from_position(Vector3(0, dist * 0.35, dist), Vector3(0, dist * 0.12, 0))
	for i in 10:
		await process_frame
	root.get_texture().get_image().save_png(saida)
	print("FOTO ", saida)
	quit()
