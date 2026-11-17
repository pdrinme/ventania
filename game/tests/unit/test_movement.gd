extends TestCase
## Testes de movimento com física real (chão, teto). Cada teste cria um mundo pequeno.

const DT := 1.0 / 30.0
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
	pawn.position = Vector3(0, 0.05, 0)


func after_each() -> void:
	_raiz.queue_free()


func _cmd(mov: Vector2, botoes := 0) -> Protocol.InputCmd:
	var c := Protocol.InputCmd.new()
	c.move = mov
	c.buttons = botoes
	return c


## Simula n passos (espera o espaço físico atualizar no primeiro).
func _passos(n: int, cmd: Protocol.InputCmd) -> void:
	await physics_frames(1)
	for i in n:
		Movement.step(pawn, cmd, DT)


func _vel_h() -> float:
	return Vector2(pawn.velocity.x, pawn.velocity.z).length()


func test_anda_e_atinge_velocidade() -> void:
	await _passos(30, _cmd(Vector2(0, 1)))
	assert_true(absf(_vel_h() - Movement.WALK_SPEED) < 0.05, "vel %.2f" % _vel_h())
	assert_true(pawn.global_position.z < -3.5, "andou para a frente (-Z): %s" % pawn.global_position)
	assert_true(pawn.grounded)


func test_corre_so_para_frente() -> void:
	await _passos(30, _cmd(Vector2(0, 1), Protocol.BTN_SPRINT))
	assert_true(absf(_vel_h() - Movement.SPRINT_SPEED) < 0.05)
	await _passos(30, _cmd(Vector2(1, 0), Protocol.BTN_SPRINT))
	assert_true(absf(_vel_h() - Movement.WALK_SPEED) < 0.05, "de lado não corre")


func test_agachado_mais_lento_e_baixo() -> void:
	await _passos(30, _cmd(Vector2(0, 1), Protocol.BTN_CROUCH | Protocol.BTN_SPRINT))
	assert_true(pawn.crouched)
	assert_true(absf(_vel_h() - Movement.CROUCH_SPEED) < 0.05)
	assert_false(pawn.sprinting, "agachado não corre")


func test_altura_do_pulo() -> void:
	await _passos(5, _cmd(Vector2.ZERO))
	var y0 := pawn.global_position.y
	var maximo := y0
	Movement.step(pawn, _cmd(Vector2.ZERO, Protocol.BTN_JUMP), DT)
	for i in 40:
		Movement.step(pawn, _cmd(Vector2.ZERO), DT)
		maximo = maxf(maximo, pawn.global_position.y)
	var altura := maximo - y0
	assert_true(altura > 1.2 and altura < 1.55, "altura %.2f m" % altura)
	assert_true(pawn.grounded, "voltou ao chão")


func test_nao_levanta_sob_teto() -> void:
	var teto := StaticBody3D.new()
	var f := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(4, 0.2, 4)
	f.shape = b
	teto.add_child(f)
	_raiz.add_child(teto)
	teto.global_position = Vector3(0, 1.5, 0)
	await _passos(3, _cmd(Vector2.ZERO, Protocol.BTN_CROUCH))
	assert_true(pawn.crouched)
	await _passos(5, _cmd(Vector2.ZERO))
	assert_true(pawn.crouched, "continua agachado embaixo do teto")
	pawn.global_position = Vector3(10, 0.05, 0)
	await _passos(3, _cmd(Vector2.ZERO))
	assert_false(pawn.crouched, "levanta fora do teto")


func test_simulacao_deterministica() -> void:
	# mesma sequência de entradas a partir do mesmo estado -> mesmo resultado (base da predição)
	var cmds := []
	for i in 40:
		cmds.append(_cmd(Vector2(sin(i * 0.3), 1.0).limit_length(1.0), Protocol.BTN_JUMP if i == 10 else 0))
	await physics_frames(1)
	for c in cmds:
		Movement.step(pawn, c, DT)
	var p1 := pawn.global_position
	pawn.global_position = Vector3(0, 0.05, 0)
	pawn.velocity = Vector3.ZERO
	pawn.grounded = false
	await physics_frames(1)
	for c in cmds:
		Movement.step(pawn, c, DT)
	assert_true(p1.distance_to(pawn.global_position) < 0.001, "%s vs %s" % [p1, pawn.global_position])


func test_mergulho_cai_mais_rapido_so_olhando_para_baixo_e_indo_em_frente() -> void:
	var cmd := Protocol.InputCmd.new()
	cmd.move = Vector2(0, 1)
	cmd.pitch = deg_to_rad(-70)
	assert_true(Movement.diving(Pawn.QUEDA_LIVRE, cmd))
	assert_false(Movement.diving(Pawn.PLANADOR, cmd), "no planador não mergulha")
	cmd.pitch = deg_to_rad(-20)
	assert_false(Movement.diving(Pawn.QUEDA_LIVRE, cmd), "olhando para a frente: queda normal")
	cmd.pitch = deg_to_rad(-70)
	cmd.move = Vector2.ZERO
	assert_false(Movement.diving(Pawn.QUEDA_LIVRE, cmd), "sem ir para a frente: queda normal")


func test_poses_de_entrada_vem_do_estado_replicado() -> void:
	assert_eq(PawnVisual.fall_pose(Pawn.NO_ONIBUS, Vector3.ZERO), "onibus")
	assert_eq(PawnVisual.fall_pose(Pawn.QUEDA_LIVRE, Vector3(0, -20, 0)), "queda_livre")
	assert_eq(PawnVisual.fall_pose(Pawn.QUEDA_LIVRE, Vector3(0, -36, 0)), "mergulho")
	assert_eq(PawnVisual.fall_pose(Pawn.PLANADOR, Vector3(0, -6, 0)), "planador")
	assert_eq(PawnVisual.fall_pose(0, Vector3.ZERO), "chao")
	# corpo: deitado na queda livre, de cabeça para baixo no mergulho, quase em pé no planador
	var livre := PawnVisual.air_tilt("queda_livre", Vector3.ZERO, 0.0)
	var merg := PawnVisual.air_tilt("mergulho", Vector3.ZERO, 1.0)
	var plan := PawnVisual.air_tilt("planador", Vector3.ZERO, 0.0)
	assert_true(rad_to_deg(livre.x) > 60 and rad_to_deg(livre.x) < 90, "queda livre deitada (%.0f°)" % rad_to_deg(livre.x))
	assert_true(rad_to_deg(merg.x) > 140, "mergulho de cabeça para baixo (%.0f°)" % rad_to_deg(merg.x))
	assert_true(rad_to_deg(plan.x) < 20, "planador quase em pé")
	# curva para a direita inclina para um lado; para a esquerda, para o outro
	var dir := PawnVisual.air_tilt("queda_livre", Vector3(8, 0, 0), 0.0)
	var esq := PawnVisual.air_tilt("queda_livre", Vector3(-8, 0, 0), 0.0)
	assert_true(dir.y < -0.2 and esq.y > 0.2, "inclina nas curvas (%.2f / %.2f)" % [dir.y, esq.y])
