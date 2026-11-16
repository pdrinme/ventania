extends Control
## Primeira tela: aplica o tema, trata o modo servidor e o teste automático,
## dispara a verificação do meta-servidor (sem bloquear) e abre o menu.


func _ready() -> void:
	get_tree().root.theme = VentaniaTheme.build(Settings.is_mobile)
	get_tree().set_auto_accept_quit(true)
	Log.info("boot", "%s | %s | %s" % [Version.full(), OS.get_name(), RenderingServer.get_video_adapter_name()])

	var args := OS.get_cmdline_user_args()
	if OS.has_feature("dedicated_server") or "--servidor" in args:
		SceneManager.go("server")
		return

	var fundo := ColorRect.new()
	fundo.color = VentaniaTheme.TEAL_ESCURO
	fundo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(fundo)
	var titulo := Label.new()
	titulo.theme_type_variation = "Titulo"
	titulo.text = "VENTANIA"
	titulo.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	titulo.grow_horizontal = Control.GROW_DIRECTION_BOTH
	titulo.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(titulo)

	Meta.refresh()
	if "--teste-fumaca" in args:
		SmokeTest.new().run(get_tree())
		return
	await get_tree().create_timer(0.4).timeout
	SceneManager.go("menu")
