extends SceneTree
## Escadas dos edifícios no mapa real (com as peças de construção do mapa): um
## personagem sobe e desce CADA escada pelo caminho em U (entrada → lance 1 →
## patamar → lance 2 → andar de cima), andando e correndo, com a mesma física do
## jogo. Confere:
##  - chega ao andar de cima (y ≈ piso + 4) e volta ao de baixo;
##  - sem trancos: num passo (30 Hz) a altura nunca muda mais de 6 cm além do que a
##    inclinação da escada explica (um degrau de 20 cm "subido no tranco" falharia), e o
##    personagem não fica preso (avança sempre);
##  - velocidade de subida perto da velocidade normal;
##  - não atravessa paredes: termina dentro do edifício.
## Uso: godot --headless --fixed-fps 30 --path game -s res://tests/integration/test_escadas.gd

const ROTA := [Vector3(2.8, 0.0, 1.0), Vector3(1.5, 0.0, 1.0), Vector3(-1.25, 2.0, 1.0), Vector3(-1.25, 2.0, -1.0),
		Vector3(-0.3, 2.0, -1.0), Vector3(2.0, 4.0, -1.0), Vector3(3.0, 4.0, -1.0)]
var falhas := 0


func _checar(ok: bool, msg: String) -> void:
	print(("  ok  " if ok else "  FALHOU  ") + msg)
	if not ok:
		falhas += 1


func _init() -> void:
	await process_frame
	var mundo := IlhaVentania.new()
	mundo.com_ambiente = false
	root.add_child(mundo)
	var server := GameServer.new(mundo, 5, "treino", {})
	root.add_child(server)
	for i in 3:
		await physics_frame
	var escadas := mundo.stairs()
	_checar(escadas.size() >= 6, "o mapa tem escadas nos edifícios de vários andares (%d)" % escadas.size())
	var dt := 1.0 / Protocol.TICK_RATE
	var p := Pawn.new()
	mundo.add_child(p)
	var pior_salto := 0.0
	var ok_total := 0
	for e: Dictionary in escadas:
		var base: Vector3 = e["pos"]
		var giro := Basis(Vector3.UP, deg_to_rad(float(e["rot"])))
		var pontos: Array[Vector3] = []
		for r in ROTA:
			pontos.append(base + giro * Vector3(r.x, r.y + 0.1, r.z))
		for correr in [false, true]:
			# sobe
			var sub := await _percorrer(p, pontos, correr, dt)
			# desce (caminho inverso)
			var inv := pontos.duplicate()
			inv.reverse()
			var des := await _percorrer(p, inv, correr, dt)
			pior_salto = maxf(pior_salto, maxf(sub["salto"], des["salto"]))
			var ok: bool = sub["chegou"] and des["chegou"] and sub["salto"] <= 0.06 and des["salto"] <= 0.06
			if ok:
				ok_total += 1
			print("    %s %s: subida %s em %.1f s (%.2f m/s ao longo do caminho), descida %s em %.1f s, maior tranco %.3f m" % [
					str(base.snapped(Vector3.ONE)), "correndo" if correr else "andando", "ok" if sub["chegou"] else "NÃO", sub["t"],
					sub["vel"], "ok" if des["chegou"] else "NÃO", des["t"], maxf(sub["salto"], des["salto"])])
			_checar(ok, "escada em %s (%s): sobe e desce sem prender nem dar tranco" % [str(base.snapped(Vector3.ONE)), "correndo" if correr else "andando"])
	print("  escadas percorridas: %d de %d · maior tranco (subida além da inclinação) num passo: %.3f m" % [ok_total, escadas.size() * 2, pior_salto])
	print("ESCADAS %s" % ("OK" if falhas == 0 else "FALHOU (%d)" % falhas))
	quit(falhas)


## Anda de ponto em ponto (yaw para o próximo ponto). Retorna chegou, tempo,
## velocidade média e o maior salto vertical num passo.
func _percorrer(p: Pawn, pontos: Array, correr: bool, dt: float) -> Dictionary:
	p.global_position = pontos[0]
	p.velocity = Vector3.ZERO
	p.grounded = true
	var cmd := Protocol.InputCmd.new()
	for i in 5:
		cmd.move = Vector2.ZERO
		Movement.step(p, cmd, dt)
		await physics_frame
	var passos := 0
	var salto := 0.0
	var andado := 0.0
	var parado := 0
	for k in range(1, pontos.size()):
		var alvo: Vector3 = pontos[k]
		while Vector2(p.global_position.x - alvo.x, p.global_position.z - alvo.z).length() > 0.35:
			var d := alvo - p.global_position
			cmd.yaw = atan2(-d.x, -d.z)
			cmd.move = Vector2(0, 1)
			cmd.buttons = Protocol.BTN_SPRINT if correr else 0
			var antes := p.global_position
			Movement.step(p, cmd, dt)
			await physics_frame
			passos += 1
			# "tranco": quanto a altura mudou ALÉM do que a inclinação da escada (até 42°) explica
			var horiz := Vector2(p.global_position.x - antes.x, p.global_position.z - antes.z).length()
			salto = maxf(salto, absf(p.global_position.y - antes.y) - horiz * 0.9)
			andado += antes.distance_to(p.global_position)
			parado = parado + 1 if antes.distance_to(p.global_position) < 0.02 else 0
			if parado > 30 or passos > 900:
				print("      parou em %s (local %s), indo para o ponto %d" % [str(p.global_position.snapped(Vector3.ONE * 0.01)), str((p.global_position - pontos[0]).snapped(Vector3.ONE * 0.01)), k])
				return {"chegou": false, "t": passos * dt, "vel": 0.0, "salto": salto}
	var chegou: bool = absf(p.global_position.y - (pontos[-1] as Vector3).y) < 0.3
	return {"chegou": chegou, "t": passos * dt, "vel": andado / maxf(dt, passos * dt), "salto": salto}
