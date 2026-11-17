extends TestCase
## Etapa 7: protocolo v8 (ficha de sessão), relevância e robustez a pacotes ruins.


func test_hello_e_welcome_com_ficha() -> void:
	var token := 0x1234_5678_9abc_def1
	var h := Protocol.unpack_hello(Protocol.pack_hello("Brisa", token))
	assert_eq(h["token"], token)
	assert_eq(Protocol.unpack_hello(Protocol.pack_hello("Brisa"))["token"], 0)
	var w := Protocol.unpack_welcome(Protocol.pack_welcome(5, 99, "ilha_ventania", token, true))
	assert_eq(w["token"], token)
	assert_true(w["reconectou"])
	assert_false(Protocol.unpack_welcome(Protocol.pack_welcome(5, 99, "ilha_ventania"))["reconectou"])


func test_relevancia_por_distancia() -> void:
	assert_true(GameServer.relevant(9999.0, true, false), "o próprio jogador sempre")
	assert_true(GameServer.relevant(50.0, false, false), "perto: todo snapshot")
	assert_true(GameServer.relevant(GameServer.RELEVANCIA_PERTO_M + 30.0, false, true), "médio: nos snapshots pares")
	assert_false(GameServer.relevant(GameServer.RELEVANCIA_PERTO_M + 30.0, false, false), "médio: pula os ímpares")
	assert_false(GameServer.relevant(GameServer.RELEVANCIA_M + 1.0, false, true), "longe: não vai")


func test_desempacotar_lixo_nao_quebra() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 3000:
		var d := PackedByteArray()
		d.resize(rng.randi_range(0, 64))
		for j in d.size():
			d[j] = rng.randi() & 255
		if d.size() > 0:
			d[0] = [Protocol.C_HELLO, Protocol.C_INPUT, Protocol.C_INV, Protocol.C_BUILD, Protocol.C_EDIT][i % 5]
		# nenhum desempacotador pode travar ou estourar com dados aleatórios
		Protocol.unpack_hello(d)
		Protocol.unpack_inputs(d)
		Protocol.unpack_inv(d)
		Protocol.unpack_build(d)
		Protocol.unpack_edit(d)
	assert_true(true)
