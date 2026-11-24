extends SceneTree
## Close-up de um traje (detalhes: mãos, pés, topo da cabeça, chapéu). Precisa de
## janela (xvfb-run).
## Uso: godot --path game --rendering-driver opengl3 -s res://tests/capturar_close.gd -- saida.png traje.glb anim tempo cx cy cz ax ay az [fov]


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	await process_frame
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("9fd6f2")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("b9c6ff")
	env.ambient_light_energy = 0.4
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sol := DirectionalLight3D.new()
	sol.rotation_degrees = Vector3(-45, 30, 0)
	sol.light_energy = 0.9
	root.add_child(sol)
	var chao := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(20, 20)
	var mc := StandardMaterial3D.new()
	mc.albedo_color = Color("6cc24a")
	pm.material = mc
	chao.mesh = pm
	root.add_child(chao)
	var m := (load(a[1]) as PackedScene).instantiate() as Node3D
	root.add_child(m)
	var ap := m.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	ap.play(a[2])
	ap.seek(float(a[3]), true)
	ap.pause()
	var cam := Camera3D.new()
	cam.fov = float(a[10]) if a.size() > 10 else 30.0
	root.add_child(cam)
	cam.current = true
	cam.look_at_from_position(Vector3(float(a[4]), float(a[5]), float(a[6])), Vector3(float(a[7]), float(a[8]), float(a[9])))
	for i in 6:
		await process_frame
	root.get_texture().get_image().save_png(a[0])
	quit()
