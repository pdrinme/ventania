extends SceneTree
## Física da entrada na partida (sem interface): queda livre chega à terminal
## normal; mergulho (olhando para baixo e indo para a frente) cai mais rápido e
## volta à terminal normal sem tranco; o planador abre perto do chão e pousa.
## Uso: godot --headless --path game -s res://tests/integration/test_queda.gd

var falhas := 0


func _checar(ok: bool, msg: String) -> void:
	print(("  ok  " if ok else "  FALHOU  ") + msg)
	if not ok:
		falhas += 1


func _init() -> void:
	await process_frame
	var chao := StaticBody3D.new()
	var forma := CollisionShape3D.new()
	var caixa := BoxShape3D.new()
	caixa.size = Vector3(2000, 2, 2000)
	forma.shape = caixa
	chao.add_child(forma)
	chao.position.y = -1.0
	chao.collision_layer = Pawn.LAYER_WORLD
	root.add_child(chao)
	var pawn := Pawn.new()
	root.add_child(pawn)
	pawn.global_position = Vector3(0, 400, 0)
	pawn.queda = Pawn.QUEDA_LIVRE
	await physics_frame
	var dt := 1.0 / Protocol.TICK_RATE
	var cmd := Protocol.InputCmd.new()
	for i in 90:
		Movement.step(pawn, cmd, dt)
		await physics_frame
	_checar(absf(pawn.velocity.y + Movement.QUEDA_TERMINAL) < 0.5, "queda livre chega à terminal normal (%.1f m/s)" % -pawn.velocity.y)
	cmd.pitch = deg_to_rad(-70)
	cmd.move = Vector2(0, 1)
	for i in 60:
		Movement.step(pawn, cmd, dt)
		await physics_frame
	_checar(-pawn.velocity.y > Movement.QUEDA_TERMINAL + 8.0, "mergulho cai mais rápido (%.1f m/s)" % -pawn.velocity.y)
	_checar(PawnVisual.fall_pose(pawn.queda, pawn.velocity) == "mergulho", "o visual reconhece o mergulho pela velocidade")
	var antes := pawn.velocity.y
	cmd.pitch = 0.0
	Movement.step(pawn, cmd, dt)
	_checar(absf(pawn.velocity.y - antes) < 2.0, "sair do mergulho não dá tranco (%.1f -> %.1f)" % [-antes, -pawn.velocity.y])
	for i in 600:
		Movement.step(pawn, cmd, dt)
		await physics_frame
		if pawn.queda != Pawn.QUEDA_LIVRE:
			break
	_checar(pawn.queda == Pawn.PLANADOR and pawn.global_position.y < Movement.PLANADOR_ALTURA + 2.0,
			"planador abre perto do chão (%.0f m)" % pawn.global_position.y)
	for i in 900:
		Movement.step(pawn, cmd, dt)
		await physics_frame
		if pawn.queda == 0:
			break
	_checar(pawn.queda == 0 and pawn.is_on_floor(), "pousou com o planador")
	print("QUEDA %s" % ("OK" if falhas == 0 else "FALHA (%d)" % falhas))
	quit(0 if falhas == 0 else 1)
