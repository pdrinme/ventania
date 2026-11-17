extends SceneTree
## Aceitação do botão Mirar no celular (simulado: --simular-celular), numa partida local:
## - o botão aparece; tocar e segurar mira (FOV menor, câmera mais perto, BTN_AIM na
##   entrada, como o botão direito do mouse no PC); soltar volta ao normal;
## - com a picareta na mão o botão fica apagado e não mira;
## - em 16:9, 20:9, 19,5:9 e 4:3 os botões visíveis não se sobrepõem nem saem da tela.
## Uso: godot --path game --rendering-driver opengl3 -s res://tests/capturar_mira_celular.gd -- <pasta> --simular-celular

var _falhas: Array[String] = []
var pasta := ""


func _init() -> void:
	pasta = OS.get_cmdline_user_args()[0]
	await process_frame
	root.theme = VentaniaTheme.build(true)
	await root.get_node("SceneManager").go("game", {"modo": "local"})
	var jogo = current_scene
	for i in 150:
		await physics_frame
		if jogo.pawn:
			break
	for i in 40:
		await physics_frame
	var toque = jogo.touch
	_conferir(toque.visible and toque._botoes.has("mirar"), "botão Mirar visível no celular")
	_conferir(ItemDB.is_weapon(jogo.combat_hud.current_item()), "arma na mão (%s)" % jogo.combat_hud.current_item())
	var fov0: float = jogo.camera.camera().fov
	_foto("mira_solta")
	var centro: Vector2 = toque._botoes["mirar"]["centro"]
	_tocar(centro, true, 3)
	for i in 30:
		await process_frame
	var cmd: Protocol.InputCmd = jogo.sampler.make_cmd(1, 0.0, 0.0)
	_conferir(jogo.camera.mirando, "segurando Mirar: câmera mirando")
	_conferir(jogo.camera.camera().fov < fov0 - 5.0, "FOV de mira (%.0f → %.0f)" % [fov0, jogo.camera.camera().fov])
	_conferir(cmd.has(Protocol.BTN_AIM), "entrada leva BTN_AIM (mesma lógica do PC)")
	_foto("mira_segurada")
	_tocar(centro, false, 3)
	for i in 30:
		await process_frame
	_conferir(not jogo.camera.mirando and not jogo.sampler.make_cmd(2, 0.0, 0.0).has(Protocol.BTN_AIM), "soltar volta ao normal")
	# picareta: botão apagado, não mira
	jogo.sampler.select_slot(Inventory.PICKAXE)
	for i in 45:
		await physics_frame
	_conferir(jogo.combat_hud.current_item() == "picareta", "picareta na mão (%s)" % jogo.combat_hud.current_item())
	_tocar(centro, true, 4)
	for i in 20:
		await process_frame
	_conferir(not jogo.camera.mirando, "com a picareta, o botão não mira")
	_foto("mira_picareta")
	_tocar(centro, false, 4)
	# proporções de tela
	for tam in [Vector2(1280, 720), Vector2(2400, 1080), Vector2(2340, 1080), Vector2(1024, 768), Vector2(960, 540)]:
		toque.size = tam
		toque._layout()
		for modo_c in [false, true]:
			toque.construcao.ativo = modo_c
			var vis: Array = toque._botoes.keys().filter(func(n): return toque._visivel(n))
			var ok := true
			for i in vis.size():
				var a: Dictionary = toque._botoes[vis[i]]
				var ca: Vector2 = a["centro"]
				if ca.x - a["raio"] < 0 or ca.y - a["raio"] < 0 or ca.x + a["raio"] > tam.x or ca.y + a["raio"] > tam.y:
					ok = false
					print("    fora da tela: %s em %s" % [vis[i], tam])
				for j in range(i + 1, vis.size()):
					var b: Dictionary = toque._botoes[vis[j]]
					if ca.distance_to(b["centro"]) < float(a["raio"]) + float(b["raio"]):
						ok = false
						print("    sobrepostos: %s × %s em %s" % [vis[i], vis[j], tam])
			_conferir(ok, "%dx%d%s: botões sem sobreposição e dentro da tela" % [tam.x, tam.y, " (construção)" if modo_c else ""])
		toque.construcao.ativo = false
	print("MIRA_CELULAR_OK" if _falhas.is_empty() else "MIRA_CELULAR_FALHOU %s" % [_falhas])
	quit(0 if _falhas.is_empty() else 1)


func _tocar(p: Vector2, apertado: bool, dedo: int) -> void:
	var e := InputEventScreenTouch.new()
	e.index = dedo
	e.position = p
	e.pressed = apertado
	Input.parse_input_event(e)


func _conferir(cond: bool, o_que: String) -> void:
	print(("  ok  " if cond else "  FALHOU  ") + o_que)
	if not cond:
		_falhas.append(o_que)


func _foto(nome: String) -> void:
	root.get_texture().get_image().save_png("%s/%s.png" % [pasta, nome])
