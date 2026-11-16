extends TestCase
## Revisão da Etapa 4: silhueta irregular (não quadrada), litoral real, POIs e loot
## em terra, números do Game Design, estradas, limite de movimento na costa (física
## real), rotas do Ônibus de Batalha, queda livre/planador e a tabela da Tormenta.

var ilha: IlhaVentania


func before_each() -> void:
	ilha = IlhaVentania.new()


func after_each() -> void:
	if is_instance_valid(ilha):
		ilha.free()


func test_silhueta_nao_e_quadrada() -> void:
	var raios := []
	for k in 360:
		raios.append(ilha.coast_radius(k * TAU / 360.0))
	var menor: float = raios.min()
	var maior: float = raios.max()
	assert_true(menor / maior < 0.78, "litoral irregular: raio de %.0f a %.0f m" % [menor, maior])
	# cabos e enseadas: máximos locais do raio ao longo do contorno
	var picos := 0
	for k in 360:
		var a: float = raios[(k + 359) % 360]
		var b: float = raios[k]
		var c: float = raios[(k + 1) % 360]
		if b > a and b >= c and b - minf(a, c) > 0.05:
			picos += 1
	assert_true(picos >= 6, "pelo menos 6 cabos/penínsulas no contorno (%d)" % picos)
	# ocupação da caixa envolvente: quadrado ≈ 1,0; círculo ≈ 0,79; ilha irregular < 0,75
	var terra := 0
	var min_x := 1e9
	var max_x := -1e9
	var min_z := 1e9
	var max_z := -1e9
	for j in range(-100, 101):
		for i in range(-100, 101):
			var x := i * 3.0
			var z := j * 3.0
			if ilha.ground_height(x, z) > 0.4:
				terra += 1
				min_x = minf(min_x, x)
				max_x = maxf(max_x, x)
				min_z = minf(min_z, z)
				max_z = maxf(max_z, z)
	var caixa := ((max_x - min_x) / 3.0 + 1.0) * ((max_z - min_z) / 3.0 + 1.0)
	assert_true(terra / caixa < 0.75, "não preenche a caixa como um quadrado (ocupação %.2f)" % (terra / caixa))
	assert_true(max_x - min_x < 600.0 and max_z - min_z < 600.0, "cabe em 600 × 600 m (%.0f × %.0f)" % [max_x - min_x, max_z - min_z])
	var media: float = raios.reduce(func(a, b): return a + b, 0.0) / raios.size()
	assert_true(absf(media * 2.0 - 524.0) < 60.0, "largura média entre praias ~524 m (%.0f)" % (media * 2.0))


func test_litoral_e_relevo() -> void:
	# a altura cai para o mar exatamente pela linha da costa, em todas as direções
	for k in 24:
		var a := k * TAU / 24.0
		var r := ilha.coast_radius(a)
		var dentro := Vector2(cos(a), sin(a)) * (r - 25.0)
		var fora := Vector2(cos(a), sin(a)) * (r + 12.0)
		assert_true(ilha.ground_height(dentro.x, dentro.y) > 0.4, "terra 25 m antes da costa (ângulo %d)" % k)
		assert_true(ilha.ground_height(fora.x, fora.y) < IlhaVentania.NIVEL_MAR, "mar 12 m depois da costa (ângulo %d)" % k)
	var mais_alto := -1e9
	var mais_baixo := 1e9
	for j in range(-80, 81, 4):
		for i in range(-80, 81, 4):
			var h := ilha.ground_height(i * 3.0, j * 3.0)
			if ilha.inland(i * 3.0, j * 3.0) > 30.0:
				mais_alto = maxf(mais_alto, h)
				mais_baixo = minf(mais_baixo, h)
	assert_true(mais_alto - mais_baixo > 18.0, "geografia com desnível (morros/serra/vale: %.0f m)" % (mais_alto - mais_baixo))


func test_pois_loot_e_numeros() -> void:
	assert_eq(ilha.chests().size(), 37, "37 baús (Game Design)")
	assert_eq(ilha.loot_points().size(), 102, "102 pontos de loot (Game Design)")
	for p in ilha.points_of_interest():
		var c: Vector3 = p["pos"]
		assert_true(ilha.inland(c.x, c.z) > 40.0, "%s em terra (%.0f m da costa)" % [p["nome"], ilha.inland(c.x, c.z)])
	for b in ilha.chests():
		assert_true(ilha.ground_height(b[0].x, b[0].z) > 0.4, "baú em terra")
	for l in ilha.loot_points():
		assert_true(ilha.ground_height(l.x, l.z) > 0.4, "loot em terra")
	# portas e janelas das casas do mapa são ladrilhos válidos da Etapa 5
	var editadas := 0
	for d in ilha.building_pieces():
		if d["mask"] != Grade.full_mask(d["tipo"]):
			editadas += 1
			assert_true(Grade.valid_mask(d["tipo"], d["mask"]), "máscara válida")
	assert_true(editadas > 60, "casas com portas e janelas (%d paredes editadas)" % editadas)


func test_estradas_ligam_os_pois() -> void:
	var asfalto := ilha.roads().filter(func(e): return e["tipo"] != "terra")
	assert_true(asfalto.size() >= 5)
	for e in ilha.roads():
		for p: Vector2 in e["pontos"]:
			assert_true(ilha.ground_height(p.x, p.y) > 0.3, "estrada sobre terra")
	for nome in ["Vila Brisa", "Porto Ferrugem", "Fazenda Girassol", "Pedreira Cinza", "Mirante do Vento"]:
		var poi: Vector3 = ilha.points_of_interest().filter(func(p): return p["nome"] == nome)[0]["pos"]
		var perto := 1e9
		for e in asfalto:
			for p: Vector2 in e["pontos"]:
				perto = minf(perto, p.distance_to(Vector2(poi.x, poi.z)))
		assert_true(perto < 30.0, "%s ligado por asfalto (%.0f m)" % [nome, perto])
	# o terreno acompanha a estrada (aplainado: a pista não flutua nem afunda)
	var e0: Dictionary = asfalto[0]
	var pts: PackedVector2Array = e0["pontos"]
	for k in range(0, pts.size(), 17):
		var lado := (pts[mini(k + 1, pts.size() - 1)] - pts[maxi(k - 1, 0)]).normalized().orthogonal()
		var a := pts[k] + lado * 3.5
		var b := pts[k] - lado * 3.5
		assert_true(absf(ilha.ground_height(a.x, a.y) - ilha.ground_height(b.x, b.y)) < 0.9, "pista sem desnível lateral")


func test_limite_de_movimento_segue_a_costa() -> void:
	tree.root.add_child(ilha)
	await physics_frames(3)
	for a in [0.3, 1.7, 3.0, 4.4, 5.6]:
		var dir := Vector2(cos(a), sin(a))
		var r := ilha.coast_radius(a)
		var p := Pawn.new()
		var inicio := dir * (r - 20.0)
		p.position = Vector3(inicio.x, ilha.ground_height(inicio.x, inicio.y) + 0.5, inicio.y)
		ilha.add_child(p)
		var cmd := Protocol.InputCmd.new()
		cmd.move = Vector2(0, 1)
		cmd.buttons = Protocol.BTN_SPRINT
		cmd.yaw = atan2(-dir.x, -dir.y)
		for i in 30 * 14:
			Movement.step(p, cmd, 1.0 / 30.0)
			await tree.physics_frame
		var d := Vector2(p.global_position.x, p.global_position.z).length()
		assert_true(d < r + 11.0, "parou no limite da costa (%.0f m; costa %.0f m)" % [d, r])
		assert_true(d > r - 2.0, "pôde andar até a praia e a água rasa (%.0f m)" % d)
		p.queue_free()
	ilha.queue_free()


func test_rotas_do_onibus() -> void:
	var terra := func(x: float, z: float) -> bool: return ilha.ground_height(x, z) > 0.4
	var mais_alto := -1e9
	for j in range(-100, 101, 2):
		for i in range(-100, 101, 2):
			mais_alto = maxf(mais_alto, ilha.ground_height(i * 3.0, j * 3.0))
	for semente in 40:
		var o := OnibusBatalha.sortear(semente * 7919 + 3, 100, ilha.limit(), terra)
		assert_true(o.inicio.y > mais_alto + 60.0, "altitude acima do relevo (%.0f > %.0f)" % [o.inicio.y, mais_alto])
		assert_false(terra.call(o.inicio.x, o.inicio.z), "entra pelo mar")
		assert_false(terra.call(o.fim.x, o.fim.z), "sai pelo mar")
		var a := o.position_at(o.abre)
		var b := o.position_at(o.fecha)
		assert_true(terra.call(a.x, a.z) and terra.call(b.x, b.z), "portas abrem e fecham sobre terra")
		assert_true(Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z)) >= 220.0, "atravessa boa parte da ilha")
		var mais_perto := 1e9
		for k in 50:
			var p := o.position_at(o.tick0 + o.duracao * k / 50.0)
			mais_perto = minf(mais_perto, Vector2(p.x, p.z).length())
		assert_true(mais_perto <= 85.0, "passa perto do centro (%.0f m)" % mais_perto)
	var r1 := OnibusBatalha.sortear(1, 0, ilha.limit(), terra)
	var r2 := OnibusBatalha.sortear(2, 0, ilha.limit(), terra)
	assert_true(r1.direction().angle_to(r2.direction()) > 0.05, "a rota varia entre partidas")


func test_queda_livre_e_planador() -> void:
	tree.root.add_child(ilha)
	await physics_frames(3)
	var p := Pawn.new()
	var xz := Vector2(-60, 80)
	var chao := ilha.ground_height(xz.x, xz.y)
	p.position = Vector3(xz.x, 120.0, xz.y)
	ilha.add_child(p)
	p.queda = Pawn.QUEDA_LIVRE
	var cmd := Protocol.InputCmd.new()
	cmd.move = Vector2(0, 1)
	var viu_planador := false
	var passos := 0
	var vel_livre := 0.0
	while p.queda != 0 and passos < 30 * 40:
		Movement.step(p, cmd, 1.0 / 30.0)
		await tree.physics_frame
		passos += 1
		if p.queda == Pawn.QUEDA_LIVRE:
			vel_livre = minf(vel_livre, p.velocity.y)
		if p.queda == Pawn.PLANADOR and not viu_planador:
			viu_planador = true
			var altura := p.global_position.y - ilha.ground_height(p.global_position.x, p.global_position.z)
			assert_true(altura <= Movement.PLANADOR_ALTURA + 2.0, "planador abre perto do chão (%.0f m)" % altura)
	assert_true(viu_planador, "o planador abriu sozinho")
	assert_eq(p.queda, 0, "pousou e voltou ao movimento normal")
	assert_true(absf(vel_livre + Movement.QUEDA_TERMINAL) < 0.5, "queda livre na velocidade terminal (%.1f m/s)" % vel_livre)
	assert_true(passos < 30 * 25, "chega ao chão em menos de 25 s (%.1f s)" % (passos / 30.0))
	assert_true(Vector2(p.global_position.x, p.global_position.z).distance_to(xz) > 60.0, "dá para direcionar a queda")
	assert_true(absf(p.global_position.y - ilha.ground_height(p.global_position.x, p.global_position.z)) < 0.5 or chao > 0.0)
	p.queue_free()
	ilha.queue_free()


func test_tabela_da_tormenta() -> void:
	# Game Design: 7 fases; raios 190/120/75/45/25/10/0; dano 1/1/2/5/8/10/15; espera 60→20 s; fechamento 45→20 s
	var cfg := PartidaBR.carregar_config()
	var f: Array = cfg["tormenta"]["fases"]
	assert_eq(f.size(), 7)
	assert_eq(f.map(func(x): return int(x["raio"])), [190, 120, 75, 45, 25, 10, 0])
	assert_eq(f.map(func(x): return int(x["dano"])), [1, 1, 2, 5, 8, 10, 15])
	assert_eq(int(f[0]["espera_s"]), 60)
	assert_eq(int(f[6]["espera_s"]), 20)
	assert_eq(int(f[0]["fechamento_s"]), 45)
	assert_eq(int(f[6]["fechamento_s"]), 20)
	var total := 0.0
	for x in f:
		total += float(x["espera_s"]) + float(x["fechamento_s"])
	assert_true(total >= 540.0 and total <= 660.0, "~10 min de Tormenta (%.0f s)" % total)
	# a Tormenta avança sozinha até o fim e as zonas ficam em terra, dentro da anterior
	var t := Tormenta.new(cfg["tormenta"], 99, func(c: Vector2, r: float) -> bool: return PartidaBR._zona_valida(ilha, c, r))
	var mudancas := 0
	var ticks := 0
	while not t.terminou and ticks < 30 * 700:
		var antes := [t.c_de, t.r_de]
		if t.update():
			mudancas += 1
			if not t.fechando and not t.terminou:
				assert_true(ilha.ground_height(t.c_para.x, t.c_para.y) > 1.0, "próxima zona em terra")
				assert_true(t.c_de.distance_to(t.c_para) + t.r_para <= t.r_de + 0.01, "dentro da anterior")
		ticks += 1
	assert_true(t.terminou, "chegou à zona final")
	assert_eq(mudancas, 14, "7 fases × (começa a fechar + fechou)")
	assert_true(absf(ticks / 30.0 - total) < 2.0, "duração total %.0f s" % (ticks / 30.0))
