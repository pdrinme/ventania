extends SceneTree
## Navegação dos bots no mapa real (Ilha Ventania), sem combate: um bot recebe a
## ordem de ir até cada baú e cada ponto de loot do mapa (dentro das casas, nos
## andares de cima, no meio dos POIs), partindo de 30 m de distância em direções
## variadas. Mede quantos destinos ele alcança, em quanto tempo e quanto tempo
## passa sem progresso ("preso"). Também confere que ninguém atravessa paredes:
## o bot nunca termina dentro de uma peça de construção.
## Rode com --fixed-fps 30 (simulação na velocidade máxima, passo fixo de 1/30 s, sem distorcer a física).
## Uso: godot --headless --fixed-fps 30 --path game -s res://tests/integration/test_navegacao.gd -- [limite_destinos] [minimo_%]

const LIMITE_S := 40.0
var falhas := 0


func _checar(ok: bool, msg: String) -> void:
	print(("  ok  " if ok else "  FALHOU  ") + msg)
	if not ok:
		falhas += 1


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var maximo := int(args[0]) if args.size() > 0 else 9999
	var minimo := float(args[1]) if args.size() > 1 else 0.0
	await process_frame
	Engine.max_fps = 0
	var mundo := IlhaVentania.new()
	mundo.com_ambiente = false
	root.add_child(mundo)
	var server := GameServer.new(mundo, 5, "treino", {})
	root.add_child(server)
	server.start(24873, "127.0.0.1")
	for i in 5:
		await physics_frame
	var c: GameServer.Cliente = server.add_bot("medio")
	c.vit.health = 100000
	var bot: BotCerebro = c.bot
	var destinos: Array = []
	for b in mundo.chests():
		destinos.append(["baú", b[0]])
	for l in mundo.loot_points():
		destinos.append(["loot", l])
	destinos = destinos.slice(0, maximo)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var chegou := 0
	var chegou_alto := 0
	var altos := 0
	var tempo_total := 0.0
	var preso_total := 0
	var nao := []
	for d in destinos:
		var alvo: Vector3 = d[1]
		var alto := alvo.y - mundo.ground_height(alvo.x, alvo.z) > 2.5
		if alto:
			altos += 1
		# começa a 30 m, num ponto de chão livre
		var ini := alvo
		for t in 20:
			var ang := rng.randf() * TAU
			var q := Vector2(alvo.x, alvo.z) + Vector2(cos(ang), sin(ang)) * 30.0
			if mundo.inland(q.x, q.y) > 6.0 and server.nav and not server.nav.blocked(server.nav.cell_of(q)):
				ini = Vector3(q.x, mundo.ground_height(q.x, q.y) + 0.3, q.y)
				break
		c.pawn.global_position = ini
		c.pawn.velocity = Vector3.ZERO
		bot.ordem = alvo
		bot.estado = ""
		var preso_antes := int(c.stats.get("preso_ticks", 0))
		var t0 := server.tick
		var ok := false
		while (server.tick - t0) < LIMITE_S * Protocol.TICK_RATE:
			await physics_frame
			var p := c.pawn.global_position
			if Vector2(p.x - alvo.x, p.z - alvo.z).length() < 1.6 and absf(p.y - alvo.y) < 1.3:
				ok = true
				break
		var s := (server.tick - t0) / float(Protocol.TICK_RATE)
		if OS.get_environment("NAV_DEBUG") != "":
			print("    %s ini=%s alvo=%s d=%.1f ok=%s t=%.1f" % [d[0], ini.snapped(Vector3.ONE), alvo.snapped(Vector3.ONE), ini.distance_to(alvo), ok, s])
		preso_total += int(c.stats.get("preso_ticks", 0)) - preso_antes
		if ok:
			chegou += 1
			tempo_total += s
			if alto:
				chegou_alto += 1
		else:
			nao.append("%s %s%s" % [d[0], str(alvo.snapped(Vector3.ONE * 0.1)), " (andar de cima)" if alto else ""])
	var pct := 100.0 * chegou / maxf(1.0, destinos.size())
	print("  destinos: %d · alcançados: %d (%.0f%%) · em andares de cima: %d de %d · tempo médio %.1f s · preso %.0f s no total" % [
			destinos.size(), chegou, pct, chegou_alto, altos, tempo_total / maxf(1.0, chegou), preso_total / float(Protocol.TICK_RATE)])
	for n in nao.slice(0, 25):
		print("    não chegou: ", n)
	print("  A*: %d caminhos, %d expansões" % [server.nav.caminhos, server.nav.expansoes])
	_checar(pct >= minimo, "alcançou pelo menos %.0f%% dos destinos" % minimo)
	server.stop()
	print("NAVEGACAO %s %.0f%%" % ["OK" if falhas == 0 else "FALHOU", pct])
	quit(falhas)
