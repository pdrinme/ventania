extends Control
## Tela de configurações. Os controles são montados a partir do SettingsSchema;
## cada mudança é aplicada na hora e salva automaticamente.
## Layout por plataforma: o PC mostra janela, vsync, mouse, controle e atalhos;
## o celular mostra sensibilidade do toque e tamanho dos botões de toque.

const ABAS := [["Gráficos", "graphics"], ["Áudio", "audio"], ["Controles", "controls"], ["Interface", "interface"], ["Servidor", "network"]]

var _widgets := {}          # "section/key" -> Control
var _atualizando := false
var _capturando := ""       # ação aguardando nova tecla
var _botoes_atalho := {}    # ação -> Button
var _aviso_atalho: Label
var _status_rede: Label
var _abas: TabContainer


func _ready() -> void:
	var fundo := ColorRect.new()
	fundo.color = VentaniaTheme.TEAL_ESCURO
	fundo.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(fundo)

	var margem := MarginContainer.new()
	margem.set_anchors_preset(Control.PRESET_FULL_RECT)
	for lado in ["left", "right", "top", "bottom"]:
		margem.add_theme_constant_override("margin_" + lado, 32)
	add_child(margem)
	var coluna := VBoxContainer.new()
	margem.add_child(coluna)

	var topo := HBoxContainer.new()
	coluna.add_child(topo)
	var voltar := Button.new()
	voltar.text = "‹ Voltar"
	voltar.custom_minimum_size = Vector2(160, _altura())
	voltar.pressed.connect(_voltar)
	topo.add_child(voltar)
	var titulo := Label.new()
	titulo.theme_type_variation = "Subtitulo"
	titulo.text = "Configurações"
	titulo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	topo.add_child(titulo)
	var restaurar := Button.new()
	restaurar.text = "Restaurar aba"
	restaurar.custom_minimum_size.y = _altura()
	restaurar.pressed.connect(_restaurar_aba)
	topo.add_child(restaurar)

	_abas = TabContainer.new()
	_abas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	coluna.add_child(_abas)
	for aba in ABAS:
		var rolagem := ScrollContainer.new()
		rolagem.name = aba[0]
		rolagem.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		_abas.add_child(rolagem)
		var lista := VBoxContainer.new()
		lista.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rolagem.add_child(lista)
		for key in SettingsSchema.SPEC[aba[1]]:
			_criar_campo(lista, aba[1], key)
		if aba[1] == "controls" and not Settings.is_mobile:
			_criar_atalhos(lista)
		if aba[1] == "network":
			_criar_rede(lista)
		if aba[1] == "graphics":
			_info_graficos(lista)

	Settings.changed.connect(_on_changed)
	InputManager.bindings_changed.connect(_atualizar_atalhos)
	voltar.grab_focus.call_deferred()


func _altura() -> int:
	return get_tree().root.theme.get_meta("altura_alvo", 52)


func _visivel(section: String, key: String) -> bool:
	var s: Dictionary = SettingsSchema.SPEC[section][key]
	if s.get("pc_only", false) and Settings.is_mobile:
		return false
	if s.get("mobile_only", false) and not Settings.is_mobile:
		return false
	return s["type"] != "dict"


func _linha(pai: Control, texto: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.custom_minimum_size.y = _altura()
	pai.add_child(h)
	var l := Label.new()
	l.text = texto
	l.custom_minimum_size.x = 340 if Settings.is_mobile else 320
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(l)
	return h


func _criar_campo(pai: Control, section: String, key: String) -> void:
	if not _visivel(section, key):
		return
	var s: Dictionary = SettingsSchema.SPEC[section][key]
	var h := _linha(pai, SettingsSchema.label(key))
	var v: Variant = Settings.get_value(section, key)
	var w: Control
	match s["type"]:
		"float":
			var caixa := HBoxContainer.new()
			caixa.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var slider := HSlider.new()
			slider.min_value = s["min"]
			slider.max_value = s["max"]
			slider.step = s["step"]
			slider.value = v
			slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			var valor := Label.new()
			valor.custom_minimum_size.x = 90
			valor.text = _formatar(key, v)
			slider.value_changed.connect(func(x):
				valor.text = _formatar(key, x)
				if not _atualizando:
					Settings.set_value(section, key, x))
			caixa.add_child(slider)
			caixa.add_child(valor)
			slider.set_meta("rotulo", valor)
			w = slider
			h.add_child(caixa)
		"int_enum", "str_enum":
			var op := OptionButton.new()
			op.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			op.custom_minimum_size.y = _altura() - 8
			var opcoes: Array = s["options"]
			for i in opcoes.size():
				op.add_item(_formatar(key, opcoes[i]), i)
			op.selected = opcoes.find(v)
			op.item_selected.connect(func(i):
				Audio.play_ui("clique")
				if not _atualizando:
					Settings.set_value(section, key, opcoes[i]))
			w = op
			h.add_child(op)
		"bool":
			var cb := CheckButton.new()
			cb.button_pressed = v
			cb.toggled.connect(func(x):
				Audio.play_ui("clique")
				if not _atualizando:
					Settings.set_value(section, key, x))
			w = cb
			h.add_child(cb)
		"string":
			var le := LineEdit.new()
			le.text = v
			le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			le.text_submitted.connect(func(x): Settings.set_value(section, key, x))
			le.focus_exited.connect(func(): Settings.set_value(section, key, le.text))
			w = le
			h.add_child(le)
	_widgets["%s/%s" % [section, key]] = w


func _formatar(key: String, v: Variant) -> String:
	match key:
		"render_scale", "master", "music", "sfx", "ui":
			return "%d%%" % roundi(float(v) * 100)
		"ui_scale", "mouse_sensitivity", "gamepad_sensitivity", "touch_sensitivity":
			return "%.2fx" % float(v)
		"view_distance":
			return "%d m" % roundi(float(v))
		"msaa":
			return "Desligado" if int(v) == 0 else "%dx" % int(v)
		"fps_limit":
			return "Sem limite" if int(v) == 0 else "%d" % int(v)
	return SettingsSchema.label(v)


## Reflete mudanças vindas de outro lugar (ex.: escolher um perfil muda os sliders).
func _on_changed(section: String, key: String, value: Variant) -> void:
	var w: Control = _widgets.get("%s/%s" % [section, key])
	if w == null:
		return
	_atualizando = true
	if w is HSlider:
		(w as HSlider).value = value
		(w.get_meta("rotulo") as Label).text = _formatar(key, value)
	elif w is OptionButton:
		(w as OptionButton).selected = (SettingsSchema.SPEC[section][key]["options"] as Array).find(value)
	elif w is CheckButton:
		(w as CheckButton).set_pressed_no_signal(value)
	elif w is LineEdit and not w.has_focus():
		(w as LineEdit).text = value
	_atualizando = false


func _info_graficos(pai: Control) -> void:
	var l := Label.new()
	l.theme_type_variation = "Pequeno"
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.text = "Escolher um perfil preenche as opções abaixo. Mudar qualquer opção deixa o perfil como \"Personalizado\". Teste o resultado em \"Vitrine e teste de desempenho\"."
	pai.add_child(l)


func _criar_atalhos(pai: Control) -> void:
	var t := Label.new()
	t.theme_type_variation = "Subtitulo"
	t.text = "Atalhos de teclado e mouse"
	pai.add_child(t)
	_aviso_atalho = Label.new()
	_aviso_atalho.theme_type_variation = "Pequeno"
	_aviso_atalho.text = "Clique em um atalho e pressione a nova tecla ou botão do mouse (Esc cancela)."
	pai.add_child(_aviso_atalho)
	for acao in InputDefaults.ACTIONS:
		if not InputDefaults.ACTIONS[acao]["remap"]:
			continue
		var h := _linha(pai, InputDefaults.ACTIONS[acao]["label"])
		var b := Button.new()
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func(): _iniciar_captura(acao))
		h.add_child(b)
		_botoes_atalho[acao] = b
	var reset := Button.new()
	reset.text = "Restaurar atalhos padrão"
	reset.custom_minimum_size.y = _altura()
	reset.pressed.connect(func():
		Audio.play_ui("voltar")
		InputManager.reset_bindings())
	pai.add_child(reset)
	_atualizar_atalhos()


func _atualizar_atalhos() -> void:
	for acao in _botoes_atalho:
		var nomes := InputManager.keyboard_events(acao).map(func(e): return InputSerializer.describe(e))
		(_botoes_atalho[acao] as Button).text = " / ".join(nomes) if not nomes.is_empty() else "—"


func _iniciar_captura(acao: String) -> void:
	Audio.play_ui("clique")
	_capturando = acao
	(_botoes_atalho[acao] as Button).text = "Pressione…"


func _input(e: InputEvent) -> void:
	if _capturando.is_empty():
		if e.is_action_pressed("ui_cancel"):
			get_viewport().set_input_as_handled()
			_voltar()
		return
	var valido: bool = (e is InputEventKey and e.pressed and not e.echo) or (e is InputEventMouseButton and e.pressed)
	if not valido:
		return
	get_viewport().set_input_as_handled()
	var acao := _capturando
	_capturando = ""
	if e is InputEventKey and (e as InputEventKey).physical_keycode == KEY_ESCAPE:
		_atualizar_atalhos()
		return
	var limpo := InputSerializer.from_dict(InputSerializer.to_dict(e))
	var perdeu := InputManager.remap(acao, limpo)
	Audio.play_ui("confirmar")
	if not perdeu.is_empty():
		_aviso_atalho.text = "\"%s\" usava esse atalho e voltou ao padrão." % InputDefaults.ACTIONS[perdeu]["label"]


func _criar_rede(pai: Control) -> void:
	var l := Label.new()
	l.theme_type_variation = "Pequeno"
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.text = "Endereço do meta-servidor (ex.: http://192.168.0.10:8080 na sua rede local). Sem servidor, o jogo funciona offline."
	pai.add_child(l)
	var b := Button.new()
	b.text = "Testar conexão"
	b.custom_minimum_size.y = _altura()
	b.pressed.connect(func():
		Audio.play_ui("clique")
		var w: LineEdit = _widgets["network/server_url"]
		Settings.set_value("network", "server_url", w.text)
		Meta.refresh())
	pai.add_child(b)
	_status_rede = Label.new()
	_status_rede.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pai.add_child(_status_rede)
	var sobre := Label.new()
	sobre.theme_type_variation = "Pequeno"
	sobre.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sobre.text = "%s\n%s · %s\nFonte Fredoka (SIL OFL 1.1). Arte, sons e código originais do projeto." % [
		Version.full(), OS.get_name(), RenderingServer.get_video_adapter_name()]
	pai.add_child(sobre)
	Meta.status_changed.connect(_on_rede)
	_on_rede(Meta.state, Meta.info, Meta.last_error)


func _on_rede(estado: String, info: Dictionary, erro: String) -> void:
	var textos := {"online": "Conectado: servidor v%s, protocolo %s" % [info.get("server_version", "?"), info.get("protocol_version", "?")],
			"verificando": "Verificando…", "offline": "Sem conexão: " + erro, "incompatible": erro}
	_status_rede.text = textos.get(estado, "")


func _restaurar_aba() -> void:
	Audio.play_ui("voltar")
	Settings.reset_section(ABAS[_abas.current_tab][1])
	if ABAS[_abas.current_tab][1] == "controls":
		InputManager.reset_bindings()


func _voltar() -> void:
	Audio.play_ui("voltar")
	Settings.save_now()
	SceneManager.go("menu")
