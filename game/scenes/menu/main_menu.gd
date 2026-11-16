extends Control
## Menu principal. Só tem botões que funcionam nesta versão; "Jogar" entra
## quando existir gameplay (Etapa 2+). O personagem do kit aparece em 3D.

var _status: Label
var _tentar: Button


func _ready() -> void:
	_mundo_3d()
	var margem := MarginContainer.new()
	margem.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for lado in ["left", "right", "top", "bottom"]:
		margem.add_theme_constant_override("margin_" + lado, 48 if Settings.is_mobile else 40)
	add_child(margem)

	var coluna := VBoxContainer.new()
	coluna.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	coluna.custom_minimum_size.x = 420 if Settings.is_mobile else 380
	margem.add_child(coluna)

	var titulo := Label.new()
	titulo.theme_type_variation = "Titulo"
	titulo.text = "VENTANIA"
	coluna.add_child(titulo)
	var sub := Label.new()
	sub.theme_type_variation = "Subtitulo"
	sub.text = "versão de teste %s" % Version.GAME
	coluna.add_child(sub)
	var espaco := Control.new()
	espaco.custom_minimum_size.y = 24
	coluna.add_child(espaco)

	var alvo: int = get_tree().root.theme.get_meta("altura_alvo", 52)
	var b1 := _botao(coluna, "Jogar: campo de treino", alvo, func(): SceneManager.go("game", {"modo": "local"}))
	_botao(coluna, "Entrar em servidor", alvo, _entrar_servidor)
	_botao(coluna, "Vitrine e teste de desempenho", alvo, func(): SceneManager.go("diagnostics"))
	_botao(coluna, "Configurações", alvo, func(): SceneManager.go("settings"))
	if not Settings.is_mobile:
		_botao(coluna, "Sair", alvo, func(): get_tree().quit())
	b1.grab_focus.call_deferred()

	var rodape := VBoxContainer.new()
	rodape.size_flags_vertical = Control.SIZE_SHRINK_END | Control.SIZE_EXPAND
	coluna.add_child(rodape)
	var linha := HBoxContainer.new()
	rodape.add_child(linha)
	_status = Label.new()
	_status.theme_type_variation = "Pequeno"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.x = 260
	linha.add_child(_status)
	_tentar = Button.new()
	_tentar.text = "Tentar de novo"
	_tentar.pressed.connect(func():
		Audio.play_ui("clique")
		Meta.refresh())
	linha.add_child(_tentar)
	Meta.status_changed.connect(_on_status)
	_on_status(Meta.state, Meta.info, Meta.last_error)
	if not SceneManager.message.is_empty():
		_aviso(SceneManager.message)
		SceneManager.message = ""


func _botao(pai: Control, texto: String, altura: int, acao: Callable) -> Button:
	var b := Button.new()
	b.text = texto
	b.custom_minimum_size.y = altura
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(func():
		Audio.play_ui("clique")
		acao.call())
	b.focus_entered.connect(func(): Audio.play_ui("foco"))
	pai.add_child(b)
	return b


## Conecta no servidor de partida configurado (Configurações → Rede).
func _entrar_servidor() -> void:
	var alvo: String = Settings.get_value("network", "game_server")
	var partes := alvo.rsplit(":", true, 1)
	var host := partes[0].strip_edges()
	var porta := Protocol.DEFAULT_PORT
	if partes.size() == 2 and partes[1].is_valid_int():
		porta = int(partes[1])
	if host.is_empty():
		_aviso("Configure o endereço em Configurações → Rede.")
		return
	SceneManager.go("game", {"modo": "remoto", "host": host, "porta": porta})


func _aviso(texto: String) -> void:
	var d := AcceptDialog.new()
	d.title = "Aviso"
	d.dialog_text = texto
	d.dialog_autowrap = true
	d.min_size = Vector2i(460, 0)
	add_child(d)
	d.popup_centered()


func _on_status(estado: String, info: Dictionary, erro: String) -> void:
	match estado:
		"online":
			_status.text = "Servidor: online (v%s)" % info.get("server_version", "?")
		"verificando":
			_status.text = "Servidor: verificando…"
		"incompatible":
			_status.text = "Servidor: incompatível. " + erro
		"offline":
			_status.text = "Servidor: offline. " + erro + " (o modo offline continua funcionando)"
		_:
			_status.text = "Servidor: —"
	_tentar.visible = estado in ["offline", "incompatible"]


func _mundo_3d() -> void:
	# o mundo 3D fica atrás da interface
	var vp_cont := SubViewportContainer.new()
	vp_cont.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vp_cont.stretch = true
	vp_cont.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vp_cont)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.msaa_3d = get_tree().root.msaa_3d
	vp.scaling_3d_scale = get_tree().root.scaling_3d_scale
	vp_cont.add_child(vp)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("8fd3ff")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("b9c6ff")
	env.ambient_light_energy = 0.35
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var sol := DirectionalLight3D.new()
	sol.rotation_degrees = Vector3(-40, -30, 0)
	sol.light_energy = 0.9
	sol.light_color = Color("fff3dc")
	sol.add_to_group("sol")
	vp.add_child(sol)

	var chao := MeshInstance3D.new()
	var disco := CylinderMesh.new()
	disco.top_radius = 1.6
	disco.bottom_radius = 1.7
	disco.height = 0.2
	disco.radial_segments = 32
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("ffc93c")
	disco.material = mat
	chao.mesh = disco
	chao.position = Vector3(1.4, -0.1, 0)
	vp.add_child(chao)

	var recruta := (load("res://assets/personagens/recruta_base_01.glb") as PackedScene).instantiate() as Node3D
	recruta.position = Vector3(1.4, 0, 0)
	recruta.rotation_degrees.y = -20
	vp.add_child(recruta)
	var aps := recruta.find_children("*", "AnimationPlayer", true, false)
	if not aps.is_empty():
		(aps[0] as AnimationPlayer).play("idle")

	var cam := Camera3D.new()
	cam.fov = 40
	vp.add_child(cam)
	cam.look_at_from_position(Vector3(0.2, 1.5, 5.2), Vector3(0.6, 1.0, 0), Vector3.UP)
