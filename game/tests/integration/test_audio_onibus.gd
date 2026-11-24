extends SceneTree
## Som da entrada (AudioEntrada), simulando um voo do Ônibus dos Ventos tick a tick:
##  - motor e vento do ônibus entram em fade (sem começar no volume cheio) e saem
##    em fade quando o ônibus vai embora; o motor é 3D, preso ao ônibus;
##  - a cabine toca só enquanto o jogador está a bordo e some depois do salto;
##  - buzina de aviso, portas e última chamada tocam UMA vez cada, na hora certa;
##  - quem "entra no meio" (depois do horário de um evento) não ouve o evento velho;
##  - o vento de altitude acompanha a queda livre e para no chão;
##  - aproximação sobe o tom do motor (Doppler) e afastamento desce.
## Uso: godot --headless --fixed-fps 30 --path game -s res://tests/integration/test_audio_onibus.gd

var falhas := 0


func _checar(ok: bool, msg: String) -> void:
	print(("  ok  " if ok else "  FALHOU  ") + msg)
	if not ok:
		falhas += 1


func _rota(tick0: int) -> OnibusBatalha:
	return OnibusBatalha.from_dict({"inicio": Vector3(-300, 120, 0), "fim": Vector3(300, 120, 0), "tick0": tick0,
			"duracao": 30 * 30, "abre": tick0 + 30 * 4, "fecha": tick0 + 30 * 20})


func _init() -> void:
	await process_frame
	var a := AudioEntrada.new()
	root.add_child(a)
	var onibus := Node3D.new()
	root.add_child(onibus)
	a.attach_bus(onibus)
	var bus := _rota(1000)
	var dt := 1.0 / 30.0
	var eventos_vistos := {}
	var tocou_cedo := false
	var g0 := -1.0
	var cabine_antes := 0.0
	var cabine_depois := 1.0
	var queda_max := 0.0
	var tick := bus.tick0
	# voo: a bordo até o tick abre + 3 s, depois queda livre, depois chão
	var salto := bus.abre + 90
	var chao := salto + 150
	while tick <= bus.tick0 + bus.duracao + 30:
		var ativo := tick <= bus.tick0 + bus.duracao
		onibus.position = bus.position_at(tick)
		var a_bordo := tick < salto
		var queda := 1 if (tick >= salto and tick < chao) else 0
		a.update(dt, ativo, a_bordo, tick, bus, Vector3(0, 0, 40), queda, 32.0 if queda == 1 else 0.0)
		var st := a.state()
		if g0 < 0.0:
			g0 = st["motor"]
		for e in st["eventos"]:
			if not eventos_vistos.has(e):
				eventos_vistos[e] = tick
		if tick == salto - 1:
			cabine_antes = st["cabine"]
		if tick == salto + 30:
			cabine_depois = st["cabine"]
		queda_max = maxf(queda_max, st["vento_queda"])
		if tick < bus.abre - 3 * 30 and not eventos_vistos.is_empty():
			tocou_cedo = true
		await process_frame
		tick += 1
	_checar(g0 < 0.2, "motor entra em fade (ganho inicial %.2f)" % g0)
	_checar(a.motor.get_parent() == onibus, "motor é 3D, preso ao ônibus")
	_checar(cabine_antes > 0.9 and cabine_depois < 0.05, "cabine a bordo (%.2f) e some depois do salto (%.2f)" % [cabine_antes, cabine_depois])
	_checar(queda_max > 0.6, "vento de altitude na queda livre (%.2f)" % queda_max)
	_checar(eventos_vistos.has("aviso") and eventos_vistos.has("portas") and eventos_vistos.has("ultima") and not tocou_cedo,
			"aviso, portas e última chamada tocaram nos horários %s" % str(eventos_vistos))
	_checar(absi(eventos_vistos.get("portas", -999) - bus.abre) <= 1 and absi(eventos_vistos.get("aviso", -999) - (bus.abre - 90)) <= 1,
			"portas no tick da abertura e aviso 3 s antes")
	# fim: tudo em silêncio depois do fade
	for i in 60:
		a.update(dt, false, false, tick, bus, Vector3.ZERO, 0, 0.0)
		await process_frame
	var fim := a.state()
	_checar(fim["motor"] == 0.0 and fim["cabine"] == 0.0 and fim["vento_queda"] == 0.0 and not a.motor.playing,
			"tudo para depois que o ônibus vai embora %s" % str(fim))
	# mesma partida, update repetido: eventos não repetem (sem duplicar)
	var antes: int = a.state()["eventos"].size()
	for t in range(bus.abre, bus.abre + 10):
		a.update(dt, true, true, t, bus, Vector3.ZERO, 0, 0.0)
	_checar(a.state()["eventos"].size() == antes, "eventos não repetem na mesma partida")
	# quem conecta no meio do voo (depois das portas) não ouve buzina/portas velhas
	var b := AudioEntrada.new()
	root.add_child(b)
	var bus2 := _rota(5000)
	var o2 := Node3D.new()
	root.add_child(o2)
	b.attach_bus(o2)
	for t in range(bus2.abre + 60, bus2.abre + 120):
		o2.position = bus2.position_at(t)
		b.update(dt, true, true, t, bus2, Vector3.ZERO, 0, 0.0)
	_checar(not b.state()["eventos"].has("aviso") and not b.state()["eventos"].has("portas"),
			"quem entra no meio não ouve eventos passados %s" % str(b.state()["eventos"]))
	# Doppler: ônibus vindo na direção do ouvinte -> tom acima de 1; indo embora -> abaixo
	var c := AudioEntrada.new()
	root.add_child(c)
	var o3 := Node3D.new()
	root.add_child(o3)
	c.attach_bus(o3)
	var bus3 := _rota(9000)
	for i in 40:
		o3.position = Vector3(-200 + i * 20.0 / 30.0 * 1.0 * 30.0 / 30.0, 120, 0)
		c.update(dt, true, false, bus3.tick0 + 1, bus3, Vector3(0, 0, 0), 0, 0.0)
		await process_frame
	var p_vindo := c.motor.pitch_scale
	for i in 40:
		o3.position = Vector3(200 + i * 20.0 / 30.0, 120, 0)
		c.update(dt, true, false, bus3.tick0 + 1, bus3, Vector3(0, 0, 0), 0, 0.0)
		await process_frame
	var p_indo := c.motor.pitch_scale
	_checar(p_vindo > 1.02 and p_indo < 0.98, "Doppler: chegando %.3f, indo embora %.3f" % [p_vindo, p_indo])
	print("AUDIO_ONIBUS %s" % ("OK" if falhas == 0 else "FALHOU (%d)" % falhas))
	quit(falhas)
