extends TestCase


func _cmd(seq: int, mx: float, my: float, yaw: float, botoes: int) -> Protocol.InputCmd:
	var c := Protocol.InputCmd.new()
	c.seq = seq
	c.move = Vector2(mx, my)
	c.yaw = yaw
	c.pitch = deg_to_rad(-20.0)
	c.buttons = botoes
	return c


func test_entradas_ida_e_volta() -> void:
	var dados := Protocol.pack_inputs([_cmd(7, 0.5, 0.5, 1.0, Protocol.BTN_JUMP), _cmd(8, -1, 0, 6.0, Protocol.BTN_CROUCH | Protocol.BTN_SPRINT)])
	var lista := Protocol.unpack_inputs(dados)
	assert_eq(lista.size(), 2)
	assert_eq(lista[0].seq, 7)
	assert_true(absf(lista[0].move.x - 0.5) < 0.01)
	assert_true(absf(lista[0].yaw - 1.0) < 0.001)
	assert_true(absf(rad_to_deg(lista[0].pitch) + 20.0) < 0.02)
	assert_true(lista[0].has(Protocol.BTN_JUMP))
	assert_true(lista[1].has(Protocol.BTN_CROUCH) and lista[1].has(Protocol.BTN_SPRINT))


func test_entrada_saneada() -> void:
	var c := _cmd(1, 1.0, 1.0, 0.0, 0xFF)   # diagonal > 1 e botões desconhecidos
	var l := Protocol.unpack_inputs(Protocol.pack_inputs([c]))
	assert_true(l[0].move.length() <= 1.0001, "movimento limitado a 1")
	assert_eq(l[0].buttons, Protocol.BTN_JUMP | Protocol.BTN_SPRINT | Protocol.BTN_CROUCH)


func test_pacotes_invalidos() -> void:
	assert_eq(Protocol.unpack_inputs(PackedByteArray([Protocol.C_INPUT, 3, 1, 2])).size(), 0, "tamanho errado")
	assert_eq(Protocol.unpack_inputs(PackedByteArray([Protocol.C_INPUT, 0])).size(), 0)
	assert_eq(Protocol.unpack_snapshot(PackedByteArray([Protocol.S_SNAPSHOT, 1, 2])).size(), 0)
	assert_eq(Protocol.unpack_hello(PackedByteArray([Protocol.C_HELLO])).size(), 0)


func test_snapshot_ida_e_volta() -> void:
	var e := Protocol.EntityState.new()
	e.id = 42
	e.position = Vector3(1.5, 2.25, -8.0)
	e.velocity = Vector3(0, -3, 4.5)
	e.yaw = PI
	e.flags = Protocol.F_ON_FLOOR | Protocol.F_CROUCHED
	var s := Protocol.unpack_snapshot(Protocol.pack_snapshot(900, 55, [e, e]))
	assert_eq(s["tick"], 900)
	assert_eq(s["ack"], 55)
	assert_eq(s["entities"].size(), 2)
	var r: Protocol.EntityState = s["entities"][0]
	assert_eq(r.id, 42)
	assert_true(r.position.is_equal_approx(e.position))
	assert_true(absf(r.yaw - PI) < 0.001)
	assert_eq(r.flags, e.flags)


func test_hello_e_welcome() -> void:
	var h := Protocol.unpack_hello(Protocol.pack_hello("Brisa"))
	assert_eq(h["protocol"], Protocol.GAME_PROTOCOL)
	assert_eq(h["name"], "Brisa")
	var w := Protocol.unpack_welcome(Protocol.pack_welcome(3, 1234, "campo_treino"))
	assert_eq(w["id"], 3)
	assert_eq(w["tick"], 1234)
	assert_eq(w["map"], "campo_treino")


func test_nome_limpo_no_servidor() -> void:
	assert_eq(GameServer._limpar_nome("  \u0001Ana\n  "), "Ana")
	assert_eq(GameServer._limpar_nome("   "), "Jogador")
	assert_eq(GameServer._limpar_nome("abcdefghijklmnopqrstuvwxyz").length(), Protocol.MAX_NAME)
