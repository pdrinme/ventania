extends SceneTree
## Onde está o custo de renderização do mapa: câmera parada (na Vila Brisa, de fora e
## de dentro de uma casa), mede chamadas de desenho, primitivas e tempo de quadro com
## TUDO e sem cada categoria (construções, props/vegetação, mobília, Tormenta, sombras).
## Uso: xvfb-run godot --path game --rendering-driver opengl3 --resolution 1280x720 -s res://tests/perf/perf_categorias.gd

func _init() -> void:
	await process_frame
	var settings = root.get_node("Settings")
	settings.set_value("graphics", "profile", "balanced")
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var mapa := IlhaVentania.new()
	root.add_child(mapa)
	var bc := BuildClient.new()
	root.add_child(bc)
	bc.setup(mapa)
	var tormenta := StormVisual.new()
	root.add_child(tormenta)
	tormenta.set_state({"fase": 2, "fases": 7, "fechando": false, "terminou": false, "c_de": Vector2(-20, 10), "r_de": 175.0,
			"c_para": Vector2(-20, 10), "r_para": 100.0, "total_ms": 0, "resta_ms": 30000, "dano": 2})
	var cam := Camera3D.new()
	cam.fov = 70
	cam.add_to_group("camera_principal")
	root.add_child(cam)
	cam.current = true
	var vila: Vector3 = mapa.points_of_interest()[0]["pos"]
	var mmis := root.find_children("*", "MultiMeshInstance3D", true, false)
	var grupos := {"construcoes": [], "mobilia": [], "vegetacao": [], "outros_props": []}
	var moveis := ["sofa", "mesa", "cadeira", "cama", "armario", "geladeira", "fogao", "pia", "tv", "prateleira", "luminaria", "tapete",
			"balcao", "gondola", "expositor", "maquina", "bancada", "caixas", "tambores", "barril", "sacos", "feno", "ferramentas", "escada"]
	for m: MultiMeshInstance3D in mmis:
		if bc.is_ancestor_of(m):
			grupos["construcoes"].append(m)
			continue
		var nome := String(m.multimesh.mesh.resource_name) if m.multimesh.mesh else ""
		var achou := ""
		for mv in moveis:
			if nome.begins_with(mv):
				achou = "mobilia"
		if achou.is_empty():
			achou = "vegetacao" if (nome.begins_with("arbusto") or nome.begins_with("pinheiro") or nome.begins_with("arvore") or nome.begins_with("girassol")) else "outros_props"
		grupos[achou].append(m)
	for g in grupos:
		print("  %s: %d grupos MultiMesh, %d instâncias" % [g, grupos[g].size(), grupos[g].reduce(func(a, m): return a + m.multimesh.instance_count, 0)])
	for vista in [["vila_de_fora", vila + Vector3(-30, 8, 30), vila], ["casa_por_dentro", vila + Vector3(10, 1.7, -18), vila + Vector3(14, 1.4, -18)]]:
		cam.look_at_from_position(vista[1], vista[2], Vector3.UP)
		for caso in ["tudo", "sem_construcoes", "sem_mobilia", "sem_vegetacao", "sem_outros_props", "sem_tormenta", "sem_sombras"]:
			for g in grupos:
				for m in grupos[g]:
					m.visible = caso != "sem_" + g
			tormenta.visible = caso != "sem_tormenta"
			settings.set_value("graphics", "shadows", "off" if caso == "sem_sombras" else "low")
			for i in 30:
				await process_frame
			var t := 0.0
			var dc := 0
			var pr := 0
			for i in 60:
				await process_frame
				t += root.get_process_delta_time()
				dc += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
				pr += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
			print("PERF %s %s: %.1f ms/quadro, %d chamadas, %d primitivas" % [vista[0], caso, t / 60.0 * 1000.0, dc / 60, pr / 60])
	quit()
