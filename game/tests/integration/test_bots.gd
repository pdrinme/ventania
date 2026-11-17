extends SceneTree
## ACEITE DA ETAPA 6: partidas simuladas headless só com bots (23) no mapa real,
## servidor autoritativo (os bots usam as mesmas entradas e regras dos humanos).
## Verifica que a partida termina sem travar, que os bots saltam do ônibus, saqueiam,
## combatem, curam e fogem da Tormenta; imprime métricas por dificuldade e o custo
## de CPU por bot. Tempos da Tormenta encurtados. Rode com --fixed-fps 30: simulação na velocidade
## máxima com o passo do jogo (time_scale distorcia a física: passo de 0,13 s).
## Uso: godot --headless --fixed-fps 30 --path game -s res://tests/integration/test_bots.gd -- [bots=23] [partidas=1] [completa]
## "completa": usa a Tormenta real (data/partida.json, ~10 min de jogo).

var falhas := 0


func _checar(ok: bool, msg: String) -> void:
	print(("  ok  " if ok else "  FALHOU  ") + msg)
	if not ok:
		falhas += 1


func _init() -> void:
	var n := 23
	var partidas := 1
	var completa := false
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		n = int(args[0])
	if args.size() > 1:
		partidas = int(args[1])
	completa = "completa" in args
	await process_frame
	Engine.max_fps = 0
	var mundo := IlhaVentania.new()
	mundo.com_ambiente = false
	root.add_child(mundo)
	var cfg: Dictionary = PartidaBR.carregar_config() if completa else JSON.parse_string(FileAccess.get_file_as_string("res://tests/integration/partida_rapida.json"))
	cfg["min_jogadores"] = 0
	cfg["espera_maxima_s"] = 1
	cfg["contagem_s"] = 1
	cfg["fim_s"] = 2
	cfg["somente_bots"] = true
	cfg["protecao_inicio_s"] = 0 if completa else 10
	cfg["bots"] = {"preencher_ate": n}
	var server := GameServer.new(mundo, 77, "br", cfg)
	root.add_child(server)
	_checar(server.start(24871, "127.0.0.1") == OK, "servidor BR (só bots) abriu")
	var inicio := Time.get_ticks_msec()
	var limite_ms := (1800000 if completa else 900000) * partidas
	while server.partida.historico.size() < partidas and Time.get_ticks_msec() - inicio < limite_ms:
		await physics_frame
	var real := (Time.get_ticks_msec() - inicio) / 1000.0
	_checar(server.partida.historico.size() == partidas, "%d partida(s) terminaram (%.0f s reais)" % [server.partida.historico.size(), real])
	var por_dif := {}
	for h in server.partida.historico:
		print("  partida %d: %d bots, %.0f s de jogo, Tormenta fase %d, vencedor %d, %d saltaram / %d ejetados" % [
				h["partida"], h["total"], h["duracao_s"], h["fase_tormenta"], h["vencedor"], h["saltaram"], h["ejetados"]])
		_checar(h["vencedor"] != 0, "partida %d teve vencedor" % h["partida"])
		_checar(h["saltaram"] + h["ejetados"] == h["total"], "todos deixaram o ônibus")
		for id in h["metricas"]:
			var m: Dictionary = h["metricas"][id]
			var d: String = m.get("dificuldade", "?")
			if not por_dif.has(d):
				por_dif[d] = {"n": 0, "colocacao": 0.0, "elim": 0, "saques": 0, "curas": 0, "dano": 0, "tormenta": 0, "construcoes": 0, "tempo": 0.0, "vitorias": 0, "preso": 0, "episodios": 0}
			var a: Dictionary = por_dif[d]
			a["n"] += 1
			a["colocacao"] += float(m["colocacao"])
			a["elim"] += int(m["eliminacoes"])
			a["saques"] += int(m.get("saques", 0))
			a["curas"] += int(m.get("curas", 0))
			a["dano"] += int(m.get("dano", 0))
			a["tormenta"] += int(m.get("dano_tormenta", 0))
			a["construcoes"] += int(m.get("construcoes", 0))
			a["tempo"] += float(m["tempo_s"])
			a["vitorias"] += 1 if m["colocacao"] == 1 else 0
			a["preso"] += int(m.get("preso_ticks", 0))
			a["episodios"] += int(m.get("preso_episodios", 0))
	# comportamentos (soma de todos os bots de todas as partidas)
	var comp := {}
	for h in server.partida.historico:
		for id in h["metricas"]:
			for k in h["metricas"][id]:
				if str(k).begins_with("estado_") or k in ["recuperacoes", "manobras", "abandonos", "andar_cima_s", "preso_episodios"]:
					comp[k] = int(comp.get(k, 0)) + int(h["metricas"][id][k])
	print("  COMPORTAMENTOS (vezes que entraram em cada estado, soma dos bots): %s" % str(comp))
	print("  MÉTRICAS POR DIFICULDADE (médias por bot):")
	var tot := {"saques": 0, "curas": 0, "elim": 0, "tormenta": 0}
	for d in ["facil", "medio", "dificil"]:
		if not por_dif.has(d):
			continue
		var a: Dictionary = por_dif[d]
		var k: float = a["n"]
		print("    %-8s n=%2d colocação %.1f · eliminações %.2f · vitórias %d · saques %.1f · curas %.2f · dano causado %.0f · dano da Tormenta %.0f · tempo vivo %.0f s · paredes %d · preso %.1f s (%d episódios > 2 s, %.1f%% do tempo vivo)" % [
				d, a["n"], a["colocacao"] / k, a["elim"] / k, a["vitorias"], a["saques"] / k, a["curas"] / k, a["dano"] / k, a["tormenta"] / k, a["tempo"] / k, a["construcoes"], a["preso"] / k / Protocol.TICK_RATE, a["episodios"],
				100.0 * a["preso"] / Protocol.TICK_RATE / maxf(1.0, a["tempo"])])
		for c in tot:
			tot[c] += a["elim" if c == "elim" else c] if c != "tormenta" else a["tormenta"]
	_checar(tot["saques"] > n, "bots saqueiam (%d itens pegos)" % tot["saques"])
	_checar(tot["elim"] > 0, "bots combatem e eliminam (%d eliminações)" % tot["elim"])
	_checar(tot["curas"] > 0, "bots usam cura/escudo (%d)" % tot["curas"])
	if completa:
		_checar(int(comp.get("estado_cobertura", 0)) > 0, "bots procuram cobertura (%d vezes)" % int(comp.get("estado_cobertura", 0)))
		_checar(int(comp.get("estado_perseguir", 0)) + int(comp.get("estado_investigar", 0)) > 0, "bots perseguem a última posição vista / investigam tiros (%d)" % (int(comp.get("estado_perseguir", 0)) + int(comp.get("estado_investigar", 0))))
		_checar(int(comp.get("estado_tormenta", 0)) > 0, "bots fogem da Tormenta (%d)" % int(comp.get("estado_tormenta", 0)))
		_checar(int(comp.get("andar_cima_s", 0)) > 0, "bots sobem aos andares de cima (%d s somados)" % int(comp.get("andar_cima_s", 0)))
	var preso_pct := 0.0
	var vivo := 0.0
	var preso := 0.0
	for d in por_dif:
		vivo += por_dif[d]["tempo"]
		preso += por_dif[d]["preso"] / float(Protocol.TICK_RATE)
	preso_pct = 100.0 * preso / maxf(1.0, vivo)
	_checar(preso_pct < 1.0, "bots presos (> 3 s sem progresso) menos de 1%% do tempo vivo (%.2f%%)" % preso_pct)
	if por_dif.has("facil") and por_dif.has("dificil"):
		var cf: float = por_dif["facil"]["colocacao"] / por_dif["facil"]["n"]
		var cd: float = por_dif["dificil"]["colocacao"] / por_dif["dificil"]["n"]
		print("  colocação média: fácil %.1f × difícil %.1f (menor = melhor)" % [cf, cd])
	# custo de CPU
	var ms_tick := server.tempo_tick_us / 1000.0 / maxf(1.0, server.ticks_medidos)
	var ms_bots := server.tempo_bots_us / 1000.0 / maxf(1.0, server.ticks_medidos)
	print("  CPU: tick médio %.2f ms (orçamento 33,3 ms) · cérebros %.3f ms/tick = %.4f ms por bot por tick · A* %d caminhos, %d expansões" % [
			ms_tick, ms_bots, ms_bots / n, server.nav.caminhos if server.nav else 0, server.nav.expansoes if server.nav else 0])
	_checar(ms_tick < 33.3, "tick cabe no orçamento com %d bots" % n)
	server.stop()
	print("BOTS %s" % ("OK" if falhas == 0 else "FALHA (%d)" % falhas))
	quit(0 if falhas == 0 else 1)
