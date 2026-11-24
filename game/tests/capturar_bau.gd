extends SceneTree
## Baú abrindo, quadro a quadro (revisão do modelo e da animação "abrir").
## Uso: godot --path game --rendering-driver opengl3 -s res://tests/capturar_bau.gd -- saida.png


func _init() -> void:
	var saida: String = OS.get_cmdline_user_args()[0]
	await process_frame
	var we := WorldEnvironment.new()
	we.environment = Environment.new()
	we.environment.background_mode = Environment.BG_COLOR
	we.environment.background_color = Color("9fd6f2")
	we.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	we.environment.ambient_light_color = Color("b9c6ff")
	root.add_child(we)
	var sol := DirectionalLight3D.new()
	sol.rotation_degrees = Vector3(-45, 30, 0)
	root.add_child(sol)
	for i in 5:
		var b := (load("res://assets/baus_coletaveis/bau_ventania_01.glb") as PackedScene).instantiate() as Node3D
		b.position = Vector3((i - 2) * 1.6, 0, 0)
		b.rotation_degrees.y = -30
		root.add_child(b)
		var ap := b.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
		var nome: String = ap.get_animation_list()[0]
		ap.play(nome)
		ap.seek(ap.get_animation(nome).length * i / 4.0, true)
		ap.pause()
	var cam := Camera3D.new()
	cam.fov = 40
	root.add_child(cam)
	cam.current = true
	cam.look_at_from_position(Vector3(0, 2.2, 5.5), Vector3(0, 0.4, 0))
	for i in 6:
		await process_frame
	root.get_texture().get_image().save_png(saida)
	quit()
