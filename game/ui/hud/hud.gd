class_name GameHud
extends Control
## HUD da partida: mira, ping, número de jogadores, dicas de controle (PC),
## mensagens e menu de pausa. No celular, mostra também o botão de pausa.

signal resume_requested
signal quit_requested

var _info: Label
var _dica: Label
var _mensagem: Label
var _pausa: PanelContainer
var _botao_pausa: Button
var _continuar: Button
var _msg_t := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var mira := Control.new()
	mira.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	mira.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mira.draw.connect(func():
		mira.draw_arc(Vector2.ZERO, 7.0, 0, TAU, 24, Color(0.14, 0.15, 0.17, 0.8), 4.0)
		mira.draw_arc(Vector2.ZERO, 7.0, 0, TAU, 24, Color(1, 1, 1, 0.95), 2.0))
	add_child(mira)

	_info = Label.new()
	_info.theme_type_variation = "Pequeno"
	_info.position = Vector2(16, 30)
	var sb := VentaniaTheme._caixa(Color(VentaniaTheme.TINTA, 0.45), 12, Color.TRANSPARENT, 0, 0)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	_info.add_theme_stylebox_override("normal", sb)
	_info.add_theme_color_override("font_outline_color", Color("24252c"))
	_info.add_theme_constant_override("outline_size", 6)
	add_child(_info)

	_dica = Label.new()
	_dica.theme_type_variation = "Pequeno"
	_dica.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 12)
	_dica.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_dica.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_dica.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dica.add_theme_color_override("font_outline_color", Color("24252c"))
	_dica.add_theme_constant_override("outline_size", 6)
	add_child(_dica)

	_mensagem = Label.new()
	_mensagem.theme_type_variation = "Subtitulo"
	_mensagem.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 90)
	_mensagem.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_mensagem.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mensagem.add_theme_color_override("font_outline_color", Color("24252c"))
	_mensagem.add_theme_constant_override("outline_size", 8)
	add_child(_mensagem)

	_botao_pausa = Button.new()
	_botao_pausa.text = "II"
	_botao_pausa.custom_minimum_size = Vector2(64, 64)
	_botao_pausa.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 16)
	_botao_pausa.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_botao_pausa.pressed.connect(func(): show_pause(true))
	add_child(_botao_pausa)

	_criar_pausa()
	device_changed(InputManager.device)
	InputManager.device_changed.connect(device_changed)


func _criar_pausa() -> void:
	_pausa = PanelContainer.new()
	_pausa.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_pausa.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_pausa.grow_vertical = Control.GROW_DIRECTION_BOTH
	_pausa.visible = false
	add_child(_pausa)
	var col := VBoxContainer.new()
	col.custom_minimum_size.x = 360
	_pausa.add_child(col)
	var t := Label.new()
	t.theme_type_variation = "Subtitulo"
	t.text = "Pausa"
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(t)
	var alvo: int = get_tree().root.theme.get_meta("altura_alvo", 52)
	_continuar = Button.new()
	_continuar.text = "Continuar"
	_continuar.custom_minimum_size.y = alvo
	_continuar.pressed.connect(func():
		Audio.play_ui("clique")
		resume_requested.emit())
	col.add_child(_continuar)
	var sair := Button.new()
	sair.text = "Sair para o menu"
	sair.custom_minimum_size.y = alvo
	sair.pressed.connect(func():
		Audio.play_ui("voltar")
		quit_requested.emit())
	col.add_child(sair)
	var obs := Label.new()
	obs.theme_type_variation = "Pequeno"
	obs.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	obs.text = "A partida continua rodando no servidor enquanto o menu está aberto."
	col.add_child(obs)


func show_pause(v: bool) -> void:
	_pausa.visible = v
	if v:
		_continuar.grab_focus.call_deferred()


func is_paused() -> bool:
	return _pausa.visible


func device_changed(d: String) -> void:
	_botao_pausa.visible = d == "toque"
	match d:
		"teclado_mouse":
			_dica.text = "WASD mover · Espaço pular · Shift correr · Ctrl agachar · Botão direito mirar · Esc pausa"
		"controle":
			_dica.text = "Analógico esquerdo mover · A pular · L3 correr · R3 agachar · LT mirar · Start pausa"
		_:
			_dica.text = ""


func set_info(ping_ms: int, jogadores: int, extra := "") -> void:
	var p := "—" if ping_ms < 0 else "%d ms" % ping_ms
	_info.text = "Ping %s · Jogadores %d%s" % [p, jogadores, extra]


func flash(msg: String, segundos := 2.5) -> void:
	_mensagem.text = msg
	_msg_t = segundos


func _process(delta: float) -> void:
	if _msg_t > 0.0:
		_msg_t -= delta
		if _msg_t <= 0.0:
			_mensagem.text = ""
