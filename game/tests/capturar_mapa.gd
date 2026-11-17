extends SceneTree
## Mapa da partida numa partida BR local (precisa de janela): minimapa com nomes e a
## região atual em cada POI, mapa completo com as 6 regiões coloridas, nomes, zona
## e Tormenta. Confere que a região detectada é a do POI onde o jogador está.
## Uso: godot --path game --rendering-driver opengl3 -s res://tests/capturar_mapa.gd -- <pasta> [--simular-celular]

var _falhas: Array[String] = []


func _init() -> void:
	var pasta: String = OS.get_cmdline_user_args()[0]
	var cel := "--simular-celular" in OS.get_cmdline_user_args()
	await process_frame
	root.theme = VentaniaTheme.build(root.get_node("Settings").is_mobile)
	var t0 := Time.get_ticks_msec()
	await root.get_node("SceneManager").go("game", {"modo": "br_local", "bots": 2})
	var jogo = current_scene
	for i in 30 * 60:
		await physics_frame
		if jogo.server and jogo.server.partida.estado == Protocol.MATCH_ONIBUS:
			break
	jogo.server.partida.onibus.fecha = jogo.server.tick + 2
	for i in 30 * 30:
		await physics_frame
		if jogo.server.partida.estado == Protocol.MATCH_JOGO:
			break
	print("carregou e começou em %.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	var eu: GameServer.Cliente
	for c: GameServer.Cliente in jogo.server.clientes.values():
		if c.bot == null:
			eu = c
		else:
			c.vit.health = 100000
	var sufixo := "_cel" if cel else ""
	for poi in jogo.mundo.points_of_interest():
		var p: Vector3 = poi["pos"]
		eu.pawn.global_position = Vector3(p.x + 3, jogo.mundo.ground_height(p.x + 3, p.z + 3) + 3.0, p.z + 3)
		eu.pawn.velocity = Vector3.ZERO
		eu.pawn.queda = 0
		for i in 45:
			await physics_frame
		var r: Dictionary = jogo.mundo.region_at(jogo.pawn.global_position.x, jogo.pawn.global_position.z)
		_conferir(r.get("id", "") == poi["id"], "região detectada em %s (%s)" % [poi["nome"], r.get("nome", "nenhuma")])
		_conferir(jogo.match_hud._regiao.visible and jogo.match_hud._regiao.text == poi["nome"], "chip da região: %s" % jogo.match_hud._regiao.text)
		root.get_texture().get_image().save_png("%s/mini_%s%s.png" % [pasta, poi["id"], sufixo])
	# fora de qualquer região (campo aberto entre POIs)
	eu.pawn.global_position = Vector3(-60, jogo.mundo.ground_height(-60, -60) + 3.0, -60)
	for i in 45:
		await physics_frame
	_conferir(not jogo.match_hud._regiao.visible, "fora das regiões: sem chip (%s)" % str(jogo.mundo.region_at(-60, -60).get("nome", "")))
	jogo.match_hud.toggle_map(true)
	for i in 10:
		await process_frame
	root.get_texture().get_image().save_png("%s/mapa_completo%s.png" % [pasta, sufixo])
	for poi in jogo.mundo.points_of_interest():
		_conferir((poi["limite"] as PackedVector2Array).size() >= 12, "%s tem contorno (%d pontos)" % [poi["nome"], poi["limite"].size()])
	print("MAPA_OK" if _falhas.is_empty() else "MAPA_FALHOU %s" % [_falhas])
	quit(0 if _falhas.is_empty() else 1)


func _conferir(cond: bool, o_que: String) -> void:
	print(("  ok  " if cond else "  FALHOU  ") + o_que)
	if not cond:
		_falhas.append(o_que)
