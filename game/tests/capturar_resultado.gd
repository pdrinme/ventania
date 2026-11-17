extends SceneTree
## Aceitação da tela de resultado numa partida BR local de verdade (precisa de janela):
## 1) eliminado (#2): a tela aparece com a colocação, "Assistir" disponível, mouse livre;
##    "Assistir" fecha a tela e segue um jogador.
## 2) vitória: VITÓRIA!, personagem, estatísticas; clique de MOUSE no botão principal
##    funciona (sem Esc); Enter no botão em foco também; Esc é só atalho.
## Uso: godot --path game --rendering-driver opengl3 -s res://tests/capturar_resultado.gd -- <pasta> [--simular-celular]

var pasta := ""
var jogo
var _falhas: Array[String] = []


func _init() -> void:
	pasta = OS.get_cmdline_user_args()[0]
	await process_frame
	root.theme = VentaniaTheme.build(root.get_node("Settings").is_mobile)
	await _rodada_eliminado()
	await _rodada_vitoria()
	print("RESULTADO_OK" if _falhas.is_empty() else "RESULTADO_FALHOU %s" % [_falhas])
	quit(0 if _falhas.is_empty() else 1)


func _comecar(bots: int) -> void:
	await root.get_node("SceneManager").go("game", {"modo": "br_local", "bots": bots})
	jogo = current_scene
	for i in 30 * 60:
		await physics_frame
		if jogo.server and jogo.server.partida.estado == Protocol.MATCH_ONIBUS:
			break
	jogo.server.partida.onibus.fecha = jogo.server.tick + 2       # todos saem do ônibus
	for i in 30 * 30:
		await physics_frame
		if jogo.server.partida.estado == Protocol.MATCH_JOGO:
			break
	for i in 30:
		await physics_frame


func _eu() -> GameServer.Cliente:
	for c: GameServer.Cliente in jogo.server.clientes.values():
		if c.bot == null:
			return c
	return null


func _rodada_eliminado() -> void:
	await _comecar(3)
	var eu := _eu()
	jogo.server.combat.eliminate(eu, eu.id, "")
	await _esperar_ate(func(): return jogo.match_hud.result_visible(), 120)
	await _quadros(40)
	_foto("resultado_eliminado")
	var tela: TelaResultado = jogo.match_hud.resultado
	_conferir(tela.visible, "tela aparece ao ser eliminado")
	_conferir(tela._titulo.text.begins_with("#"), "mostra a colocação (%s)" % tela._titulo.text)
	_conferir(tela._b_assistir.visible, "'Assistir' disponível com a partida em andamento")
	_conferir(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "mouse livre na tela de resultado")
	_conferir(jogo.camera.bloqueado, "câmera parada atrás da tela")
	tela._b_assistir.pressed.emit()
	await _quadros(10)
	_conferir(not tela.visible, "'Assistir' fecha a tela")
	_foto("resultado_assistindo")


func _rodada_vitoria() -> void:
	await _comecar(2)
	var eu := _eu()
	for c: GameServer.Cliente in jogo.server.clientes.values():
		if c.bot != null:
			jogo.server.combat.eliminate(c, eu.id, "")
	await _esperar_ate(func(): return jogo.match_hud.result_visible() and jogo.resultado.get("vencedor", 0) == eu.id, 200)
	await _quadros(60)
	_foto("resultado_vitoria")
	var tela: TelaResultado = jogo.match_hud.resultado
	_conferir(tela._titulo.text == "VITÓRIA!", "título de vitória (%s)" % tela._titulo.text)
	_conferir(int(jogo.resultado.get("eliminacoes", 0)) >= 1, "eliminações registradas (%d)" % int(jogo.resultado.get("eliminacoes", 0)))
	_conferir(not tela._b_assistir.visible, "sem 'Assistir' depois do fim")
	_conferir(tela._b_denovo.visible and tela._b_denovo.has_focus(), "'Jogar de novo' visível e em foco (teclado/controle)")
	_conferir(tela._b_menu.size.y >= 52, "botões com área de toque grande (%.0f px)" % tela._b_menu.size.y)
	# clique de mouse de verdade (pela fila de entrada) no "Voltar ao lobby"
	var saiu := [false]
	jogo.match_hud.back_to_menu.disconnect(jogo._sair)
	jogo.match_hud.back_to_menu.connect(func(): saiu[0] = true)
	var centro: Vector2 = tela._b_menu.get_global_rect().get_center()
	var mm := InputEventMouseMotion.new()
	mm.position = centro
	Input.parse_input_event(mm)
	for pressionado in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressionado
		ev.position = centro
		ev.global_position = centro
		Input.parse_input_event(ev)
		await _quadros(2)
	_conferir(saiu[0], "clique do mouse em 'Voltar ao lobby' funciona (sem Esc)")
	# Enter no botão em foco
	var denovo := [false]
	jogo.match_hud.play_again.disconnect(jogo._jogar_de_novo)
	jogo.match_hud.play_again.connect(func(): denovo[0] = true)
	tela._b_denovo.grab_focus()
	await _quadros(2)
	for pressionado in [true, false]:
		var k := InputEventAction.new()
		k.action = "ui_accept"
		k.pressed = pressionado
		Input.parse_input_event(k)
		await _quadros(2)
	_conferir(denovo[0], "Enter/botão A no botão em foco funciona")


func _conferir(cond: bool, o_que: String) -> void:
	print(("  ok  " if cond else "  FALHOU  ") + o_que)
	if not cond:
		_falhas.append(o_que)


func _quadros(n: int) -> void:
	for i in n:
		await process_frame


func _esperar_ate(f: Callable, n: int) -> void:
	for i in n:
		if f.call():
			return
		await physics_frame


func _foto(nome: String) -> void:
	root.get_texture().get_image().save_png("%s/%s.png" % [pasta, nome])
	print("FOTO ", nome)
