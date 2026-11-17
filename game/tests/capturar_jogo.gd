extends SceneTree
## Captura a partida local (precisa de janela / xvfb-run).
## Uso: godot --path game --rendering-driver opengl3 -s res://tests/capturar_jogo.gd -- saida.png [--simular-celular] [--br]
## --br: Battle Royale local (sem bots), fotografado já no chão, em jogo.


func _init() -> void:
	var saida := OS.get_cmdline_user_args()[0]
	await process_frame
	root.theme = VentaniaTheme.build(root.get_node("Settings").is_mobile)
	var br := "--br" in OS.get_cmdline_user_args()
	await root.get_node("SceneManager").go("game", {"modo": "br_local" if br else "local", "bots": 0})
	var jogo := current_scene
	for i in 120:
		await physics_frame
		if jogo.pawn:
			break
	if br:
		# espera a partida começar e põe o jogador no chão (pelo servidor local)
		for i in 30 * 30:
			await physics_frame
			if jogo.server.partida.estado == Protocol.MATCH_ONIBUS:
				break
		jogo.server.partida.onibus.fecha = jogo.server.tick + 2
		for i in 90:
			await physics_frame
		var c = jogo.server.clientes.values()[0]
		c.pawn.global_position = Vector3(0, jogo.mundo.ground_height(0, 0) + 1.0, 0)
		c.pawn.queda = 0
		c.pawn.velocity = Vector3.ZERO
		for i in 60:
			await physics_frame
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
