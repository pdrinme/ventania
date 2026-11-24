extends SceneTree
## Folha de quadros de uma animação: N cópias do personagem lado a lado, cada uma
## num instante do clipe (de lado, como numa folha de animador). Para revisar
## passadas, pulo, aterrissagem, eliminação. Precisa de janela (xvfb-run).
## Uso: godot --path game --rendering-driver opengl3 -s res://tests/capturar_anim.gd -- saida.png traje.glb anim [quadros=8] [angulo=90]


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var saida := a[0]
	var caminho := a[1]
	var anim := a[2]
	var n := int(a[3]) if a.size() > 3 else 8
	var ang := float(a[4]) if a.size() > 4 else 90.0
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
	sol.rotation_degrees = Vector3(-40, 140, 0)
	sol.light_energy = 0.9
	root.add_child(sol)
	var chao := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 20)
	var mc := StandardMaterial3D.new()
	mc.albedo_color = Color("e9f7ef")
	pm.material = mc
	chao.mesh = pm
	root.add_child(chao)
	var passo := 1.15
	for i in n:
		var m := (load(caminho) as PackedScene).instantiate() as Node3D
		m.position = Vector3((i - (n - 1) / 2.0) * passo, 0, 0)
		m.rotation_degrees.y = ang
		root.add_child(m)
		var ap := m.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
		ap.play(anim)
		var dur := ap.get_animation(anim).length
		ap.seek(dur * i / float(n if ap.get_animation(anim).loop_mode != Animation.LOOP_NONE else n - 1), true)
		ap.pause()
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 2.5
	root.add_child(cam)
	cam.current = true
	cam.look_at_from_position(Vector3(0, 1.0, 10), Vector3(0, 1.0, 0))
	for i in 6:
		await process_frame
	root.get_texture().get_image().save_png(saida)
	print("FOTO ", saida)
	quit()
