extends TestCase
## Tormenta e regras da partida (sem rede): fases, círculos aninhados, dano só na
## vida, protocolo das mensagens da partida e o mapa da ilha (determinístico).

const CFG := {"raio_inicial": 380, "margem_terra": 200, "fases": [
	{"espera_s": 2, "fechamento_s": 3, "raio": 150, "dano": 1},
	{"espera_s": 1, "fechamento_s": 2, "raio": 60, "dano": 5},
	{"espera_s": 1, "fechamento_s": 1, "raio": 0, "dano": 10}]}


func test_fases_e_zonas_aninhadas() -> void:
	for semente in [1, 2, 3, 99, 12345]:
		var t := Tormenta.new(CFG, semente)
		var raio_ant := 380.0
		var centro_ant := Vector2.ZERO
		var mudancas := 0
		var fases_vistas := {}
		for i in 30 * 12:
			fases_vistas[t.fase] = true
			var alvo_c := t.c_para
			var alvo_r := t.r_para
			# a próxima zona cabe inteira dentro da zona atual
			assert_true(centro_ant.distance_to(alvo_c) + alvo_r <= raio_ant + 0.01, "zona %d dentro da anterior (semente %d)" % [t.fase, semente])
			if t.update():
				mudancas += 1
				if not t.fechando:
					raio_ant = t.r_de
					centro_ant = t.c_de
			var c := t.current()
			assert_true(float(c[1]) <= 380.0 + 0.01)
		assert_true(t.terminou, "terminou todas as fases")
		assert_eq(mudancas, 6, "3 fases x (começa a fechar + fechou)")
		assert_eq(t.current()[1], 0.0, "zona final de raio 0")
		assert_eq(fases_vistas.size(), 4)


func test_fechamento_interpolado_e_dano() -> void:
	var t := Tormenta.new(CFG, 7)
	assert_eq(t.damage_per_second(), 1)
	for i in 60:
		t.update()
	assert_true(t.fechando, "depois da espera, fecha")
	for i in 45:
		t.update()
	var meio: float = t.current()[1]
	assert_true(meio < 380.0 and meio > 150.0, "no meio do fechamento o raio está entre os dois (%.0f)" % meio)
	assert_true(t.is_outside(Vector3(1000, 0, 0)))
	assert_false(t.is_outside(Vector3(t.current()[0].x, 0, t.current()[0].y)))


func test_dano_da_tormenta_ignora_escudo() -> void:
	var v := Vitals.new()
	v.shield = 100
	assert_false(v.take_storm_damage(30))
	assert_eq(v.health, 70)
	assert_eq(v.shield, 100, "escudo não protege da Tormenta")
	assert_true(v.take_storm_damage(500))


func test_mensagens_da_partida() -> void:
	var m := Protocol.unpack_match(Protocol.pack_match({"estado": Protocol.MATCH_JOGO, "vivos": 7, "total": 12, "resta_ms": 45000, "vencedor": 0}))
	assert_eq(m["estado"], Protocol.MATCH_JOGO)
	assert_eq(m["vivos"], 7)
	assert_eq(m["resta_ms"], 45000)
	var t := Tormenta.new(CFG, 3)
	var s := Protocol.unpack_storm(Protocol.pack_storm(t.to_dict()))
	assert_eq(s["fases"], 3)
	assert_true(s["c_para"].distance_to(t.c_para) < 0.01)
	assert_eq(s["r_para"], 150.0)
	var r := Protocol.unpack_result(Protocol.pack_result({"colocacao": 3, "total": 12, "eliminacoes": 2, "tempo_s": 300, "vencedor": 5,
			"dano": 812, "baus": 4, "curas": 2, "coleta": 230, "construcoes": 17}))
	assert_eq(r["colocacao"], 3)
	assert_eq(r["vencedor"], 5)
	assert_eq(r["dano"], 812)
	assert_eq(r["baus"], 4)
	assert_eq(r["curas"], 2)
	assert_eq(r["coleta"], 230)
	assert_eq(r["construcoes"], 17)


func test_ilha_deterministica() -> void:
	var a := IlhaVentania.new()
	var b := IlhaVentania.new()
	for p in [Vector2(0, 0), Vector2(-150, 55), Vector2(123.4, -77.7), Vector2(250, 250)]:
		assert_eq(a.ground_height(p.x, p.y), b.ground_height(p.x, p.y), "mesmo relevo no servidor e no cliente")
	assert_true(a.ground_height(261, 0) < 1.5 and a.ground_height(0, -261) < 1.5, "praia junto às bordas jogáveis")
	assert_true(a.ground_height(290, 290) < IlhaVentania.NIVEL_MAR, "fora das bordas é mar")
	var pois := a.points_of_interest()
	assert_eq(pois.size(), 6)
	for p in pois:
		var c: Vector3 = p["pos"]
		assert_true(absf(a.ground_height(c.x + 8, c.z) - c.y) < 0.05, "%s sobre um platô plano" % p["nome"])
	a.free()
	b.free()


func test_mapa_pelo_nome() -> void:
	var m := Mapa.create("ilha_ventania")
	assert_true(m is IlhaVentania)
	var t := Mapa.create("campo_treino")
	assert_true(t is CampoTreino)
	assert_eq(t.chests().size(), CampoTreino.CHESTS.size())
	m.free()
	t.free()
