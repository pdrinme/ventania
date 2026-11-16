extends Control
## Benchmark do mapa Battle Royale (Ilha Ventania) nos 3 perfis gráficos.
## Câmera percorre os pontos de interesse na altura do jogador, com 16 personagens
## animados (armas e picareta) e a parede da Tormenta — a carga de uma partida.
## Cada perfil: 2 s de aquecimento + DURACAO s medidos, sem limite de FPS e sem
## vsync. Resultados salvos em user://benchmarks/ (JSON + CSV), como o da vitrine.
## Linha de comando: --benchmark-ilha (roda os 3 perfis, imprime e fecha).

const DURACAO := 20.0
const PERFIS := ["performance", "balanced", "quality"]

var mapa: IlhaVentania
var cam: Camera3D
var _rota: Array[Vector3] = []
var _t := 0.0
var _pessoas: Array = []
var _texto: Label
var _resultados: Array = []
var automatico := false


func _ready() -> void:
	automatico = "--benchmark-ilha" in OS.get_cmdline_user_args()
	mapa = IlhaVentania.new()
	add_child(mapa)
	cam = Camera3D.new()
	cam.fov = 70
	cam.add_to_group("camera_principal")
	add_child(cam)
	cam.current = true
	var tormenta := StormVisual.new()
	add_child(tormenta)
	tormenta.set_state({"fase": 2, "fases": 7, "fechando": false, "terminou": false, "c_de": Vector2(-20, 10), "r_de": 175.0,
			"c_para": Vector2(-20, 10), "r_para": 100.0, "total_ms": 0, "resta_ms": 30000, "dano": 2})
	await get_tree().process_frame
	for p in mapa.points_of_interest():
		_rota.append(p["pos"])
	_rota.append(_rota[0])
	var itens := ["rajada", "faisca", "trovao", "zumbido", "gaviao", "picareta", "celula_p", "picareta"]
	for i in 16:
		var v := PawnVisual.new()
		add_child(v)
		v.set_held(ItemDB.index_of(itens[i % itens.size()]))
		_pessoas.append(v)
	_texto = Label.new()
	_texto.theme_type_variation = "Subtitulo"
	_texto.position = Vector2(20, 20)
	_texto.add_theme_color_override("font_outline_color", Color("24252c"))
	_texto.add_theme_constant_override("outline_size", 8)
	add_child(_texto)
	_rodar()


## Posição na rota (0..1) — da altura do chão + olhos, de POI em POI.
func _na_rota(k: float) -> Vector3:
	var n := _rota.size() - 1
	var f := fposmod(k, 1.0) * n
	var i := floori(f)
	var p := _rota[i].lerp(_rota[i + 1], f - i)
	p.y = mapa.ground_height(p.x, p.z) + 3.2
	return p


func _process(delta: float) -> void:
	if _rota.is_empty():
		return
	_t += delta / 60.0
	var p := _na_rota(_t)
	var adiante := _na_rota(_t + 0.004)
	cam.look_at_from_position(p, adiante + Vector3(0, -1.0, 0), Vector3.UP)
	for i in _pessoas.size():
		var v: PawnVisual = _pessoas[i]
		var ang := i * TAU / _pessoas.size() + _t * 20.0
		var q := p + Basis(Vector3.UP, cam.rotation.y) * Vector3(cos(ang) * (4 + i % 4 * 3), 0, -8 - (i % 5) * 4)
		q.y = mapa.ground_height(q.x, q.z)
		v.global_position = q
		v.update_state(Vector3(0, 0, -5.5), Protocol.F_ON_FLOOR | Protocol.F_SPRINTING, ang)
		v.set_action(Protocol.ACT_SWING if i % 8 == 5 else 0, fmod(_t * 60.0, 1.0))


func _rodar() -> void:
	var perfil_antes: String = Settings.get_value("graphics", "profile")
	var fps_antes := Engine.max_fps
	var vsync_antes := DisplayServer.window_get_vsync_mode() if DisplayServer.get_name() != "headless" else DisplayServer.VSYNC_ENABLED
	for perfil in PERFIS:
		Settings.set_value("graphics", "profile", perfil)
		Engine.max_fps = 0
		if DisplayServer.get_name() != "headless":
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		_texto.text = "Benchmark da Ilha — perfil %s (aquecendo)" % SettingsSchema.label(perfil)
		await get_tree().create_timer(2.0).timeout
		var frames := PackedFloat32Array()
		var draws := PackedInt32Array()
		var prims := PackedInt32Array()
		var ini := Time.get_ticks_msec()
		_texto.text = "Benchmark da Ilha — perfil %s (medindo %d s)" % [SettingsSchema.label(perfil), DURACAO]
		while Time.get_ticks_msec() - ini < DURACAO * 1000.0:
			await get_tree().process_frame
			frames.append(get_process_delta_time() * 1000.0)
			draws.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
			prims.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
		var r := Benchmark.summarize(frames, draws, prims)
		r["cenario"] = "ilha_ventania (rota pelos POIs, 16 personagens, Tormenta)"
		r["perfil"] = perfil
		r["resolucao_3d"] = Settings.get_value("graphics", "render_scale")
		r["sombras"] = Settings.get_value("graphics", "shadows")
		r["msaa"] = Settings.get_value("graphics", "msaa")
		r["tela"] = "%dx%d" % [get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y]
		r.merge(Benchmark.device_info())
		Benchmark.save(r, frames)
		_resultados.append(r)
		var linha := "BENCH_ILHA perfil=%s fps_medio=%.1f fps_1pct=%.1f frame_max_ms=%.1f draw_calls=%d primitivas=%d" % [
				perfil, r["fps_medio"], r["fps_1pct"], r["frame_max_ms"], r["draw_calls_medio"], r["primitivas_medio"]]
		print(linha)
		Log.info("benchmark", linha)
	Settings.set_value("graphics", "profile", perfil_antes)
	Engine.max_fps = fps_antes
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(vsync_antes)
	var resumo := "Benchmark da Ilha (%s)\n" % RenderingServer.get_video_adapter_name()
	for r in _resultados:
		resumo += "%s: %.1f FPS (1%% pior %.1f), %d draw calls\n" % [SettingsSchema.label(r["perfil"]), r["fps_medio"], r["fps_1pct"], r["draw_calls_medio"]]
	resumo += "Salvo em %s · Esc para voltar" % ProjectSettings.globalize_path("user://benchmarks")
	_texto.text = resumo
	DisplayServer.clipboard_set(resumo)
	if automatico:
		get_tree().quit()


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_cancel") or e.is_action_pressed("pause"):
		SceneManager.go("diagnostics")
