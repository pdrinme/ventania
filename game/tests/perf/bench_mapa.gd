extends SceneTree
## Benchmark do mapa (cliente): Ilha Ventania com as construções (BuildClient), a
## parede da Tormenta e 12 personagens animados, em DUAS rotas — por fora (de POI em
## POI, na altura do jogador) e POR DENTRO dos edifícios (cômodos térreos) — nos 3
## perfis gráficos. Mede: carga do mapa, memória (estática e de vídeo), objetos,
## corpos de colisão, FPS médio / 1% pior / pior quadro, chamadas de desenho e
## primitivas. Precisa de janela (xvfb-run). Sem GPU (renderização por software) os
## números de FPS só valem para COMPARAR versões na mesma máquina.
## Uso: godot --path game --rendering-driver opengl3 --resolution 1280x720 -s res://tests/perf/bench_mapa.gd [-- segundos]

const PERFIS := ["performance", "balanced", "quality"]
var seg := 10.0


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		seg = float(a[0])
	await process_frame
	var settings = root.get_node("Settings")
	var mem0 := OS.get_static_memory_usage()
	var t0 := Time.get_ticks_usec()
	var mapa := IlhaVentania.new()
	root.add_child(mapa)
	var bc := BuildClient.new()
	root.add_child(bc)
	bc.setup(mapa)
	var carga_ms := (Time.get_ticks_usec() - t0) / 1000.0
	await process_frame
	await process_frame
	var corpos := root.find_children("*", "StaticBody3D", true, false).size()
	var cam := Camera3D.new()
	cam.fov = 70
	cam.add_to_group("camera_principal")
	root.add_child(cam)
	cam.current = true
	var tormenta := StormVisual.new()
	root.add_child(tormenta)
	tormenta.set_state({"fase": 2, "fases": 7, "fechando": false, "terminou": false, "c_de": Vector2(-20, 10), "r_de": 175.0,
			"c_para": Vector2(-20, 10), "r_para": 100.0, "total_ms": 0, "resta_ms": 30000, "dano": 2})
	var pessoas := []
	for i in 12:
		var v := PawnVisual.new()
		root.add_child(v)
		v.set_held(ItemDB.index_of(["rajada", "picareta", "trovao"][i % 3]))
		pessoas.append(v)
	# rotas
	var fora: Array[Vector3] = []
	for p in mapa.points_of_interest():
		fora.append(p["pos"])
	fora.append(fora[0])
	var dentro: Array[Vector3] = []
	var k := 0
	for d: Dictionary in mapa.building_pieces():
		if d["tipo"] != Grade.PISO:
			continue
		var cell: Vector3i = d["cell"]
		var c := Vector3(cell.x * 4.0 + 2.0, cell.y * 4.0 + 0.1, cell.z * 4.0 + 2.0)
		if c.y - mapa.ground_height(c.x, c.z) > 1.5:
			continue
		k += 1
		if k % 9 == 0:
			dentro.append(c)
	print("BENCH carga_mapa_ms=%.0f memoria_estatica_mb=%.1f (mapa +%.1f) objetos=%d nos=%d corpos_colisao=%d pecas=%d" % [
			carga_ms, OS.get_static_memory_usage() / 1048576.0, (OS.get_static_memory_usage() - mem0) / 1048576.0,
			Performance.get_monitor(Performance.OBJECT_COUNT), Performance.get_monitor(Performance.OBJECT_NODE_COUNT), corpos,
			mapa.building_pieces().size()])
	for perfil in PERFIS:
		settings.set_value("graphics", "profile", perfil)
		Engine.max_fps = 0
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		for rota in ["fora", "dentro"]:
			var pts: Array[Vector3] = fora if rota == "fora" else dentro
			var frames := PackedFloat32Array()
			var draws := PackedInt32Array()
			var prims := PackedInt32Array()
			var ini := Time.get_ticks_msec()
			var aquec := 1500
			var t := 0.0
			while Time.get_ticks_msec() - ini < seg * 1000.0 + aquec:
				await process_frame
				var dt := 1.0 / 60.0
				t += dt / (seg * 0.95)
				var p := _na_rota(pts, t, mapa, rota == "dentro")
				var adiante := _na_rota(pts, t + 0.01, mapa, rota == "dentro")
				if rota == "dentro":
					# dentro: gira devagar olhando o cômodo
					var giro := Vector3(cos(t * 40.0), 0, sin(t * 40.0))
					cam.look_at_from_position(p, p + giro + Vector3(0, -0.25, 0), Vector3.UP)
				else:
					cam.look_at_from_position(p, adiante + Vector3(0, -1.0, 0), Vector3.UP)
				for i in pessoas.size():
					var v: PawnVisual = pessoas[i]
					var ang := i * TAU / pessoas.size() + t * 20.0
					var q := p + Basis(Vector3.UP, cam.rotation.y) * Vector3(cos(ang) * (3 + i % 4 * 2), 0, -6 - (i % 5) * 3)
					q.y = mapa.ground_height(q.x, q.z)
					v.global_position = q
					v.update_state(Vector3(0, 0, -5.5), Protocol.F_ON_FLOOR | Protocol.F_SPRINTING, ang)
				if Time.get_ticks_msec() - ini < aquec:
					continue
				frames.append(get_process_frame_time_ms())
				draws.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
				prims.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
			var r := Benchmark.summarize(frames, draws, prims)
			var dmax := 0
			for d in draws:
				dmax = maxi(dmax, d)
			print("BENCH perfil=%s rota=%s fps_medio=%.1f fps_1pct=%.1f frame_max_ms=%.1f draw_calls=%d (max %d) primitivas=%d memoria_video_mb=%.1f memoria_estatica_mb=%.1f" % [
					perfil, rota, r["fps_medio"], r["fps_1pct"], r["frame_max_ms"], r["draw_calls_medio"], dmax, r["primitivas_medio"],
					RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0, OS.get_static_memory_usage() / 1048576.0])
	quit()


func get_process_frame_time_ms() -> float:
	return Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0 if false else root.get_process_delta_time() * 1000.0


func _na_rota(pts: Array[Vector3], k: float, mapa: Mapa, dentro: bool) -> Vector3:
	var n := pts.size() - 1
	if dentro:
		var i := clampi(floori(fposmod(k, 1.0) * pts.size()), 0, pts.size() - 1)
		return pts[i] + Vector3(0, 1.6, 0)
	var f := fposmod(k, 1.0) * n
	var i := floori(f)
	var p := pts[i].lerp(pts[i + 1], f - i)
	p.y = mapa.ground_height(p.x, p.z) + 3.2
	return p
