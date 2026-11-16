extends SceneTree
## Prancha com todas as animações do personagem (precisa de janela / xvfb-run).
## Uso: godot --path game --rendering-driver opengl3 -s res://tests/capturar_animacoes.gd -- saida.png

const ANIMS := ["idle", "andar", "correr", "agachado", "agachado_andar", "no_ar", "acenar"]


func _init() -> void:
	var saida := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://anims.png"
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("8fd3ff")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("b9c6ff")
	env.ambient_light_energy = 0.4
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sol := DirectionalLight3D.new()
	sol.rotation_degrees = Vector3(-40, -60, 0)
	sol.light_energy = 0.9
	root.add_child(sol)
	var cena: PackedScene = load("res://assets/personagens/recruta_base_01.glb")
	for i in ANIMS.size():
		var r := cena.instantiate() as Node3D
		r.position = Vector3((i - 3) * 1.6, 0, 0)
		r.rotation_degrees.y = 60  # 3/4 de perfil
		root.add_child(r)
		var ap := r.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
		if not ap.has_animation(ANIMS[i]):
			printerr("FALTA animação " + ANIMS[i])
			continue
		ap.play(ANIMS[i])
		ap.seek(ap.get_animation(ANIMS[i]).length * 0.3, true)
		ap.pause()
	var cam := Camera3D.new()
	cam.fov = 40
	root.add_child(cam)
	cam.look_at_from_position(Vector3(0, 1.4, 11.5), Vector3(0, 0.95, 0), Vector3.UP)
	for i in 6:
		await process_frame
	root.get_texture().get_image().save_png(saida)
	print("ANIMS_OK")
	quit()
