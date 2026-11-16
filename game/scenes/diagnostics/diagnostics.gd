extends Control
## Vitrine do kit + teste de desempenho para hardware real.
## - Câmera livre (arrastar/pinçar/roda/analógico).
## - Troca de perfil gráfico e de densidade (1 a 4 quarteirões por lado) ao vivo.
## - Benchmark de 20 s com câmera automática: FPS médio, 1% pior, frame mais lento,
##   draw calls, memória. Salva em user://benchmarks/ e copia o resumo.

const DURACAO_BENCH := 20.0
const PERFIS := ["performance", "balanced", "quality"]

var _vitrine: KitShowcase
var _camera: OrbitCamera
var _stats: Label
var _resultado: Label
var _b_perfil: Button
var _b_densidade: Button
var _b_bench: Button
var _b_copiar: Button
var _ultimo_resumo := ""
var _acumulado := 0.0
var _bench_ativo := false
var _frames: PackedFloat32Array = []
var _draws: PackedInt32Array = []
var _prims: PackedInt32Array = []


func _ready() -> void:
	var vp_cont := SubViewportContainer.new()
	vp_cont.set_anchors_preset(Control.PRESET_FULL_RECT)
	vp_cont.stretch = true
	add_child(vp_cont)
	var vp := SubViewport.new()
	vp.handle_input_locally = true
	vp_cont.add_child(vp)
	_vitrine = KitShowcase.new()
	vp.add_child(_vitrine)
	_camera = OrbitCamera.new()
	_camera.fov = 55
	vp.add_child(_camera)
	_aplicar_viewport(vp)
	Settings.changed.connect(func(s, _k, _v):
		if s == "graphics":
			_aplicar_viewport(vp))

	var margem := MarginContainer.new()
	margem.set_anchors_preset(Control.PRESET_FULL_RECT)
	margem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for lado in ["left", "right", "top", "bottom"]:
		margem.add_theme_constant_override("margin_" + lado, 20)
	add_child(margem)
	var raiz := HBoxContainer.new()
	raiz.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margem.add_child(raiz)

	var painel := PanelContainer.new()
	painel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	raiz.add_child(painel)
	var coluna := VBoxContainer.new()
	coluna.custom_minimum_size.x = 330 if Settings.is_mobile else 300
	painel.add_child(coluna)
	var alvo: int = get_tree().root.theme.get_meta("altura_alvo", 52)
	var voltar := _botao(coluna, "‹ Menu", alvo, _voltar)
	_b_perfil = _botao(coluna, "", alvo, _proximo_perfil)
	_b_densidade = _botao(coluna, "", alvo, _proxima_densidade)
	_b_bench = _botao(coluna, "Iniciar teste (20 s)", alvo, _iniciar_bench)
	_b_copiar = _botao(coluna, "Copiar resultado", alvo, func():
		DisplayServer.clipboard_set(_ultimo_resumo)
		_resultado.text += "\n(copiado)")
	_b_copiar.disabled = true
	_resultado = Label.new()
	_resultado.theme_type_variation = "Pequeno"
	_resultado.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_resultado.custom_minimum_size.x = 280
	coluna.add_child(_resultado)

	var espaco := Control.new()
	espaco.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	espaco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	raiz.add_child(espaco)
	var painel_stats := PanelContainer.new()
	painel_stats.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	painel_stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	raiz.add_child(painel_stats)
	_stats = Label.new()
	_stats.theme_type_variation = "Pequeno"
	painel_stats.add_child(_stats)

	_atualizar_botoes()
	voltar.grab_focus.call_deferred()


## O SubViewport não herda as opções da janela: copiamos resolução 3D e MSAA.
func _aplicar_viewport(vp: SubViewport) -> void:
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = Settings.get_value("graphics", "render_scale")
	vp.msaa_3d = get_tree().root.msaa_3d


func _botao(pai: Control, texto: String, altura: int, acao: Callable) -> Button:
	var b := Button.new()
	b.text = texto
	b.custom_minimum_size.y = altura
	b.pressed.connect(func():
		Audio.play_ui("clique")
		acao.call())
	pai.add_child(b)
	return b


func _atualizar_botoes() -> void:
	_b_perfil.text = "Perfil: " + SettingsSchema.label(Settings.get_value("graphics", "profile"))
	_b_densidade.text = "Densidade: %d×%d" % [_vitrine.densidade, _vitrine.densidade]


func _proximo_perfil() -> void:
	var atual: String = Settings.get_value("graphics", "profile")
	var i := PERFIS.find(atual)
	Settings.set_value("graphics", "profile", PERFIS[(i + 1) % PERFIS.size()])
	_atualizar_botoes()


func _proxima_densidade() -> void:
	_vitrine.montar(_vitrine.densidade % 4 + 1)
	_atualizar_botoes()


func _process(delta: float) -> void:
	if _bench_ativo:
		_frames.append(delta * 1000.0)
		_draws.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
		_prims.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
	_acumulado += delta
	if _acumulado < 0.5:
		return
	_acumulado = 0.0
	_stats.text = "FPS %d  (%.1f ms)\nDraw calls %d\nPrimitivas %s\nMemória vídeo %s\nMemória estática %s\n%s" % [
		Engine.get_frames_per_second(), 1000.0 / maxf(Engine.get_frames_per_second(), 1.0),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		_milhares(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)),
		String.humanize_size(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED)),
		String.humanize_size(OS.get_static_memory_usage()),
		"TESTE EM ANDAMENTO…" if _bench_ativo else ""]


func _iniciar_bench() -> void:
	if _bench_ativo:
		return
	_frames.clear()
	_draws.clear()
	_prims.clear()
	_bench_ativo = true
	_camera.automatico = true
	_b_bench.disabled = true
	_resultado.text = "Medindo por %d s. Não mexa no aparelho." % DURACAO_BENCH
	await get_tree().create_timer(1.0).timeout   # aquecimento
	_frames.clear()
	_draws.clear()
	_prims.clear()
	await get_tree().create_timer(DURACAO_BENCH).timeout
	_bench_ativo = false
	_camera.automatico = false
	_b_bench.disabled = false
	_finalizar_bench()


func _finalizar_bench() -> void:
	var r := Benchmark.summarize(_frames, _draws, _prims)
	r["perfil"] = Settings.get_value("graphics", "profile")
	r["resolucao_3d"] = Settings.get_value("graphics", "render_scale")
	r["sombras"] = Settings.get_value("graphics", "shadows")
	r["msaa"] = Settings.get_value("graphics", "msaa")
	r["densidade"] = "%dx%d" % [_vitrine.densidade, _vitrine.densidade]
	r["tela"] = "%dx%d" % [get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y]
	r.merge(Benchmark.device_info())
	var caminho := Benchmark.save(r, _frames)
	_ultimo_resumo = Benchmark.text_summary(r)
	_resultado.text = _ultimo_resumo + "\nSalvo em: " + ProjectSettings.globalize_path(caminho)
	_b_copiar.disabled = false
	Log.info("benchmark", _ultimo_resumo.replace("\n", " | "))


func _milhares(n: int) -> String:
	return "%.1fk" % (n / 1000.0) if n >= 1000 else str(n)


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_cancel") or e.is_action_pressed("pause"):
		_voltar()


func _voltar() -> void:
	if _bench_ativo:
		return
	Audio.play_ui("voltar")
	SceneManager.go("menu")
