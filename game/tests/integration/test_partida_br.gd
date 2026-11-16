extends SceneTree
## ACEITE DA ETAPA 4: partida Battle Royale COMPLETA com clientes simulados, no
## mapa de verdade (Ilha Ventania), servidor autoritativo por ENet: espera ->
## contagem -> jogo (loot, Tormenta, eliminações) -> vencedor -> resultados ->
## nova partida. Tempos da Tormenta encurtados e simulação acelerada (time_scale).
## Uso: godot --headless --path game -s res://tests/integration/test_partida_br.gd -- [jogadores=6] [--externo=PORTA]
## --externo: os clientes entram num servidor dedicado já rodando (outro processo,
## iniciado com --modo=br --config=res://tests/integration/partida_rapida.json);
## as verificações são feitas só pelo que os clientes recebem.

var falhas := 0


func _checar(ok: bool, msg: String) -> void:
	print(("  ok  " if ok else "  FALHOU  ") + msg)
	if not ok:
		falhas += 1


func _init() -> void:
	var n := 6
	var externo := 0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--externo="):
			externo = int(a.trim_prefix("--externo="))
		elif a.is_valid_int():
			n = int(a)
	await process_frame
	Engine.max_fps = 0
	if externo:
		await _externo(n, externo)
		return
	var mundo := IlhaVentania.new()
	mundo.com_ambiente = false
	root.add_child(mundo)
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/integration/partida_rapida.json"))
	cfg["min_jogadores"] = n
	var server := GameServer.new(mundo, 99, "br", cfg)
	root.add_child(server)
	var porta := 0
	for p in [24851, 24852, 24853, 24854]:
		if server.start(p, "127.0.0.1") == OK:
			porta = p
			break
	_checar(porta > 0, "servidor BR abriu porta")
	var bots: Array = []
	var Bot := load("res://tests/integration/cliente_simulado.gd")
	for i in n:
		var b = Bot.new()
		b.nome = "Sim%d" % (i + 1)
		root.add_child(b)
		b.conectar(porta)
		bots.append(b)
	Engine.time_scale = 4.0
	var inicio := Time.get_ticks_msec()
	var viu := {"espera": false, "contagem": false, "onibus": false, "jogo": false, "fim": false, "reiniciou": false}
	var tormenta_no_onibus := false
	var fases_vistas := {}
	var vivos_min := 99
	while Time.get_ticks_msec() - inicio < 420000:
		await physics_frame
		var e := server.partida.estado
		viu["espera"] = viu["espera"] or e == Protocol.MATCH_ESPERA
		viu["contagem"] = viu["contagem"] or e == Protocol.MATCH_CONTAGEM
		viu["jogo"] = viu["jogo"] or e == Protocol.MATCH_JOGO
		viu["onibus"] = viu["onibus"] or e == Protocol.MATCH_ONIBUS
		tormenta_no_onibus = tormenta_no_onibus or (e == Protocol.MATCH_ONIBUS and server.partida.tormenta != null)
		if e == Protocol.MATCH_JOGO:
			fases_vistas[server.partida.tormenta.fase] = true
			if server.partida.tormenta.fechando:
				fases_vistas["fechou"] = true
			vivos_min = mini(vivos_min, server.partida.vivos.size())
		if e == Protocol.MATCH_FIM:
			viu["fim"] = true
		if viu["fim"] and e == Protocol.MATCH_ESPERA:
			viu["reiniciou"] = true
			break
	Engine.time_scale = 1.0
	var segundos := (Time.get_ticks_msec() - inicio) / 1000.0
	_checar(viu["espera"] and viu["contagem"] and viu["onibus"] and viu["jogo"] and viu["fim"], "passou por espera, contagem, ônibus, jogo e fim")
	_checar(not tormenta_no_onibus, "a Tormenta só começou depois de o ônibus partir")
	_checar(viu["reiniciou"], "depois do fim, voltou à espera (nova partida)")
	_checar(server.partida.historico.size() == 1, "uma partida registrada")
	if server.partida.historico.is_empty():
		_fim()
		return
	var h: Dictionary = server.partida.historico[0]
	print("  partida: %d jogadores, %.0f s de jogo, Tormenta na fase %d, vencedor %d" % [h["total"], h["duracao_s"], h["fase_tormenta"], h["vencedor"]])
	_checar(h["total"] == n, "todos os %d clientes participaram" % n)
	print("  ônibus: %d saltaram por conta própria, %d ejetados no fim da rota" % [h["saltaram"], h["ejetados"]])
	_checar(h["saltaram"] + h["ejetados"] == n, "todos deixaram o ônibus (saltando ou ejetados)")
	_checar(h["saltaram"] >= n / 2, "saltos individuais, cada um no seu momento (%d)" % h["saltaram"])
	_checar(bots.filter(func(b): return b.viu_planador).size() == n, "todos abriram o planador antes de pousar")
	_checar(h["vencedor"] != 0, "há um vencedor")
	var colocacoes := []
	var elim_total := 0
	for id in h["colocacoes"]:
		colocacoes.append(h["colocacoes"][id]["colocacao"])
		elim_total += h["colocacoes"][id]["eliminacoes"]
	colocacoes.sort()
	_checar(colocacoes == range(1, n + 1), "colocações 1..%d sem repetição (%s)" % [n, str(colocacoes)])
	_checar(fases_vistas.has("fechou"), "a Tormenta começou a fechar durante a partida (fases vistas: %s)" % str(fases_vistas.keys()))
	var pegaram := bots.filter(func(b): return b.pegou > 0).size()
	var atiraram := bots.filter(func(b): return b.atirou > 0).size()
	print("  clientes que pegaram arma: %d, que atiraram: %d; eliminações por jogadores: %d" % [pegaram, atiraram, elim_total])
	_checar(pegaram > 0, "clientes coletaram loot do mapa (pelo inventário)")
	var com_resultado := bots.filter(func(b): return not b.resultado.is_empty()).size()
	_checar(com_resultado == n, "todos receberam a tela de resultado (%d/%d)" % [com_resultado, n])
	var venc := bots.filter(func(b): return b.resultado.get("colocacao", 0) == 1)
	_checar(venc.size() == 1, "exatamente um cliente recebeu 1º lugar")
	_checar(bots.all(func(b): return b.partida.get("estado", -1) == Protocol.MATCH_ESPERA or b.partida.get("estado", -1) == Protocol.MATCH_FIM), "clientes acompanharam o estado da partida")
	print("  tempo real: %.0f s (simulação 4x)" % segundos)
	server.stop()
	_fim()


## Contra um servidor dedicado (outro processo): só o que os clientes veem.
func _externo(n: int, porta: int) -> void:
	var bots: Array = []
	var Bot := load("res://tests/integration/cliente_simulado.gd")
	for i in n:
		var b = Bot.new()
		b.nome = "Ext%d" % (i + 1)
		root.add_child(b)
		b.conectar(porta)
		bots.append(b)
	var inicio := Time.get_ticks_msec()
	var viu_jogo := false
	var viu_tormenta := false
	while Time.get_ticks_msec() - inicio < 300000:
		await physics_frame
		viu_jogo = viu_jogo or bots.any(func(b): return b.partida.get("estado", -1) == Protocol.MATCH_JOGO)
		viu_tormenta = viu_tormenta or bots.any(func(b): return not b.tormenta.is_empty())
		if bots.all(func(b): return not b.resultado.is_empty()) and bots.any(func(b): return b.partida.get("estado", -1) == Protocol.MATCH_FIM):
			break
	_checar(bots.all(func(b): return b.client.connected), "%d clientes conectados ao servidor dedicado" % n)
	_checar(viu_jogo, "partida começou no servidor dedicado")
	_checar(viu_tormenta, "clientes receberam a Tormenta")
	var com_resultado := bots.filter(func(b): return not b.resultado.is_empty())
	_checar(com_resultado.size() == n, "todos receberam resultado (%d/%d)" % [com_resultado.size(), n])
	var col := com_resultado.map(func(b): return b.resultado["colocacao"])
	col.sort()
	_checar(col == range(1, n + 1), "colocações 1..%d (%s)" % [n, str(col)])
	print("  tempo real: %.0f s" % ((Time.get_ticks_msec() - inicio) / 1000.0))
	_fim()


func _fim() -> void:
	print("PARTIDA_BR %s" % ("OK" if falhas == 0 else "FALHA (%d)" % falhas))
	quit(0 if falhas == 0 else 1)
