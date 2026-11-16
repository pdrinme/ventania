extends SceneTree
## Captura a partida local (precisa de janela / xvfb-run).
## Uso: godot --path game --rendering-driver opengl3 -s res://tests/capturar_jogo.gd -- saida.png [--simular-celular]


func _init() -> void:
	var saida := OS.get_cmdline_user_args()[0]
	await process_frame
	root.theme = VentaniaTheme.build(root.get_node("Settings").is_mobile)
	await root.get_node("SceneManager").go("game", {"modo": "local"})
	var jogo := current_scene
	for i in 120:
		await physics_frame
		if jogo.pawn:
			break
	jogo.camera.yaw = 10.0      # olha para os bonecos de treino e a torre
	jogo.camera.pitch = -6.0
	Input.action_press("move_forward")
	for i in 25:
		await physics_frame
	Input.action_press("fire")
	for i in 3:
		await physics_frame
	Input.action_release("fire")
	for i in 3:
		await process_frame
	root.get_texture().get_image().save_png(saida)
	print("CAPTURA_JOGO anim=%s pos=%s" % [jogo.visual.current_animation(), jogo.pawn.global_position.snapped(Vector3.ONE * 0.1)])
	Input.action_release("move_forward")
	quit()
