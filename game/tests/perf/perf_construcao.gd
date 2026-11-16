extends SceneTree
## Mede o custo das construções para definir o limite de peças (Etapa 5):
##  1) servidor: criar N peças (validação + corpo de colisão);
##  2) servidor: tick com 24 jogadores andando entre as N peças (movimento + física);
##  3) servidor: derrubar a base de uma estrutura grande (busca de apoio + lotes);
##  4) cliente: grupos de MultiMesh (chamadas de desenho) e montagem do visual.
## Uso: godot --headless --path game -s res://tests/perf/perf_construcao.gd -- [N=1200]


func _init() -> void:
	var n := int(OS.get_cmdline_user_args()[0]) if OS.get_cmdline_user_args().size() > 0 else 1200
	await process_frame
	var mundo := CampoTreino.new()
	mundo.com_ambiente = false
	root.add_child(mundo)
	var server := GameServer.new(mundo, 1, "treino")
	server.kit_inicial = false
	root.add_child(server)
	await physics_frame
	Grade.config()["limite_pecas"] = 100000
	var c := GameServer.Cliente.new()
	c.id = 1
	c.pawn = Pawn.new()
	mundo.add_child(c.pawn)
	server.clientes[1] = c
	for t in ItemDB.material_types():
		c.inv.materials[t] = 1000000
	# "cidade" de torres 2×2: piso, 4 paredes e piso em cima, por andar, subindo
	var feitos := 0
	var ini := Time.get_ticks_usec()
	var torre := 0
	var maior_torre: Array = []
	while feitos < n:
		var bx := -12 + (torre % 6) * 4
		var bz := -12 + (torre / 6) * 4
		for andar in 6:
			for p in [[1, Vector3i(bx, andar, bz), 0], [0, Vector3i(bx, andar, bz), 0], [0, Vector3i(bx, andar, bz + 1), 2],
					[0, Vector3i(bx, andar, bz), 1], [0, Vector3i(bx + 1, andar, bz), 3]]:
				if feitos >= n:
					break
				var cell: Vector3i = p[1]
				c.pawn.global_position = Grade.center(Grade.slot_type(p[0], p[2]), cell)
				if server.build.try_build(c, {"escolha": p[0], "material": torre % 3, "cell": cell, "rot": p[2]}) == Inventory.Err.OK:
					feitos += 1
					if torre == 0:
						maior_torre.append(server.build.estado.por_slot[Grade.key(Grade.slot_type(p[0], p[2]), cell)])
		torre += 1
	var t_criar := (Time.get_ticks_usec() - ini) / 1000.0
	print("PERF_CONSTRUCAO criar %d peças: %.1f ms (%.3f ms/peça)" % [feitos, t_criar, t_criar / feitos])
	# tick do servidor com 24 jogadores andando entre as torres
	var pawns: Array[Pawn] = []
	for i in 24:
		var p := Pawn.new()
		mundo.add_child(p)
		p.global_position = Vector3(-40 + (i % 6) * 15 + 2, 0.3, -40 + (i / 6) * 15 + 2)
		pawns.append(p)
	for i in 30:
		server.build.update()
		await physics_frame
	var tempos := PackedFloat64Array()
	for t in 150:
		await physics_frame
		var t0 := Time.get_ticks_usec()
		for i in pawns.size():
			var cmd := Protocol.InputCmd.new()
			cmd.move = Vector2(sin(t * 0.04 + i), 1.0).limit_length(1.0)
			cmd.yaw = i * 0.7 + t * 0.03
			Movement.step(pawns[i], cmd, 1.0 / Protocol.TICK_RATE)
		server.build.update()
		tempos.append((Time.get_ticks_usec() - t0) / 1000.0)
	var soma := 0.0
	var maximo := 0.0
	for x in tempos:
		soma += x
		maximo = maxf(maximo, x)
	print("PERF_CONSTRUCAO tick com 24 jogadores e %d peças: média %.3f ms, máx %.3f ms (%.1f%% do tick)" % [feitos, soma / tempos.size(), maximo, soma / tempos.size() / 33.3 * 100.0])
	# derrubar o pé de uma torre de 6 andares (busca de apoio + desabamento em lotes)
	var t1 := Time.get_ticks_usec()
	var base_paredes := maior_torre.filter(func(id): return server.build.estado.pecas.has(id) and server.build.estado.pecas[id].cell.y == 0 and server.build.estado.pecas[id].tipo != Grade.PISO)
	for id in base_paredes:
		server.build.destroy(id, Protocol.GONE_DESTRUIDA)
	var t_busca := (Time.get_ticks_usec() - t1) / 1000.0
	var ticks := 0
	var pior := 0.0
	while true:
		var t2 := Time.get_ticks_usec()
		server.build.update()
		pior = maxf(pior, (Time.get_ticks_usec() - t2) / 1000.0)
		ticks += 1
		if server.build._desabar.is_empty() or ticks > 200:
			break
	print("PERF_CONSTRUCAO derrubar a base de uma torre: busca %.2f ms, %d desabaram em %d ticks (pior tick %.2f ms)" % [t_busca, server.build.desabaram, ticks, pior])
	# cliente: espelho com visual
	var cli := BuildClient.new()
	root.add_child(cli)
	var vazio := Mapa.new()
	cli.setup(vazio)
	var t3 := Time.get_ticks_usec()
	for p: Construcoes.Peca in server.build.estado.pecas.values():
		cli.on_piece(p.to_dict())
	await process_frame
	var t_cli := (Time.get_ticks_usec() - t3) / 1000.0
	print("PERF_CONSTRUCAO cliente: %d peças em %.1f ms, %d grupos visuais (chamadas de desenho no máximo, antes do corte por distância)" % [cli.estado.pecas.size(), t_cli, cli.visual_groups()])
	quit()
