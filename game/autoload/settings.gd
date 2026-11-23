extends Node
## Configurações do jogador: guarda (SettingsStore), salva em user:// e aplica
## no motor (janela, resolução 3D, FPS, áudio) e no mundo (sombras, distância).
##
## O mundo participa por grupos:
##   "sol"              DirectionalLight3D principal
##   "camera_principal" Camera3D do jogador
##   "ambiente"         WorldEnvironment

signal changed(section: String, key: String, value: Variant)

const PATH := "user://settings.json"

var store: SettingsStore
var is_mobile := false
var _salvar_pendente := false


func _ready() -> void:
	is_mobile = OS.has_feature("mobile") or OS.has_feature("android") or "--simular-celular" in OS.get_cmdline_user_args()
	store = SettingsStore.new(is_mobile)
	var carregou := store.load_file(PATH)
	Log.info("config", "configurações %s (%s)" % ["carregadas" if carregou else "padrão", "celular" if is_mobile else "PC"])
	store.changed.connect(_on_store_changed)
	apply_all()
	get_tree().node_added.connect(_on_node_added)


func get_value(section: String, key: String) -> Variant:
	return store.get_value(section, key)


func set_value(section: String, key: String, value: Variant) -> void:
	store.set_value(section, key, value)


func reset_section(section: String) -> void:
	store.reset_section(section)


func _on_store_changed(section: String, key: String, value: Variant) -> void:
	_apply_key(section, key)
	changed.emit(section, key, value)
	_agendar_salvar()


## Junta várias mudanças seguidas (ex.: arrastar um slider) em um único salvamento.
func _agendar_salvar() -> void:
	if _salvar_pendente:
		return
	_salvar_pendente = true
	await get_tree().create_timer(0.5).timeout
	_salvar_pendente = false
	save_now()


func save_now() -> void:
	var e := store.save(PATH)
	if e != OK:
		Log.error("config", "falha ao salvar configurações: %s" % error_string(e))


func apply_all() -> void:
	for section in SettingsSchema.SPEC:
		for key in SettingsSchema.SPEC[section]:
			_apply_key(section, key)
	apply_to_world(get_tree().root)


func _apply_key(section: String, key: String) -> void:
	var v: Variant = store.get_value(section, key)
	var vp := get_tree().root
	match [section, key]:
		["graphics", "render_scale"]:
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
			vp.scaling_3d_scale = v
		["graphics", "msaa"]:
			vp.msaa_3d = {0: Viewport.MSAA_DISABLED, 2: Viewport.MSAA_2X, 4: Viewport.MSAA_4X}[v]
		["graphics", "fps_limit"]:
			Engine.max_fps = v
		["graphics", "vsync"]:
			if DisplayServer.get_name() != "headless":
				DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if v else DisplayServer.VSYNC_DISABLED)
		["graphics", "window_mode"]:
			if not is_mobile and DisplayServer.get_name() != "headless":
				var modo := DisplayServer.WINDOW_MODE_FULLSCREEN if v == "fullscreen" else DisplayServer.WINDOW_MODE_WINDOWED
				if DisplayServer.window_get_mode() != modo:
					DisplayServer.window_set_mode(modo)
		["graphics", "shadows"], ["graphics", "view_distance"], ["graphics", "detail"]:
			apply_to_world(vp)
		["graphics", "show_fps"]:
			var sm := get_node_or_null("/root/SceneManager")
			if sm:
				sm.set_fps_visible(v)
		["interface", "ui_scale"]:
			vp.content_scale_factor = v
		["audio", _]:
			Audio.set_bus_volume(key, v)


func apply_to_world(raiz: Node) -> void:
	for n in raiz.get_tree().get_nodes_in_group("sol"):
		_aplicar_sol(n)
	for n in raiz.get_tree().get_nodes_in_group("camera_principal"):
		_aplicar_camera(n)
	for n in raiz.get_tree().get_nodes_in_group("ambiente"):
		_aplicar_ambiente(n)
	for n in raiz.get_tree().get_nodes_in_group("kit_visual"):
		_aplicar_detalhe(n)


func _on_node_added(n: Node) -> void:
	# grupos definidos na cena já existem quando o nó entra na árvore
	if n.is_in_group("sol"):
		_aplicar_sol.call_deferred(n)
	elif n.is_in_group("camera_principal"):
		_aplicar_camera.call_deferred(n)
	elif n.is_in_group("ambiente"):
		_aplicar_ambiente.call_deferred(n)
	elif n.is_in_group("kit_visual"):
		_aplicar_detalhe.call_deferred(n)


func _aplicar_sol(n: Node) -> void:
	var sol := n as DirectionalLight3D
	if sol == null:
		return
	var s: String = store.get_value("graphics", "shadows")
	sol.shadow_enabled = s != "off"
	if s == "low":
		sol.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
		sol.directional_shadow_max_distance = 35.0
		RenderingServer.directional_shadow_atlas_set_size(1024, false)
	elif s == "high":
		sol.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		sol.directional_shadow_max_distance = 80.0
		RenderingServer.directional_shadow_atlas_set_size(2048, false)


## Detalhes do cenário num grupo visual do KitInstancer (MultiMeshInstance3D):
## distância de detalhe e, na vegetação decorativa, a densidade (instâncias visíveis).
func _aplicar_detalhe(n: Node) -> void:
	var mmi := n as MultiMeshInstance3D
	if mmi == null or not is_instance_valid(mmi) or mmi.multimesh == null:
		return
	var f := GraphicsProfiles.detail_factors(store.get_value("graphics", "detail"))
	if mmi.has_meta("vis_base"):
		mmi.visibility_range_end = float(mmi.get_meta("vis_base")) * float(f[0])
	if mmi.get_meta("vegetacao", false):
		mmi.multimesh.visible_instance_count = maxi(1, ceili(mmi.multimesh.instance_count * float(f[1])))


## Fator de partículas dos efeitos (Detalhes do cenário).
func particle_factor() -> float:
	return float(GraphicsProfiles.detail_factors(store.get_value("graphics", "detail"))[2])


func _aplicar_camera(n: Node) -> void:
	var cam := n as Camera3D
	if cam:
		cam.far = store.get_value("graphics", "view_distance")


func _aplicar_ambiente(n: Node) -> void:
	var we := n as WorldEnvironment
	if we and we.environment:
		# neblina de profundidade: começa na metade da distância de visão e
		# cobre o corte da câmera; objetos próximos ficam nítidos
		var dist: float = store.get_value("graphics", "view_distance")
		var env := we.environment
		env.fog_enabled = true
		env.fog_mode = Environment.FOG_MODE_DEPTH
		env.fog_depth_begin = dist * 0.5
		env.fog_depth_end = dist
		env.fog_depth_curve = 1.0
		env.fog_density = 1.0
		# acabamento por nível de detalhe: tonemap suave (médio/alto) e brilho leve
		# nas partes claras (só alto). Baixo: nada, o mais barato possível.
		var detalhe: String = store.get_value("graphics", "detail")
		# efeitos de pintura por pixel nos shaders do kit e do terreno
		RenderingServer.global_shader_parameter_set("detalhe_arte", 0.0 if detalhe == "baixo" else 1.0)
		# troca de LOD das malhas mais cedo nos níveis baixos (personagens, construções)
		var vp := we.get_viewport()
		if vp:
			vp.mesh_lod_threshold = {"baixo": 6.0, "medio": 2.5}.get(detalhe, 1.0)
		env.tonemap_mode = Environment.TONE_MAPPER_LINEAR if detalhe == "baixo" else Environment.TONE_MAPPER_FILMIC
		env.tonemap_exposure = 1.0 if detalhe == "baixo" else 1.05
		env.tonemap_white = 1.4
		env.glow_enabled = detalhe == "alto"
		env.glow_intensity = 0.35
		env.glow_bloom = 0.04
		env.glow_hdr_threshold = 1.1
		env.adjustment_enabled = detalhe == "alto"
		# céu em degradê só de médio para cima; no baixo, fundo de cor chapada (barato)
		if env.sky:
			env.background_mode = Environment.BG_COLOR if detalhe == "baixo" else Environment.BG_SKY
		env.adjustment_saturation = 1.08
		env.adjustment_contrast = 1.04
