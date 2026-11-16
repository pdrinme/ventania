extends SceneTree
## Integração com um servidor dedicado em OUTRO processo (como no uso real).
## Uso: godot --headless --path game -s res://tests/integration/test_dedicated_server.gd -- 127.0.0.1 PORTA
## Dois clientes conectam; o 1º anda e corre para a frente; verifica que o servidor
## moveu o personagem, que a velocidade respeita o limite e que o 2º jogador vê o 1º.


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var host := args[0] if args.size() > 0 else "127.0.0.1"
	var porta := int(args[1]) if args.size() > 1 else Protocol.DEFAULT_PORT
	var a := GameClient.new()
	var b := GameClient.new()
	root.add_child.call_deferred(a)
	root.add_child.call_deferred(b)
	await process_frame
	a.connect_to(host, porta, "Ana")
	b.connect_to(host, porta, "Bia")
	# lambdas do GDScript copiam variáveis simples: o estado fica num dicionário (referência)
	var r := {"posicoes": [], "vel_max": 0.0, "b_viu_a": false}
	a.snapshot_received.connect(func(s):
		for e: Protocol.EntityState in s["entities"]:
			if e.id == a.my_id:
				r["posicoes"].append(e.position)
				r["vel_max"] = maxf(r["vel_max"], Vector2(e.velocity.x, e.velocity.z).length()))
	b.snapshot_received.connect(func(s):
		for e: Protocol.EntityState in s["entities"]:
			if e.id == a.my_id and a.my_id != 0:
				r["b_viu_a"] = true)
	var seq_a := 0
	var seq_b := 0
	var frames := 0
	while frames < 240:
		await physics_frame
		frames += 1
		a.poll()
		b.poll()
		if a.connected:
			seq_a += 1
			var c := Protocol.InputCmd.new()
			c.seq = seq_a
			c.move = Vector2(0, 1)
			c.buttons = Protocol.BTN_SPRINT if seq_a > 30 else 0
			a.send_inputs([c])
		if b.connected:
			seq_b += 1
			var c2 := Protocol.InputCmd.new()
			c2.seq = seq_b
			b.send_inputs([c2])
		if seq_a > 90 and r["posicoes"].size() > 20:
			break
	# --- combate: A para, mira em B (posição vista no snapshot) e atira com a pistola inicial
	var combate := {"pos_a": Vector3.ZERO, "pos_b": Vector3.ZERO, "tick": 0, "acertos": 0, "dano_b": 0, "hp_b": 100}
	a.snapshot_received.connect(func(s):
		combate["tick"] = s["tick"]
		for e: Protocol.EntityState in s["entities"]:
			if e.id == a.my_id:
				combate["pos_a"] = e.position
			elif e.id == b.my_id:
				combate["pos_b"] = e.position)
	a.hit_confirmed.connect(func(h):
		if h["target"] == b.my_id:
			combate["acertos"] += 1)
	b.damaged.connect(func(d): combate["dano_b"] += d["damage"])
	b.status_received.connect(func(st): combate["hp_b"] = st["hp"] + st["shield"])
	for i in 300:
		await physics_frame
		a.poll()
		b.poll()
		var parar := i < 30
		seq_a += 1
		var c := Protocol.InputCmd.new()
		c.seq = seq_a
		c.view_tick = combate["tick"]
		if not parar:
			var alvo: Vector3 = combate["pos_b"] + Vector3(0, 1.0, 0)
			var d: Vector3 = alvo - (combate["pos_a"] + Vector3(0, Combat.EYE_STAND, 0))
			c.yaw = atan2(-d.x, -d.z)
			c.pitch = atan2(d.y, Vector2(d.x, d.z).length())
			var mira := Combat.aim_ray(combate["pos_a"], false, c.yaw, c.pitch)
			d = alvo - (mira["origin"] as Vector3)
			c.yaw = atan2(-d.x, -d.z)
			c.pitch = atan2(d.y, Vector2(d.x, d.z).length())
			c.buttons = Protocol.BTN_FIRE if i % 8 < 2 else 0     # semiautomática: aperta e solta
		a.send_inputs([c])
		seq_b += 1
		var c2 := Protocol.InputCmd.new()
		c2.seq = seq_b
		b.send_inputs([c2])
		if combate["acertos"] >= 3 and combate["hp_b"] < 100:
			break
	print("COMBATE acertos=%d dano_b=%d vida+escudo_b=%d" % [combate["acertos"], combate["dano_b"], combate["hp_b"]])

	var falhas := 0
	if combate["acertos"] < 3 or combate["dano_b"] <= 0 or combate["hp_b"] >= 100:
		printerr("FALHA: combate entre jogadores não registrou dano")
		falhas += 1
	if not (a.connected and b.connected):
		printerr("FALHA: clientes não conectaram (a=%s b=%s)" % [a.connected, b.connected])
		falhas += 1
	var posicoes: Array = r["posicoes"]
	var vel_max: float = r["vel_max"]
	var b_viu_a: bool = r["b_viu_a"]
	var andou: float = (posicoes[0] as Vector3).distance_to(posicoes[-1]) if posicoes.size() > 1 else 0.0
	if andou < 8.0:
		printerr("FALHA: servidor moveu só %.1f m" % andou)
		falhas += 1
	if vel_max > Movement.SPRINT_SPEED * 1.05:
		printerr("FALHA: velocidade %.2f acima do limite" % vel_max)
		falhas += 1
	if not b_viu_a:
		printerr("FALHA: jogador B não recebeu o jogador A")
		falhas += 1
	print("DEDICADO %s andou=%.1fm vel_max=%.2f b_viu_a=%s" % ["OK" if falhas == 0 else "FALHA", andou, vel_max, b_viu_a])
	a.close()
	b.close()
	quit(1 if falhas else 0)
