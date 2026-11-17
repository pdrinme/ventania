class_name SmokeTest
extends Node
## Teste de fumaça do jogo real (com autoloads): boot -> menu -> configurações
## -> mudar opções -> vitrine (densidade 2, benchmark curto) -> menu -> sair.
## Rodar: godot --headless --path game -- --teste-fumaca
## Código de saída 0 = passou.

var _falhas: PackedStringArray = []


func run(tree: SceneTree) -> void:
	# preso à raiz para sobreviver às trocas de cena
	name = "TesteFumaca"
	tree.root.add_child.call_deferred(self)
	await tree.process_frame
	Log.info("fumaca", "início")
	await _ir(tree, "menu")
	_checar(tree.current_scene != null and tree.current_scene.name == "main_menu", "menu abriu")

	await _ir(tree, "settings")
	_checar(tree.current_scene.name == "settings_menu", "configurações abriu")
	Settings.set_value("graphics", "profile", "quality")
	_checar(Settings.get_value("graphics", "render_scale") == 1.0, "perfil quality aplica render_scale 1.0")
	_checar(is_equal_approx(tree.root.scaling_3d_scale, 1.0), "resolução 3D aplicada na janela")
	Settings.set_value("graphics", "render_scale", 0.6)
	_checar(Settings.get_value("graphics", "profile") == "custom", "mudar opção vira perfil custom")
	Settings.set_value("audio", "master", 0.0)
	_checar(AudioServer.is_bus_mute(AudioServer.get_bus_index("Master")), "volume 0 silencia o Master")
	Settings.set_value("audio", "master", 0.8)
	Settings.set_value("graphics", "show_fps", true)
	_checar(SceneManager._fps.get_parent().visible, "mostrar FPS liga o contador")
	Settings.set_value("graphics", "show_fps", false)
	var tecla := InputEventKey.new()
	tecla.physical_keycode = KEY_F
	InputManager.remap("jump", tecla)
	_checar(InputMap.action_has_event("jump", tecla), "remapear pulo para F")
	InputManager.reset_bindings()
	_checar(not InputMap.action_has_event("jump", tecla), "restaurar atalhos")
	Settings.set_value("graphics", "profile", "performance")

	await _ir(tree, "diagnostics")
	_checar(tree.current_scene.name == "diagnostics", "vitrine abriu")
	var vitrine := tree.current_scene.find_children("*", "KitShowcase", true, false)
	_checar(vitrine.size() == 1, "vitrine montada")
	if vitrine.size() == 1:
		(vitrine[0] as KitShowcase).montar(2)
		await tree.process_frame
		_checar((vitrine[0] as KitShowcase).blocos() == 4, "densidade 2x2")
		_checar(tree.get_nodes_in_group("camera_principal").size() == 1, "câmera no grupo camera_principal")
		var cam := tree.get_nodes_in_group("camera_principal")[0] as Camera3D
		_checar(is_equal_approx(cam.far, Settings.get_value("graphics", "view_distance")), "distância de visão aplicada na câmera")
	for i in 30:
		await tree.process_frame

	var r := Benchmark.summarize(PackedFloat32Array([16.0, 16.0, 33.0]), PackedInt32Array([10, 20, 30]), PackedInt32Array([1, 2, 3]))
	var caminho := Benchmark.save(r, PackedFloat32Array([16.0, 16.0, 33.0]), "user://teste_fumaca")
	_checar(FileAccess.file_exists(caminho), "benchmark salva JSON")

	await _jogar(tree)
	await _jogar_br(tree)

	await _ir(tree, "menu")
	_checar(tree.current_scene.name == "main_menu", "voltou ao menu")
	Settings.save_now()
	_checar(FileAccess.file_exists(Settings.PATH), "configurações salvas em disco")

	if _falhas.is_empty():
		print("FUMACA_OK")
		tree.quit(0)
	else:
		for f in _falhas:
			printerr("FUMACA_FALHA: " + f)
		tree.quit(1)


## Partida local: andar, pular, comparar predição x servidor, 2º jogador entra e sai.
func _jogar(tree: SceneTree) -> void:
	var ok: bool = await SceneManager.go("game", {"modo": "local"})
	_checar(ok, "abrir partida local")
	var jogo := tree.current_scene
	for i in 150:
		if jogo.pawn != null:
			break
		await tree.physics_frame
	_checar(jogo.pawn != null, "conectou no servidor local e recebeu o personagem")
	if jogo.pawn == null:
		return
	for i in 20:
		await tree.physics_frame
	var inicio: Vector3 = jogo.pawn.global_position
	Input.action_press("move_forward")
	for i in 45:
		await tree.physics_frame
	Input.action_release("move_forward")
	var srv_c: GameServer.Cliente = jogo.server.clientes.values()[0]
	_checar(srv_c.descartados == 0 and srv_c.inventados == 0, "servidor não perdeu nem inventou entradas (perdidas %d, inventadas %d)" % [srv_c.descartados, srv_c.inventados])
	for i in 20:
		await tree.physics_frame
	var andou: float = inicio.distance_to(jogo.pawn.global_position)
	_checar(andou > 3.0, "andou para a frente (%.1f m)" % andou)
	var srv_pawn: Pawn = jogo.server.clientes.values()[0].pawn
	var erro: float = srv_pawn.global_position.distance_to(jogo.pawn.global_position)
	_checar(erro < 0.15, "predição bate com o servidor (erro %.3f m)" % erro)
	_checar(jogo.correction_count() <= 1, "predição sem correções (%d)" % jogo.correction_count())

	var y0: float = jogo.pawn.global_position.y
	var pulo := InputEventAction.new()
	pulo.action = "jump"
	pulo.pressed = true
	Input.parse_input_event(pulo)
	var maximo := y0
	for i in 30:
		await tree.physics_frame
		maximo = maxf(maximo, jogo.pawn.global_position.y)
	_checar(maximo - y0 > 1.0, "pulou (%.2f m)" % (maximo - y0))

	# segundo jogador conecta no mesmo servidor
	var outro := GameClient.new()
	tree.root.add_child(outro)
	outro.connect_to("127.0.0.1", jogo.local_port, "Teste2")
	var seq := 0
	for i in 120:
		await tree.physics_frame
		outro.poll()
		if outro.connected:
			seq += 1
			var c := Protocol.InputCmd.new()
			c.seq = seq
			outro.send_inputs([c])
		if jogo.remote_player_count() == 1:
			break
	_checar(outro.connected, "segundo jogador conectou")
	_checar(jogo.remote_player_count() == 1, "jogador 1 vê o jogador 2")
	_checar(jogo.server.player_count() == 2, "servidor com 2 jogadores")
	outro.close()
	outro.queue_free()
	for i in 90:
		await tree.physics_frame
		if jogo.remote_player_count() == 0:
			break
	_checar(jogo.remote_player_count() == 0, "jogador 2 saiu e sumiu da tela")

	await _combate(tree, jogo)


## Combate: começa com a pistola, mira num boneco de treino e atira.
func _combate(tree: SceneTree, jogo) -> void:
	_checar(jogo.combat_hud.current_item() == "faisca", "começa com a pistola Faísca")
	_checar(jogo.remote_player_count() == 0 and jogo._remotos.size() == CampoTreino.DUMMIES.size(), "bonecos de treino visíveis")
	_checar(not jogo._loot.is_empty(), "itens no chão recebidos (%d)" % jogo._loot.size())
	var alvo: Vector3 = CampoTreino.DUMMIES[1] + Vector3(0, 1.0, 0)
	for tentativa in 3:
		var p: Vector3 = jogo.pawn.global_position + Vector3(0, Combat.EYE_STAND, 0)
		var d := alvo - p
		jogo.camera.yaw = rad_to_deg(atan2(-d.x, -d.z))
		jogo.camera.pitch = rad_to_deg(atan2(d.y, Vector2(d.x, d.z).length()))
		var r := Combat.aim_ray(jogo.pawn.global_position, false, jogo.camera.yaw_rad(), jogo.camera.pitch_rad())
		d = alvo - (r["origin"] as Vector3)   # corrige o deslocamento do ombro
		jogo.camera.yaw = rad_to_deg(atan2(-d.x, -d.z))
		jogo.camera.pitch = rad_to_deg(atan2(d.y, Vector2(d.x, d.z).length()))
	var antes: int = jogo.hits_confirmed
	var mag_antes: int = jogo._status["slots"][0]["mag"]
	Input.action_press("fire")
	for i in 3:
		await tree.physics_frame
	Input.action_release("fire")
	for i in 20:
		await tree.physics_frame
	_checar(jogo.fx.active_tracers() > 0 or jogo.hits_confirmed > antes, "traçante do disparo criado")
	_checar(jogo.hits_confirmed > antes, "tiro acertou o boneco (acertos confirmados: %d)" % (jogo.hits_confirmed - antes))
	_checar(jogo._status["slots"][0]["mag"] == mag_antes - 1, "pistola semiautomática gastou 1 bala (%d -> %d)" % [mag_antes, jogo._status["slots"][0]["mag"]])

	# baú: aproxima, segura Interagir, o personagem alcança a alça e o servidor abre
	var cli: GameServer.Cliente = jogo.server.clientes.values()[0]
	var bau: Vector3 = CampoTreino.CHESTS[3][0]
	var frente := Basis(Vector3.UP, deg_to_rad(CampoTreino.CHESTS[3][1])) * Vector3(0, 0, 1)
	cli.pawn.global_position = bau + frente * 1.5
	jogo.pawn.global_position = bau + frente * 1.5
	for i in 8:
		await tree.physics_frame
	var loot_antes: int = jogo._loot.size()
	var loot_srv_antes: int = jogo.server.loot.loot.size()
	var municao_antes: int = cli.inv.ammo.values().reduce(func(a, b): return a + b, 0)
	Input.action_press("interact")
	var viu_alcance := false
	for i in 30:
		await tree.physics_frame
		await tree.process_frame
		viu_alcance = viu_alcance or jogo.visual.rig.action == Protocol.ACT_CHEST
		if jogo.chests.is_open(3):
			break
	Input.action_release("interact")
	for i in 10:
		await tree.physics_frame
	_checar(viu_alcance, "personagem alcança a alça enquanto segura Interagir")
	_checar(jogo.chests.is_open(3) and jogo.server.loot.chests[3]["open"], "baú aberto pelo servidor e no cliente")
	# 4 itens saem do baú; caixas de munição que caem ao lado do jogador são coletadas na hora
	var municao_depois: int = cli.inv.ammo.values().reduce(func(a, b): return a + b, 0)
	var coletadas := 1 if municao_depois > municao_antes else 0
	_checar(jogo.server.loot.loot.size() + coletadas >= loot_srv_antes + 4, "baú liberou 4 itens no servidor")
	_checar(jogo._loot.size() + coletadas >= loot_antes + 4, "cliente recebeu os itens do baú (%d -> %d, %d coletado)" % [loot_antes, jogo._loot.size(), coletadas])
	_checar(jogo.visual.rig.ik_d.influence > 0.5, "mão direita presa à arma (IK ativo)")
	await _picareta_e_inventario(tree, jogo)


func _quadros_tree(tree: SceneTree, n: int) -> void:
	for i in n:
		await tree.process_frame


func _apertar(acao: String) -> void:
	var ev := InputEventAction.new()
	ev.action = acao
	ev.pressed = true
	Input.parse_input_event(ev)
	var solta := InputEventAction.new()
	solta.action = acao
	Input.parse_input_event(solta)


## Picareta (seleção, golpe, impacto confirmado, visto por outro jogador) e
## inventário (abrir, largar, recusar a picareta, pegar de volta), tudo pela rede.
func _picareta_e_inventario(tree: SceneTree, jogo) -> void:
	var cli: GameServer.Cliente = jogo.server.clientes.values()[0]
	_checar(jogo.combat_hud._picareta.item == "picareta", "barra: picareta no 1º espaço à esquerda")
	_apertar("pickaxe")
	for i in 20:
		await tree.physics_frame
		if jogo._status.get("selected", 0) == Protocol.SELECTED_PICKAXE:
			break
	_checar(cli.inv.pickaxe_selected() and jogo.combat_hud.current_item() == "picareta", "tecla dedicada seleciona a picareta (servidor confirmou)")
	_checar(jogo.combat_hud._picareta.selecionado and not jogo.combat_hud._slots[0].selecionado, "destaque no 1º espaço")
	for i in 20:
		await tree.process_frame
	_checar(jogo.visual.held_index() == ItemDB.index_of("picareta"), "picareta na mão do personagem")
	# diante da parede de madeira da cabana, golpeia segurando o botão
	var pos := Vector3(-16.55, 0.1, -10.2)
	cli.pawn.global_position = pos
	jogo.pawn.global_position = pos
	jogo.camera.yaw = 0.0
	jogo.camera.pitch = 0.0
	for i in 6:
		await tree.physics_frame
	var fx_antes: int = jogo.fx.melee_impacts
	var viu_golpe := false
	Input.action_press("fire")
	for i in 45:
		await tree.physics_frame
		await tree.process_frame
		viu_golpe = viu_golpe or jogo.visual.rig.action in [Protocol.ACT_SWING, Protocol.ACT_SWING_B]
	Input.action_release("fire")
	for i in 15:
		await tree.physics_frame
	_checar(viu_golpe, "animação do golpe na mão do personagem")
	_checar(jogo.melee_local >= 2 and jogo.fx.melee_impacts > fx_antes, "impacto imediato previsto no cliente (%d)" % jogo.melee_local)
	_checar(jogo.melee_confirmed >= 2 and jogo.melee_confirmed == cli.melee_hits, "servidor confirmou cada impacto, sem duplicar (%d / %d)" % [jogo.melee_confirmed, cli.melee_hits])
	_checar(cli.swings == cli.melee_hits, "um impacto por golpe (%d golpes)" % cli.swings)

	# outro jogador com a picareta: o primeiro vê a picareta e o golpe dele
	var outro := GameClient.new()
	tree.root.add_child(outro)
	outro.connect_to("127.0.0.1", jogo.local_port, "Teste3")
	var seq := 0
	var viu_remoto := false
	var idx_pic := ItemDB.index_of("picareta")
	for i in 150:
		await tree.physics_frame
		await tree.process_frame
		outro.poll()
		if outro.connected:
			seq += 1
			var c := Protocol.InputCmd.new()
			c.seq = seq
			c.slot = Protocol.SLOT_PICKAXE if seq < 3 else 0
			c.buttons = Protocol.BTN_FIRE if seq > 10 else 0
			outro.send_inputs([c])
			var r: Dictionary = jogo._remotos.get(outro.my_id, {})
			if not r.is_empty():
				var v: PawnVisual = r["visual"]
				viu_remoto = viu_remoto or (v.held_index() == idx_pic and v.rig.action in [Protocol.ACT_SWING, Protocol.ACT_SWING_B])
	_checar(viu_remoto, "jogador remoto aparece com a picareta e golpeando")
	outro.close()
	outro.queue_free()

	# inventário: abre, larga a pistola, a picareta é recusada, pega a pistola de volta
	var resultados := []
	jogo.client.inventory_result.connect(func(r): resultados.append(r))
	jogo._inventario(true)
	_checar(jogo.inventario.is_open() and jogo.sampler.inventario_aberto, "tela de inventário abre")
	cli.pawn.global_position = Vector3(30, 0, 40)
	jogo.pawn.global_position = Vector3(30, 0, 40)
	for i in 6:
		await tree.physics_frame
	jogo._pedido_inventario({"op": Protocol.OP_DROP, "a": 0, "n": 1})
	jogo._pedido_inventario({"op": Protocol.OP_DROP, "a": Protocol.SEM_ESPACO, "n": 1})
	for i in 20:
		await tree.physics_frame
		if resultados.size() >= 2:
			break
	_checar(resultados.size() == 2 and resultados[0]["code"] == Inventory.Err.OK, "servidor largou a pistola")
	_checar(resultados.size() == 2 and resultados[1]["code"] == Inventory.Err.NOT_DROPPABLE, "servidor recusou largar a picareta")
	_checar(jogo._status["slots"][0]["item"] == 0, "espaço 1 vazio no HUD depois de largar")
	var largada := -1
	for v: LootVisual in jogo._loot.values():
		if ItemDB.id_of(v.data["item"]) == "faisca" and v.data["pos"].distance_to(Vector3(30, 0, 40)) < 2.5:
			largada = v.data["id"]
	_checar(largada >= 0, "pistola largada aparece no chão para todos")
	jogo._atualizar_proximos()
	_checar(jogo.inventario._proximos.any(func(l): return l["id"] == largada), "tela lista o item próximo")
	jogo._pedido_inventario({"op": Protocol.OP_PICKUP, "loot": largada, "b": Protocol.SEM_ESPACO})
	for i in 20:
		await tree.physics_frame
		if resultados.size() >= 3:
			break
	_checar(resultados.size() >= 3 and resultados[2]["code"] == Inventory.Err.OK, "pegou de volta pela tela de inventário")
	_checar(ItemDB.id_of(jogo._status["slots"][0]["item"]) == "faisca", "pistola de volta no espaço 1")
	jogo._inventario(false)
	_checar(not jogo.inventario.is_open() and not jogo.sampler.inventario_aberto, "tela de inventário fecha")
	await _construcao(tree, jogo)


## Construção pelo caminho real das teclas: modo construção, piso sob os pés,
## parede à frente, edição (porta) e picareta derrubando a parede.
func _construcao(tree: SceneTree, jogo) -> void:
	var cli: GameServer.Cliente = jogo.server.clientes.values()[0]
	var pos := Vector3(42, 0.1, 42)
	cli.pawn.global_position = pos
	jogo.pawn.global_position = pos
	jogo.camera.yaw = 0.0
	jogo.camera.pitch = -60.0
	for i in 8:
		await tree.physics_frame
	var madeira: int = jogo._status["materials"][0]
	_checar(madeira >= 10, "treino dá materiais para construir (%d de madeira)" % madeira)
	var golpes_antes := cli.swings
	var balas_antes: int = jogo._status["slots"][0]["mag"]
	_apertar("build_mode")
	await _quadros_tree(tree, 3)
	_checar(jogo.modo_build.ativo and jogo.sampler.modo_construcao, "Q liga o modo construção")
	_apertar("slot_2")
	await _quadros_tree(tree, 3)
	_checar(jogo.modo_build.escolha == 1, "tecla 2 escolhe o piso")
	var n_antes: int = jogo.server.build.estado.count_players()
	Input.action_press("fire")
	for i in 3:
		await tree.physics_frame
	Input.action_release("fire")
	for i in 12:
		await tree.physics_frame
	_checar(jogo.server.build.estado.count_players() == n_antes + 1, "piso construído no servidor")
	_checar(jogo.build.estado.occupied(Grade.PISO, Vector3i(10, 0, 10)), "piso apareceu no cliente, sob os pés")
	_checar(jogo._status["materials"][0] == madeira - 10, "custou 10 de madeira")
	_checar(cli.swings == golpes_antes and jogo._status["slots"][0]["mag"] == balas_antes, "Atirar no modo construção não usou a arma nem a picareta")
	_apertar("slot_1")
	jogo.camera.pitch = 0.0
	await tree.process_frame
	Input.action_press("fire")
	for i in 3:
		await tree.physics_frame
	Input.action_release("fire")
	for i in 70:
		await tree.physics_frame
	var parede: int = jogo.build.estado.por_slot.get(Grade.key(Grade.PAREDE_X, Vector3i(10, 0, 10)), -1)
	_checar(parede >= 0, "parede construída à frente (Grade.target)")
	# edição: G mirando na parede, Atirar no ladrilho do meio, G confirma
	_apertar("edit_mode")
	await _quadros_tree(tree, 3)
	_checar(jogo.modo_build.editando == parede, "G entra na edição da própria parede (mira: %s)" % str(jogo.modo_build.aimed_piece()))
	jogo.modo_build.toggle_tile_index(4)
	jogo.modo_build.toggle_tile_index(1)
	_apertar("edit_mode")
	for i in 12:
		await tree.physics_frame
	_checar(jogo.build.estado.pecas.has(parede) and jogo.build.estado.pecas[parede].mask == 511 & ~((1 << 1) | (1 << 4)), "porta confirmada pelo servidor e aplicada no cliente")
	_apertar("build_mode")
	await _quadros_tree(tree, 3)
	_checar(not jogo.modo_build.ativo and not jogo.sampler.modo_construcao, "Q desliga o modo construção")
	# picareta na parede (madeira 150 = 3 golpes) até cair
	_apertar("pickaxe")
	for i in 20:
		await tree.physics_frame
	var destruidas: int = jogo.fx.pecas_destruidas
	jogo.camera.pitch = 38.0        # parte de cima da parede (o meio agora é a porta)
	Input.action_press("fire")
	for i in Combat.melee_swing_steps() * 4:
		await tree.physics_frame
	Input.action_release("fire")
	for i in 15:
		await tree.physics_frame
	_checar(not jogo.build.estado.pecas.has(parede), "a picareta derrubou a parede (vida %s)" % str(jogo.server.build.estado.pecas[parede].hp if jogo.server.build.estado.pecas.has(parede) else 0))
	_checar(jogo.fx.pecas_destruidas > destruidas, "efeito de destruição no cliente")


## Battle Royale local na Ilha Ventania: mapa vindo do servidor, contagem, início
## da partida (só picareta, longe da espera), Tormenta, HUD da partida e fim.
func _jogar_br(tree: SceneTree) -> void:
	await _ir(tree, "menu")
	var ok: bool = await SceneManager.go("game", {"modo": "br_local", "bots": 0})
	_checar(ok, "abrir Battle Royale local")
	var jogo = tree.current_scene
	for i in 200:
		await tree.physics_frame
		if jogo.pawn:
			break
	_checar(jogo.mundo is IlhaVentania, "cliente montou a Ilha Ventania anunciada pelo servidor")
	_checar(jogo.match_hud._mini.visible, "minimapa visível")
	var viu_contagem := false
	for i in 30 * 25:
		await tree.physics_frame
		var e: int = jogo._partida.get("estado", -1)
		viu_contagem = viu_contagem or e == Protocol.MATCH_CONTAGEM
		if e == Protocol.MATCH_ONIBUS:
			break
	_checar(viu_contagem, "contagem regressiva antes da partida")
	_checar(jogo._partida.get("estado", -1) == Protocol.MATCH_ONIBUS, "partida começou no Ônibus de Batalha")
	for i in 20:
		await tree.physics_frame
		await tree.process_frame
	_checar(jogo.pawn.queda == Pawn.NO_ONIBUS and not jogo.visual.visible, "jogador dentro do ônibus (invisível, câmera no ônibus)")
	_checar(jogo._onibus_vis != null and jogo._onibus_vis.visible and jogo.camera.alvo == jogo._onibus_vis, "ônibus desenhado e seguido pela câmera")
	var ab: float = jogo.onibus.abre
	for i in 30 * 30:
		await tree.physics_frame
		if jogo.server_tick_now() > ab + 5:
			break
	_apertar("jump")
	var viu_queda := false
	var viu_planador := false
	for i in 30 * 40:
		await tree.physics_frame
		viu_queda = viu_queda or jogo.pawn.queda == Pawn.QUEDA_LIVRE
		viu_planador = viu_planador or jogo.pawn.queda == Pawn.PLANADOR
		if jogo.pawn.queda == 0 and viu_queda:
			break
	_checar(viu_queda, "Pular com as portas abertas: saltou (queda livre)")
	_checar(viu_planador, "planador abriu perto do chão")
	_checar(jogo.pawn.queda == 0 and jogo.pawn.grounded, "pousou na ilha (y %.1f, chão %.1f)" % [jogo.pawn.global_position.y, jogo.mundo.ground_height(jogo.pawn.global_position.x, jogo.pawn.global_position.z)])
	for i in 30 * 40:
		await tree.physics_frame
		if jogo._partida.get("estado", -1) == Protocol.MATCH_JOGO:
			break
	_checar(jogo._partida.get("estado", -1) == Protocol.MATCH_JOGO, "o ônibus partiu e a partida seguiu")
	for i in 20:
		await tree.physics_frame
		await tree.process_frame
	_checar(jogo.tormenta.active() and jogo.tormenta.visible, "Tormenta recebida e desenhada")
	_checar(jogo.match_hud._topo.text.begins_with("1 vivo"), "HUD da partida: %s" % jogo.match_hud._topo.text)
	_checar(jogo.combat_hud.current_item() == "picareta", "começa só com a picareta na mão")
	_checar(jogo._status["slots"].all(func(sl): return sl["item"] == 0), "inventário vazio no início da partida")
	_checar(jogo.server.loot.loot.size() > 40, "loot do mapa sorteado (%d itens)" % jogo.server.loot.loot.size())
	var cli: GameServer.Cliente = jogo.server.clientes.values()[0]
	cli.pawn.global_position = Vector3(250, jogo.mundo.ground_height(250, 250) + 0.3, 250)
	for i in 10:
		await tree.physics_frame
		await tree.process_frame
	_checar(jogo.tormenta.is_outside(jogo.pawn.global_position) or not jogo.server.partida.tormenta.is_outside(cli.pawn.global_position),
			"cliente e servidor concordam sobre estar fora da zona")
	jogo.server.combat.eliminate(cli, cli.id, "")
	for i in 60:
		await tree.physics_frame
		if not jogo.resultado.is_empty() and jogo._partida.get("estado", -1) == Protocol.MATCH_FIM:
			break
	_checar(not jogo.resultado.is_empty(), "tela de resultado recebida (#%d de %d)" % [jogo.resultado.get("colocacao", 0), jogo.resultado.get("total", 0)])
	_checar(jogo._partida.get("estado", -1) == Protocol.MATCH_FIM, "partida terminou")
	_checar(jogo.match_hud._res_titulo.text != "VITÓRIA!", "eliminado sozinho não é vitória")


func _ir(tree: SceneTree, cena: String) -> void:
	var ok: bool = await SceneManager.go(cena)
	_checar(ok, "trocar para " + cena)
	for i in 3:
		await tree.process_frame


func _checar(cond: bool, nome: String) -> void:
	if cond:
		print("  ok  " + nome)
	else:
		_falhas.append(nome)
		printerr("  FALHOU  " + nome)
