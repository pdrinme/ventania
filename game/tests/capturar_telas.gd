extends SceneTree
## Captura imagens das telas (precisa de janela; no Linux sem tela use xvfb-run).
## Uso: godot --path game --rendering-driver opengl3 -s res://tests/capturar_telas.gd -- <pasta_saida>


func _init() -> void:
	var pasta := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://capturas"
	await process_frame
	# autoloads existem em tempo de execução, mas não como identificadores neste script
	root.theme = VentaniaTheme.build(root.get_node("Settings").is_mobile)
	for cena in ["menu", "settings", "diagnostics"]:
		await root.get_node("SceneManager").go(cena)
		for i in 20:
			await process_frame
		var img := root.get_texture().get_image()
		img.save_png("%s/tela_%s.png" % [pasta, cena])
		print("CAPTURA ", cena)
	quit()
