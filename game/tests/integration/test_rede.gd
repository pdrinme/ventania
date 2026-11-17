extends SceneTree
## ACEITE DA ETAPA 7 (parte automática): multiplayer e servidores.
## Duas salas no mesmo processo (cada uma com mundo físico próprio), como o
## servidor dedicado com --salas=2. Na sala 1: 3 jogadores (simulados, por ENet)
## + bots até 16; um deles com rede ruim simulada (atraso, variação e perda).
## Verifica: sala cheia recusa com mensagem; queda e reconexão devolvem o mesmo
## personagem (id, inventário, posição); banda por cliente medida; relevância
## reduz o que cada um recebe; pacotes de lixo e inundação expulsam o atacante
## sem afetar quem está jogando; a sala 2 é independente.
## Uso: godot --headless --path game -s res://tests/integration/test_rede.gd

var falhas := 0
var resumo := {}


func _checar(ok: bool, msg: String) -> void:
	print(("  ok  " if ok else "  FALHOU  ") + msg)
	if not ok:
		falhas += 1


func _esperar(n: int) -> void:
	for i in n:
		await physics_frame


func _sala(porta_base: int, cfg: Dictionary, max_jog: int) -> GameServer:
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	vp.size = Vector2i(2, 2)
	root.add_child(vp)
	var mundo := IlhaVentania.new()
	mundo.com_ambiente = false
	vp.add_child(mundo)
	var s := GameServer.new(mundo, 0, "br", cfg)
	s.max_jogadores = max_jog
	vp.add_child(s)
	for p in range(porta_base, porta_base + 6):
		if s.start(p, "127.0.0.1") == OK:
			return s
	return null


func _init() -> void:
	await process_frame
	Engine.max_fps = 0
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/integration/partida_rapida.json"))
	cfg["min_jogadores"] = 3
	cfg["espera_maxima_s"] = 5
	cfg["protecao_inicio_s"] = 60
	cfg["bots"] = {"preencher_ate": 16}
	var sala1 := _sala(24871, cfg, 3)
	var cfg2 := cfg.duplicate(true)
	cfg2["min_jogadores"] = 1
	cfg2["bots"] = {"preencher_ate": 4}
	var sala2 := _sala(24881, cfg2, 16)
	_checar(sala1 != null and sala2 != null, "duas salas abertas em portas diferentes")
	var p1 := sala1.peer.host.get_local_port() if sala1 else 0
	var p2 := sala2.peer.host.get_local_port() if sala2 else 0
	var Sim := load("res://tests/integration/cliente_simulado.gd")
	var sims: Array = []
	var entidades_recebidas := {}
	for i in 3:
		var s = Sim.new()
		s.nome = "Rede%d" % (i + 1)
		root.add_child(s)
		if i == 2:
			s.client.lag_ms = 120
			s.client.jitter_ms = 30
			s.client.perda = 0.02
		entidades_recebidas[s.nome] = [0, 0]
		s.client.snapshot_received.connect(func(snap):
			entidades_recebidas[s.nome][0] += snap["entities"].size()
			entidades_recebidas[s.nome][1] += 1)
		s.conectar(p1)
		sims.append(s)
	var s2 = Sim.new()
	s2.nome = "OutraSala"
	root.add_child(s2)
	s2.conectar(p2)
	for i in 300:
		await physics_frame
		if sims.all(func(s): return s.client.connected) and s2.client.connected:
			break
	_checar(sims.all(func(s): return s.client.connected), "3 jogadores na sala 1 (um com 120 ms ± 30 e 2% de perda)")
	_checar(s2.client.connected and sala2.player_count() == 1, "sala 2 independente com o próprio jogador")

	# --- sala cheia ---
	var extra := GameClient.new()
	root.add_child(extra)
	var recusa := [""]
	extra.rejected.connect(func(r): recusa[0] = r)
	extra.connect_to("127.0.0.1", p1, "Atrasado")
	for i in 120:
		await physics_frame
		extra.poll()
		if not recusa[0].is_empty():
			break
	_checar(recusa[0].begins_with("Sala cheia"), "4º jogador recusado com mensagem: \"%s\"" % recusa[0])
	extra.close()

	# --- partida: ônibus, salto e pouso (acelerado) ---
	Engine.time_scale = 3.0
	var inicio := Time.get_ticks_msec()
	while Time.get_ticks_msec() - inicio < 120000:
		await physics_frame
		if sala1.partida.estado == Protocol.MATCH_JOGO and sims.all(func(s): return s.queda == 0 and s.saltou):
			break
	Engine.time_scale = 1.0
	_checar(sala1.partida.estado == Protocol.MATCH_JOGO, "sala 1 em jogo")
	_checar(sala1.bots().size() == 13, "bots completaram a partida até 16 (%d bots)" % sala1.bots().size())
	_checar(sims[2].saltou and sims[2].queda == 0, "o cliente com rede ruim saltou e pousou")
	await _esperar(60)

	# --- reconexão ---
	var a = sims[0]
	var ca: GameServer.Cliente = sala1.client_by_id(a.client.my_id)
	var id_antes: int = a.client.my_id
	ca.inv.materials["madeira"] = 123
	var pos_antes: Vector3 = ca.pawn.global_position
	var vivos_antes: int = sala1.partida.vivos.size()
	a.client.close(false)            # queda de rede (sem despedida)
	await _esperar(20)
	var esperando := ca.desconectado_tick >= 0
	_checar(esperando and sala1.client_by_id(id_antes) == ca, "quem caiu fica no jogo esperando reconectar")
	_checar(sala1.partida.vivos.size() == vivos_antes, "a queda não eliminou o jogador")
	await _esperar(60)
	a.client.reconnect()
	var w := {}
	a.client.welcomed.connect(func(i): w.merge(i))
	for i in 300:
		await physics_frame
		if a.client.connected:
			break
	await _esperar(30)
	var cb: GameServer.Cliente = sala1.client_by_id(a.client.my_id)
	_checar(a.client.connected and w.get("reconectou", false), "reconectou com a ficha")
	_checar(a.client.my_id == id_antes and cb == ca, "mesmo id (%d -> %d) e mesmo personagem" % [id_antes, a.client.my_id])
	_checar(cb != null and cb.inv.materials["madeira"] == 123, "inventário preservado")
	_checar(cb != null and cb.pawn.global_position.distance_to(pos_antes) < 25.0, "posição preservada (%.1f m)" % (cb.pawn.global_position.distance_to(pos_antes) if cb else -1.0))
	_checar(sala1.reconexoes == 1 and sala1.humanos() == 3, "servidor: 1 reconexão, 3 humanos")
	var tick_snap: int = a.ultimo_tick
	await _esperar(30)
	_checar(a.ultimo_tick > tick_snap, "voltou a receber snapshots")

	# --- banda por cliente (20 s de jogo em tempo real) ---
	for s in entidades_recebidas:
		entidades_recebidas[s] = [0, 0]
	sala1.bandwidth(1.0)            # zera
	var t0: int = sala1.tick
	await _esperar(20 * Protocol.TICK_RATE)
	var seg := (sala1.tick - t0) / float(Protocol.TICK_RATE)
	var banda := sala1.bandwidth(seg)
	var maior := 0.0
	for id in banda:
		var b: Dictionary = banda[id]
		print("      %s: ↓ %.1f kbit/s, ↑ %.1f kbit/s" % [b["nome"], b["desce_kbps"], b["sobe_kbps"]])
		maior = maxf(maior, b["desce_kbps"])
		resumo[b["nome"]] = b
	_checar(banda.size() == 3, "banda medida para os 3 clientes")
	_checar(maior > 1.0 and maior < 160.0, "banda de descida por cliente abaixo de 160 kbit/s (máx %.1f)" % maior)
	var total_pawns := sala1.player_count()
	for s in entidades_recebidas:
		var e: Array = entidades_recebidas[s]
		print("      %s: %.1f entidades por snapshot (de %d na partida)" % [s, e[0] / maxf(1.0, e[1]), total_pawns])
	var media_ent: float = entidades_recebidas["Rede1"][0] / maxf(1.0, entidades_recebidas["Rede1"][1])
	_checar(media_ent < total_pawns, "relevância: cada cliente recebe menos entidades que o total (%.1f < %d)" % [media_ent, total_pawns])
	var c_ruim: GameServer.Cliente = sala1.client_by_id(sims[2].client.my_id)
	_checar(c_ruim != null and sala1.tick - sims[2].ultimo_tick < 30, "cliente com rede ruim continua sincronizado (atraso de %d ticks)" % (sala1.tick - sims[2].ultimo_tick))

	# --- lixo e inundação na sala 2 ---
	var tick2 := sala2.tick
	var lixo := ENetMultiplayerPeer.new()
	lixo.create_client("127.0.0.1", p2, 3, 0, 0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for i in 120:
		await physics_frame
		lixo.poll()
		if lixo.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			break
	for i in 60:
		if lixo.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
			break
		var d := PackedByteArray()
		d.resize(rng.randi_range(1, 40))
		for j in d.size():
			d[j] = rng.randi() & 255
		d[0] = [Protocol.C_INPUT, Protocol.C_INV, Protocol.C_BUILD, Protocol.C_EDIT, 200][i % 5]
		lixo.set_target_peer(1)
		lixo.transfer_mode = MultiplayerPeer.TRANSFER_MODE_RELIABLE
		lixo.put_packet(d)
		lixo.poll()
		await physics_frame
	await _esperar(30)
	_checar(sala2.expulsos == 1, "pacotes malformados: atacante expulso (%d)" % sala2.expulsos)
	lixo.close()
	var enchente := GameClient.new()
	root.add_child(enchente)
	enchente.connect_to("127.0.0.1", p2, "Enchente")
	for i in 120:
		await physics_frame
		enchente.poll()
		if enchente.connected:
			break
	var vazio := Protocol.InputCmd.new()
	print("      enchente conectada: %s" % enchente.connected)
	for f in 6:
		for i in 300:
			vazio.seq = f * 300 + i + 1
			enchente.send_inputs([vazio])
		await physics_frame
		enchente.poll()
	for i in 30:
		await physics_frame
		enchente.poll()
	_checar(sala2.expulsos == 2, "inundação de pacotes: expulso (%d)" % sala2.expulsos)
	_checar(s2.client.connected and sala2.tick > tick2, "sala 2 seguiu rodando e o jogador legítimo continua conectado")
	_checar(sims.all(func(s): return s.client.connected), "sala 1 não foi afetada")
	enchente.close()

	# --- caiu e não voltou: sai da partida depois da janela ---
	var b = sims[1]
	var id_b: int = b.client.my_id
	b.client.close(false)
	await _esperar(10)
	var cbb := sala1.client_by_id(id_b)
	var janela := GameServer.JANELA_RECONEXAO_S * Protocol.TICK_RATE
	if cbb:
		cbb.desconectado_tick = sala1.tick - janela   # adianta o relógio da janela
	await _esperar(10)
	_checar(sala1.client_by_id(id_b) == null, "fora da janela de reconexão, o jogador sai da partida")

	print("  resumo: %s" % str(resumo))
	sala1.stop()
	sala2.stop()
	print("REDE %s" % ("OK" if falhas == 0 else "FALHA (%d)" % falhas))
	quit(0 if falhas == 0 else 1)
