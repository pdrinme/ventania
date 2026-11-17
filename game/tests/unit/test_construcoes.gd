extends TestCase
## Construções e colisões: forma visual x colisão, e o personagem andando de verdade
## (Movement + física) sobre pisos, rampas, paredes, quinas, telhado e props.

const DT := 1.0 / 30.0
const TOL := 0.03
var _raiz: Node3D
var pawn: Pawn


func before_each() -> void:
	_raiz = Node3D.new()
	tree.root.add_child(_raiz)
	var chao := StaticBody3D.new()
	var f := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(200, 2, 200)
	f.shape = b
	f.position.y = -1
	chao.add_child(f)
	_raiz.add_child(chao)
	pawn = Pawn.new()
	_raiz.add_child(pawn)


func after_each() -> void:
	_raiz.queue_free()


func _peca(nome: String, pos: Vector3, rot_y := 0.0) -> Node3D:
	var n := (load("res://assets/construcoes/%s.glb" % nome) as PackedScene).instantiate() as Node3D
	n.position = pos
	n.rotation_degrees.y = rot_y
	_raiz.add_child(n)
	return n


static func aabb_visual(n: Node3D) -> AABB:
	var r := AABB()
	var primeiro := true
	for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
		var a := mi.global_transform * mi.get_aabb()
		r = a if primeiro else r.merge(a)
		primeiro = false
	return r


static func aabb_colisao(n: Node3D) -> AABB:
	var r := AABB()
	var primeiro := true
	for cs: CollisionShape3D in n.find_children("*", "CollisionShape3D", true, false):
		var pts: PackedVector3Array = []
		if cs.shape is ConvexPolygonShape3D:
			pts = (cs.shape as ConvexPolygonShape3D).points
		elif cs.shape is BoxShape3D:
			var h: Vector3 = (cs.shape as BoxShape3D).size / 2
			for sx in [-1, 1]:
				for sy in [-1, 1]:
					for sz in [-1, 1]:
						pts.append(Vector3(sx * h.x, sy * h.y, sz * h.z))
		for p in pts:
			var g := cs.global_transform * p
			r = AABB(g, Vector3.ZERO) if primeiro else r.expand(g)
			primeiro = false
	return r


func _cmd(mov: Vector2, botoes := 0, yaw := 0.0) -> Protocol.InputCmd:
	var c := Protocol.InputCmd.new()
	c.move = mov
	c.buttons = botoes
	c.yaw = yaw
	return c


func _andar(passos: int, cmd: Protocol.InputCmd) -> void:
	await physics_frames(1)
	for i in passos:
		Movement.step(pawn, cmd, DT)


func _colocar(pos: Vector3) -> void:
	pawn.global_position = pos
	pawn.velocity = Vector3.ZERO
	pawn.grounded = false
	pawn.set_crouched(false)


# ---------- forma ----------

func test_colisao_igual_ao_visual() -> void:
	for arq in DirAccess.get_files_at("res://assets/construcoes"):
		if not arq.ends_with(".glb"):
			continue
		var n := _peca(arq.get_basename(), Vector3.ZERO)
		var v := aabb_visual(n)
		var c := aabb_colisao(n)
		assert_true(c.size.length() > 0.1, "%s tem colisão" % arq)
		for eixo in 3:
			# a colisão cobre o visual (o beiral do telhado pode passar 8 cm)
			var folga := 0.09 if arq.begins_with("teto") and eixo != 1 else TOL
			assert_true(c.position[eixo] <= v.position[eixo] + folga and c.end[eixo] >= v.end[eixo] - folga,
					"%s eixo %d: visual %.2f..%.2f, colisão %.2f..%.2f" % [arq, eixo, v.position[eixo], v.end[eixo], c.position[eixo], c.end[eixo]])
			assert_true(c.position[eixo] >= v.position[eixo] - folga and c.end[eixo] <= v.end[eixo] + folga,
					"%s eixo %d: colisão maior que o visual" % [arq, eixo])
		n.free()


func test_padroes_da_grade() -> void:
	var piso := _peca("piso_madeira", Vector3.ZERO)
	assert_true(absf(aabb_colisao(piso).end.y - 0.10) < 0.01, "topo do piso a 10 cm")
	assert_true(absf(aabb_colisao(piso).size.x - 4.0) < 0.01, "piso ocupa a célula inteira")
	var rampa := _peca("rampa_pedra", Vector3(10, 0, 0))
	var r := aabb_colisao(rampa)
	assert_true(absf(r.end.y - 4.10) < 0.12, "rampa chega ao topo do andar de cima (%.2f)" % r.end.y)
	var parede := _peca("parede_metal", Vector3(20, 0, 0))
	var p := aabb_colisao(parede)
	assert_true(absf(p.size.z - 0.24) < 0.01 and absf(p.size.y - 4.0) < 0.01, "parede 4 m x 24 cm")


# ---------- física ----------

func test_sobe_do_chao_para_o_piso() -> void:
	_peca("piso_madeira", Vector3(0, 0, -4))
	_colocar(Vector3(0, 0.05, 0.5))
	await _andar(45, _cmd(Vector2(0, 1)))
	assert_true(pawn.global_position.z < -3.0, "entrou no piso (z=%.2f)" % pawn.global_position.z)
	assert_true(absf(pawn.global_position.y - 0.10) < 0.05, "em cima do piso (y=%.2f)" % pawn.global_position.y)


func test_sobe_rampa_ate_o_andar_de_cima() -> void:
	for mat in ["madeira", "pedra", "metal"]:
		_peca("rampa_" + mat, Vector3(0, 0, -2))
		_peca("piso_" + mat, Vector3(0, 4, -6))
		_colocar(Vector3(0, 0.05, 2.0))
		# corre até passar do meio do piso de cima (z -4..-8) e para (antes de cair da borda)
		await physics_frames(1)
		var sobe := _cmd(Vector2(0, 1), Protocol.BTN_SPRINT)
		for i in 120:
			Movement.step(pawn, sobe, DT)
			if pawn.global_position.z < -5.5:
				break
		for i in 10:
			Movement.step(pawn, _cmd(Vector2.ZERO), DT)
		assert_true(pawn.global_position.z < -5.0, "%s: chegou ao piso de cima (z=%.2f)" % [mat, pawn.global_position.z])
		assert_true(absf(pawn.global_position.y - 4.10) < 0.08, "%s: altura do andar (y=%.2f)" % [mat, pawn.global_position.y])
		# desce de volta sem "quicar" no ar
		var no_chao := 0
		var cmd := _cmd(Vector2(0, 1), 0, PI)
		await physics_frames(1)
		for i in 60:
			Movement.step(pawn, cmd, DT)
			no_chao += 1 if pawn.grounded else 0
		assert_true(pawn.global_position.y < 0.3, "%s: desceu a rampa (y=%.2f)" % [mat, pawn.global_position.y])
		assert_true(no_chao >= 54, "%s: desceu colado na rampa (%d/60 no chão)" % [mat, no_chao])
		for c in _raiz.get_children():
			if c is Node3D and c != pawn and not (c is StaticBody3D):
				c.free()


func test_nao_atravessa_parede() -> void:
	for mat in ["madeira", "pedra", "metal"]:
		var parede := _peca("parede_" + mat, Vector3(0, 0, -2))
		_colocar(Vector3(0, 0.05, 0))
		var menor_z := 99.0
		await physics_frames(1)
		for i in 90:
			Movement.step(pawn, _cmd(Vector2(0, 1), Protocol.BTN_SPRINT | (Protocol.BTN_JUMP if i % 20 == 0 else 0)), DT)
			menor_z = minf(menor_z, pawn.global_position.z)
		var limite := -2.0 + 0.12 + Pawn.RADIUS - 0.03
		assert_true(menor_z > limite, "%s: parou na face da parede (z mín %.3f, limite %.3f)" % [mat, menor_z, limite])
		parede.free()


func test_quina_de_duas_paredes() -> void:
	_peca("parede_madeira", Vector3(0, 0, -2))
	_peca("parede_madeira", Vector3(2, 0, 0), 90)
	_colocar(Vector3(0, 0.05, 0))
	await _andar(90, _cmd(Vector2(0.7, 0.7), Protocol.BTN_SPRINT))
	assert_true(pawn.global_position.z > -2.0 and pawn.global_position.x < 2.0, "não escapou pela quina (%s)" % pawn.global_position)


func test_telhado_solido_e_andavel() -> void:
	_peca("teto_metal", Vector3(0, 0, 0))
	_colocar(Vector3(0, 4.0, 0))
	await _andar(40, _cmd(Vector2.ZERO))
	assert_true(absf(pawn.global_position.y - 1.6) < 0.1, "pousou no topo do telhado (y=%.2f)" % pawn.global_position.y)
	await _andar(10, _cmd(Vector2(0, 1)))
	assert_true(pawn.global_position.y > 0.5 and pawn.global_position.y < 1.65, "andando sobre a face do telhado (y=%.2f)" % pawn.global_position.y)


func test_props_bloqueiam() -> void:
	for nome in ["pedra_01", "arvore_redonda_01", "pinheiro_01"]:
		var n := (load("res://assets/cenario/%s.glb" % nome) as PackedScene).instantiate() as Node3D
		n.position = Vector3(0, 0, -3)
		_raiz.add_child(n)
		_colocar(Vector3(0, 0.05, 0))
		await _andar(60, _cmd(Vector2(0, 1)))
		assert_true(pawn.global_position.z > -3.0, "%s bloqueia (z=%.2f)" % [nome, pawn.global_position.z])
		n.free()
