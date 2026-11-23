extends SceneTree
## Giro de um traje (frente, 3/4, costas, perfil e rosto de perto) com a luz e o
## material do jogo, num fundo neutro. Para revisar modelagem e deformação.
## Uso: godot --path game --rendering-driver opengl3 --resolution 1600x900 -s res://tests/capturar_traje.gd -- saida.png caminho.glb [animacao] [tempo]

func _init() -> void:
	var a := OS.get_cmdline_user_args()
	await process_frame
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("9fd6f5")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("c8d2ff")
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sol := DirectionalLight3D.new()
	sol.rotation_degrees = Vector3(-35, -30 + 180, 0)
	sol.shadow_enabled = true
	root.add_child(sol)
	var chao := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 30)
	chao.mesh = pm
	var mc := StandardMaterial3D.new()
	mc.albedo_color = Color("7fc77a")
	chao.material_override = mc
	root.add_child(chao)
	var anim: String = a[2] if a.size() > 2 else "idle"
	var tempo := float(a[3]) if a.size() > 3 else 0.5
	var giros := [-20.0, 25.0, 180.0, 90.0]
	for i in giros.size():
		var m := (load(a[1]) as PackedScene).instantiate() as Node3D
		m.position = Vector3((i - 1.5) * 1.3, 0, 0)
		m.rotation_degrees.y = giros[i]
		root.add_child(m)
		TrajeFx.attach(m, "")
		var ap := m.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
		ap.play(anim)
		ap.seek(tempo, true)
		ap.pause()
	var cam := Camera3D.new()
	cam.fov = 30
	root.add_child(cam)
	cam.look_at_from_position(Vector3(0, 1.2, 8.0), Vector3(0, 0.95, 0))
	for k in 20:
		await process_frame
	var img1 := root.get_texture().get_image()
	# rosto de perto (o da esquerda, quase de frente)
	cam.fov = 22
	var alvo := Vector3(-1.95, 1.64, 0)
	cam.look_at_from_position(alvo + Vector3(0.25, 0.05, 1.3), alvo)
	for k in 8:
		await process_frame
	var img2 := root.get_texture().get_image()
	img2.resize(img1.get_width() / 3, img1.get_height() / 3)
	img1.blit_rect(img2, Rect2i(Vector2i.ZERO, img2.get_size()), Vector2i(img1.get_width() - img2.get_width(), 0))
	img1.save_png(a[0])
	quit()
