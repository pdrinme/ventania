extends SceneTree
## Parado numa encosta da ilha, girando a câmera (yaw) de um lado para o outro:
## o personagem precisa continuar "no chão" (sem piscar para "no ar", o que faz
## o visual misturar a pose de queda e as pernas "voarem"). Mede também o
## visual: o peso da pose de queda nunca passa de 5%.
## Uso: godot --headless --fixed-fps 30 --path game -s res://tests/integration/test_chao_encosta.gd

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
	var dt := 1.0 / Protocol.TICK_RATE
	# encostas de várias inclinações (12° a 32°) pelo mapa
	var pontos := []
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var tent := 0
	while pontos.size() < 12 and tent < 20000:
		tent += 1
		var q := Vector2(rng.randf_range(-240, 240), rng.randf_range(-240, 240))
		var h := mundo.ground_height(q.x, q.y)
		if h < 2.0 or mundo.inland(q.x, q.y) < 20.0:
			continue
		var gx := mundo.ground_height(q.x + 1, q.y) - mundo.ground_height(q.x - 1, q.y)
		var gz := mundo.ground_height(q.x, q.y + 1) - mundo.ground_height(q.x, q.y - 1)
		var ang := rad_to_deg(atan(Vector2(gx, gz).length() / 2.0))
		if ang > 12.0 and ang < 32.0:
			pontos.append([Vector3(q.x, h + 0.2, q.y), ang])
	var p := Pawn.new()
	mundo.add_child(p)
	var v := PawnVisual.new()
	root.add_child(v)
	await process_frame
	var cmd := Protocol.InputCmd.new()
	var total_ar := 0
	var pior_ar := 0.0
	var ticks := 0
	for pt in pontos:
		p.global_position = pt[0]
		p.velocity = Vector3.ZERO
		for i in 20:                      # assenta
			cmd.move = Vector2.ZERO
			Movement.step(p, cmd, dt)
			await physics_frame
		var no_ar := 0
		for i in 150:
			cmd.move = Vector2.ZERO
			cmd.yaw = sin(i * 0.25) * 2.2  # olha de um lado para o outro (rápido)
			Movement.step(p, cmd, dt)
			await physics_frame
			var flags := Protocol.F_ON_FLOOR if p.grounded else 0
			v.update_state(p.velocity, flags, cmd.yaw)
			await process_frame
			ticks += 1
			if not p.grounded:
				no_ar += 1
			pior_ar = maxf(pior_ar, v.get("_ar"))
		total_ar += no_ar
		if no_ar > 0:
			print("    encosta %.0f° em %s: %d de 150 ticks 'no ar'" % [pt[1], str((pt[0] as Vector3).snapped(Vector3.ONE)), no_ar])
	# descendo a encosta (andando e correndo, na direção da descida)
	var no_ar_desce := 0
	var ticks_desce := 0
	var pior_desce := 0.0
	for pt in pontos:
		var c: Vector3 = pt[0]
		var gx := mundo.ground_height(c.x + 1, c.z) - mundo.ground_height(c.x - 1, c.z)
		var gz := mundo.ground_height(c.x, c.z + 1) - mundo.ground_height(c.x, c.z - 1)
		var desce := -Vector2(gx, gz).normalized()                       # direção em que o chão desce
		for correr in [false, true]:
			p.global_position = c - Vector3(desce.x, 0, desce.y) * 6.0 + Vector3(0, 0.6, 0)
			p.global_position.y = mundo.ground_height(p.global_position.x, p.global_position.z) + 0.2
			p.velocity = Vector3.ZERO
			for i in 10:
				cmd.move = Vector2.ZERO
				Movement.step(p, cmd, dt)
				await physics_frame
			var n := 0
			var firme := 0
			for i in 60:
				cmd.yaw = atan2(-desce.x, -desce.y)
				cmd.move = Vector2(0, 1)
				cmd.buttons = Protocol.BTN_SPRINT if correr else 0
				Movement.step(p, cmd, dt)
				await physics_frame
				v.update_state(p.velocity, Protocol.F_ON_FLOOR if p.grounded else 0, cmd.yaw)
				await process_frame
				ticks_desce += 1
				# pose de queda perto do chão (< 0,3 m) é o bug "pernas voando";
				# cair de um barranco de verdade (mais alto) mostra a queda, e está certo
				# com contato firme (0,2 s seguidos no chão) a pose de queda não pode aparecer;
				# o pouso depois de cair de um barranco ainda desfaz a pose, e está certo
				firme = firme + 1 if p.grounded else 0
				if firme >= 6:
					pior_desce = maxf(pior_desce, v.get("_ar"))
				if not p.grounded:
					n += 1
			no_ar_desce += n
			if n > 3:
				print("    descendo %.0f° %s: %d de 60 ticks 'no ar'" % [pt[1], "correndo" if correr else "andando", n])
	cmd.buttons = 0
	_checar(no_ar_desce * 20 < ticks_desce, "descendo encostas, no chão em quase todo o caminho (%d de %d ticks no ar)" % [no_ar_desce, ticks_desce])
	_checar(pior_desce < 0.3, "descendo, com o pé firme no chão a pose de queda não aparece (peso máximo %.2f)" % pior_desce)
	_checar(pontos.size() >= 8, "encostas testadas: %d" % pontos.size())
	_checar(total_ar == 0, "parado girando na encosta, sempre no chão (%d de %d ticks no ar)" % [total_ar, ticks])
	_checar(pior_ar < 0.05, "a pose de queda não aparece (peso máximo %.2f)" % pior_ar)
	print("CHAO_ENCOSTA %s" % ("OK" if falhas == 0 else "FALHOU (%d)" % falhas))
	quit(falhas)
