extends SceneTree
## Mede o custo de CPU da simulação do servidor com N personagens no campo de treino.
## Uso: godot --headless --path game -s res://tests/perf/perf_server.gd -- [N=24] [ticks=300] [ilha]
## "ilha": mede no mapa BR (relevo + ~760 corpos de colisão), espalhando os jogadores pelos POIs.


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var n := int(args[0]) if args.size() > 0 else 24
	var ticks := int(args[1]) if args.size() > 1 else 300
	var ilha := args.size() > 2 and args[2] == "ilha"
	var mundo: Mapa = IlhaVentania.new() if ilha else CampoTreino.new()
	mundo.com_ambiente = false
	root.add_child.call_deferred(mundo)
	await process_frame
	var pawns: Array[Pawn] = []
	for i in n:
		var p := Pawn.new()
		mundo.add_child(p)
		var ang := i * TAU / n
		p.global_position = Vector3(cos(ang) * 20.0, 0.2, sin(ang) * 20.0)
		if ilha:
			var poi: Vector3 = mundo.points_of_interest()[i % 6]["pos"]
			p.global_position = poi + Vector3(cos(ang) * 12.0, 0.4, sin(ang) * 12.0)
		pawns.append(p)
	await physics_frame
	var dt := 1.0 / Protocol.TICK_RATE
	var tempos := PackedFloat64Array()
	var rnd := RandomNumberGenerator.new()
	rnd.seed = 7
	for t in ticks:
		await physics_frame
		var ini := Time.get_ticks_usec()
		for i in pawns.size():
			var c := Protocol.InputCmd.new()
			c.move = Vector2(sin(t * 0.05 + i), 1.0).limit_length(1.0)
			c.yaw = i + t * 0.02
			c.buttons = (Protocol.BTN_SPRINT if i % 2 == 0 else 0) | (Protocol.BTN_JUMP if rnd.randf() < 0.03 else 0)
			Movement.step(pawns[i], c, dt)
		tempos.append((Time.get_ticks_usec() - ini) / 1000.0)
	var total := 0.0
	var maximo := 0.0
	for x in tempos:
		total += x
		maximo = maxf(maximo, x)
	var media := total / tempos.size()
	print("PERF_SERVIDOR jogadores=%d ticks=%d media=%.3f ms max=%.3f ms orcamento=%.1f ms (%.1f%% do tick)" % [n, ticks, media, maximo, 1000.0 / Protocol.TICK_RATE, media / (1000.0 / Protocol.TICK_RATE) * 100.0])
	quit()
