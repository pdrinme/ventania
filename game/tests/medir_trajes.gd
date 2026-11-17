extends SceneTree
## Desempenho dos trajes: 24 personagens animados com o efeito do traje (ex.: aquário
## com peixes e bolhas) contra 24 recrutas. Mede chamadas de desenho, objetos e o
## tempo médio de quadro. Precisa de janela (xvfb-run).
## Uso: godot --path game --rendering-driver opengl3 -s res://tests/medir_trajes.gd -- traje_capitao_mare [distância]


func _init() -> void:
	var traje: String = OS.get_cmdline_user_args()[0]
	var dist := float(OS.get_cmdline_user_args()[1]) if OS.get_cmdline_user_args().size() > 1 else 14.0
	await process_frame
	var sol := DirectionalLight3D.new()
	sol.rotation_degrees = Vector3(-35, -40, 0)
	root.add_child(sol)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.look_at_from_position(Vector3(0, dist * 0.4, dist), Vector3(0, 1, 0))
	cam.fov = 75.0 * 14.0 / dist if dist > 14.0 else 75.0
	for i in 24:
		var m := (load(Cosmeticos.outfit_scene(traje)) as PackedScene).instantiate() as Node3D
		m.position = Vector3((i % 6 - 2.5) * 1.6, 0, -(i / 6) * 2.0)
		root.add_child(m)
		var fx := TrajeFx.attach(m, traje)
		if fx:
			fx.velocidade = Vector3(2, 0, 0)
		var ap := m.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
		ap.play("correr")
	for i in 30:
		await process_frame
	var t0 := Time.get_ticks_usec()
	var n := 120
	var dc := 0.0
	for i in n:
		await process_frame
		dc += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0 / n
	print("MEDIDA %s a %.0f m: draw_calls=%.0f objetos=%d quadro=%.2f ms" % [traje, dist, dc / n,
			Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME), ms])
	quit()
