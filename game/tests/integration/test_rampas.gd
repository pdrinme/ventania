extends SceneTree
## Movimento em rampas (física compartilhada servidor/cliente): mede a velocidade
## subindo e descendo rampas de 10°, 20°, 30° e 45° (a rampa de construção), em
## comparação com o chão plano, andando e correndo. Confere que:
##  - no plano, nada muda (4,5 m/s andando, 6,5 m/s correndo);
##  - na subida, a velocidade AO LONGO da rampa fica perto da do plano (≥ 90%);
##  - ninguém escorrega para trás parado numa rampa, e chegar ao topo não dá salto;
##  - na descida o personagem não "voa" (continua no chão).
## Uso: godot --headless --fixed-fps 30 --path game -s res://tests/integration/test_rampas.gd

var falhas := 0


func _checar(ok: bool, msg: String) -> void:
	print(("  ok  " if ok else "  FALHOU  ") + msg)
	if not ok:
		falhas += 1


func _caixa(pos: Vector3, tam: Vector3, rot_x := 0.0) -> void:
	var corpo := StaticBody3D.new()
	corpo.collision_layer = Pawn.LAYER_WORLD
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = tam
	cs.shape = b
	corpo.add_child(cs)
	corpo.transform = Transform3D(Basis(Vector3.RIGHT, rot_x), pos)
	root.add_child(corpo)


## Uma pista: chão plano, rampa subindo para -Z com `graus`, platô no topo.
func _pista(x: float, graus: float, comprimento: float) -> Dictionary:
	var a := deg_to_rad(graus)
	var sobe := comprimento * sin(a)
	var avanco := comprimento * cos(a)
	_caixa(Vector3(x, -0.5, 10), Vector3(3, 1, 20))                         # chão: z 0..20
	# rampa: o topo começa em z = 0 (y = 0) e termina em z = -avanco (y = sobe)
	_caixa(Vector3(x, sobe / 2.0 - 0.5 * cos(a), -avanco / 2.0 - 0.5 * sin(a)), Vector3(3, 1, comprimento), a)
	_caixa(Vector3(x, sobe - 0.5, -avanco - 10), Vector3(3, 1, 20))          # platô no topo
	return {"sobe": sobe, "avanco": avanco}


func _pawn(pos: Vector3) -> Pawn:
	var p := Pawn.new()
	root.add_child(p)
	p.global_position = pos
	return p


func _init() -> void:
	await process_frame
	var dt := 1.0 / Protocol.TICK_RATE
	print("  graus | modo    | plano m/s | subida: horiz / ao longo (% do plano) | descida horiz | no chão descendo")
	var x := 0.0
	for graus in [10.0, 20.0, 30.0, 45.0]:
		var pista := _pista(x, graus, 12.0)
		await physics_frame
		for correr in [false, true]:
			var p := _pawn(Vector3(x, 0.05, 12))
			var cmd := Protocol.InputCmd.new()
			cmd.move = Vector2(0, 1)
			cmd.yaw = 0.0                      # olhando para -Z
			if correr:
				cmd.buttons |= Protocol.BTN_SPRINT
			for i in 10:
				Movement.step(p, cmd, dt)
				await physics_frame
			# plano: mede 10 passos
			var z0 := p.global_position.z
			for i in 10:
				Movement.step(p, cmd, dt)
				await physics_frame
			var v_plano := (z0 - p.global_position.z) / (10 * dt)
			# subida: mede do pé ao fim da rampa
			while p.global_position.z > -0.3:
				Movement.step(p, cmd, dt)
				await physics_frame
			var ini := p.global_position
			var passos := 0
			var no_chao := 0
			while p.global_position.z > -pista["avanco"] + 0.5 and passos < 300:
				Movement.step(p, cmd, dt)
				await physics_frame
				passos += 1
				no_chao += 1 if p.grounded else 0
			var fim := p.global_position
			var horiz := (ini.z - fim.z) / (passos * dt)
			var longo := ini.distance_to(fim) / (passos * dt)
			# topo: não pode "saltar"
			var y_max: float = fim.y
			for i in 20:
				Movement.step(p, cmd, dt)
				await physics_frame
				y_max = maxf(y_max, p.global_position.y)
			var salto: float = y_max - float(pista["sobe"])
			# descida: volta olhando para +Z
			cmd.yaw = PI
			while p.global_position.z < -pista["avanco"] - 0.3:
				Movement.step(p, cmd, dt)
				await physics_frame
			var ini_d := p.global_position
			var passos_d := 0
			var chao_d := 0
			while p.global_position.z < -0.5 and passos_d < 300:
				Movement.step(p, cmd, dt)
				await physics_frame
				passos_d += 1
				chao_d += 1 if p.grounded else 0
			var horiz_d := (p.global_position.z - ini_d.z) / (passos_d * dt)
			# parado no meio da rampa: não escorrega
			cmd.move = Vector2.ZERO
			cmd.buttons = 0
			cmd.yaw = 0.0
			p.global_position = Vector3(x, pista["sobe"] * 0.5 + 0.3, -pista["avanco"] * 0.5)
			p.velocity = Vector3.ZERO
			for i in 15:
				Movement.step(p, cmd, dt)
				await physics_frame
			var antes := p.global_position
			for i in 30:
				Movement.step(p, cmd, dt)
				await physics_frame
			var escorregou := antes.distance_to(p.global_position)
			var modo := "corre" if correr else "anda"
			print("  %4.0f° | %-7s | %9.2f | %5.2f / %5.2f (%3.0f%%)                | %5.2f        | %3.0f%%  (topo +%.2f m, parado escorregou %.2f m)" % [
					graus, modo, v_plano, horiz, longo, 100.0 * longo / v_plano, horiz_d, 100.0 * chao_d / maxf(1, passos_d), maxf(0.0, salto), escorregou])
			_checar(absf(v_plano - (Movement.SPRINT_SPEED if correr else Movement.WALK_SPEED)) < 0.05, "%.0f° %s: plano inalterado" % [graus, modo])
			_checar(longo >= 0.9 * v_plano, "%.0f° %s: subida ao longo da rampa ≥ 90%% do plano" % [graus, modo])
			_checar(salto < 0.25, "%.0f° %s: sem salto no topo" % [graus, modo])
			_checar(escorregou < 0.05, "%.0f° %s: parado não escorrega" % [graus, modo])
			_checar(chao_d >= passos_d * 0.8, "%.0f° %s: desce no chão (sem voar)" % [graus, modo])
			p.queue_free()
		x += 6.0
	print("RAMPAS %s" % ("OK" if falhas == 0 else "FALHOU (%d)" % falhas))
	quit(falhas)
