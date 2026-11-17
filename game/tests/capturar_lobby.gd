extends SceneTree
## Capturas do lobby (Etapa 8) com um meta-servidor de verdade rodando.
## Precisa de janela (xvfb-run). A conta já deve existir (tools/preparar_lobby.py).
## Uso: godot --path game --rendering-driver opengl3 -s res://tests/capturar_lobby.gd -- <pasta> <url_meta> <usuario> <senha>


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var pasta: String = a[0]
	await process_frame
	var meta = root.get_node("Meta")
	var sm = root.get_node("SceneManager")
	root.theme = VentaniaTheme.build(root.get_node("Settings").is_mobile)
	# 1) sem conta
	meta.base_url = a[1]
	meta.session_token = ""
	await sm.go("menu")
	await _esperar(40)
	_foto(pasta, "lobby_offline")
	var menu = root.get_child(root.get_child_count() - 1)
	menu._abrir_login()
	await _esperar(10)
	_foto(pasta, "login")
	menu._fechar_modal()
	# 2) com conta, grupo e amigos
	var r = await meta.login(a[2], a[3])
	print("login ", r["ok"], " ", r["error"])
	await _esperar(40)
	_foto(pasta, "lobby_grupo")
	menu._abrir_modos()
	await _esperar(10)
	_foto(pasta, "modos")
	menu._fechar_modal()
	menu._abrir_amigos()
	await _esperar(40)
	_foto(pasta, "amigos")
	menu._on_convite({"id": "x", "from": {"username": "Garoa"}})
	await _esperar(10)
	_foto(pasta, "convite")
	menu._abrir_missoes()
	await _esperar(40)
	_foto(pasta, "missoes")
	menu._abrir_perfil()
	await _esperar(40)
	_foto(pasta, "perfil")
	quit()


func _esperar(n: int) -> void:
	for i in n:
		await process_frame


func _foto(pasta: String, nome: String) -> void:
	root.get_texture().get_image().save_png("%s/%s.png" % [pasta, nome])
	print("CAPTURA ", nome)
