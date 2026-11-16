extends TestCase
## BuildServer com o mapa e a física reais (campo de treino): regras de construção,
## crescimento da vida, dano por tiro/picareta, coleta, desabamento em lotes,
## edição só do dono, raio de colisão das peças e restauração das casas do mapa.

var mundo: Mapa
var server: GameServer
var a: GameServer.Cliente
var b: GameServer.Cliente


func _cliente(id: int, pos: Vector3) -> GameServer.Cliente:
	var c := GameServer.Cliente.new()
	c.id = id
	c.peer_id = 900 + id
	c.pawn = Pawn.new()
	c.pawn.entity_id = id
	c.pawn.position = pos
	mundo.add_child(c.pawn)
	server.clientes[c.peer_id] = c
	for t in ItemDB.material_types():
		c.inv.add_material(t, 200)
	return c


func before_each() -> void:
	mundo = CampoTreino.new()
	mundo.com_ambiente = false
	tree.root.add_child(mundo)
	server = GameServer.new(mundo)
	server.kit_inicial = false
	tree.root.add_child(server)
	a = _cliente(1, Vector3(42, 0.1, 42))
	b = _cliente(2, Vector3(46, 0.1, 42))
	await physics_frames(2)


func after_each() -> void:
	server.queue_free()
	mundo.queue_free()


func _construir(c: GameServer.Cliente, escolha: int, cell: Vector3i, rot := 0, mat := 0) -> int:
	return server.build.try_build(c, {"escolha": escolha, "material": mat, "cell": cell, "rot": rot})


func _ticks(n: int) -> void:
	for i in n:
		server.tick += 1
		server.build.update()


func test_regras_de_construcao() -> void:
	var cel := Vector3i(10, 0, 9)                 # perto de (42, 0, 38)
	assert_eq(_construir(a, 1, cel), Inventory.Err.OK, "piso no chão")
	assert_eq(a.inv.materials["madeira"], 190, "custou 10 de madeira")
	assert_eq(_construir(b, 1, cel), Inventory.Err.OCCUPIED, "slot ocupado")
	assert_eq(_construir(a, 1, Vector3i(10, 1, 9)), Inventory.Err.NO_SUPPORT, "solto no ar (4 m acima, sem tocar nada)")
	assert_eq(_construir(a, 1, Vector3i(30, 0, 30)), Inventory.Err.TOO_FAR, "longe demais")
	a.inv.materials["metal"] = 5
	assert_eq(_construir(a, 0, Vector3i(10, 0, 9), 0, 2), Inventory.Err.NO_MATERIAL)
	assert_eq(_construir(a, 0, Vector3i(10, 0, 9), 0, 0), Inventory.Err.OK, "parede apoiada no piso")
	assert_eq(_construir(a, 1, Vector3i(10, 1, 9)), Inventory.Err.OK, "piso em cima da parede")
	assert_eq(server.build.estado.count_players(), 3)


func test_vida_cresce_e_corpo_existe() -> void:
	assert_eq(_construir(a, 0, Vector3i(10, 0, 10), 0, 1), Inventory.Err.OK)
	var p: Construcoes.Peca = server.build.estado.pecas.values().filter(func(x): return x.dono == 1)[0]
	assert_true(p.hp < 0.2 * p.hp_max, "nasce com pouca vida (%.0f)" % p.hp)
	assert_true(p.obra > 0.9)
	_ticks(roundi(1.6 * Protocol.TICK_RATE) + 2)
	assert_eq(roundi(p.hp), 300, "pedra chega a 300 em 1,6 s")
	assert_eq(p.obra, 0.0)
	await physics_frames(2)
	var q := PhysicsRayQueryParameters3D.create(Vector3(42, 2, 36), Vector3(42, 2, 44), Pawn.LAYER_WORLD)
	var r := mundo.get_world_3d().direct_space_state.intersect_ray(q)
	assert_false(r.is_empty(), "a parede tem colisão")
	if not r.is_empty():
		assert_eq(BuildClient.piece_of(r["collider"]), p.id, "o raio sabe qual peça atingiu")


func test_dano_destroi_e_desaba_em_lotes() -> void:
	# piso no chão + 2 andares (parede + piso), tudo ao alcance de quem está no chão
	_construir(a, 1, Vector3i(10, 0, 10))
	for n in 2:
		assert_eq(_construir(a, 0, Vector3i(10, n, 10)), Inventory.Err.OK)
		assert_eq(_construir(a, 1, Vector3i(10, n + 1, 10)), Inventory.Err.OK)
	assert_eq(server.build.estado.count_players(), 5)
	_ticks(40)
	var parede: int = server.build.estado.por_slot[Grade.key(Grade.PAREDE_X, Vector3i(10, 0, 10))]
	assert_false(server.build.damage(parede, 100.0, b), "100 de dano não derruba 150")
	assert_true(server.build.damage(parede, 60.0, b), "o resto destrói")
	assert_eq(server.build.destruidas, 1)
	assert_eq(server.build.estado.count_players(), 4, "desabamento não é imediato (lotes por tick)")
	_ticks(2)
	assert_eq(server.build.estado.count_players(), 1, "os 3 de cima desabaram; o piso do chão ficou")
	assert_eq(server.build.desabaram, 3)


func test_coleta_e_picareta() -> void:
	var arvore := Node3D.new()
	arvore.set_meta("material", ImpactMaterial.MADEIRA)
	var madeira: int = a.inv.materials["madeira"]
	server.build.on_pickaxe(a, arvore, ImpactMaterial.MADEIRA)
	assert_eq(a.inv.materials["madeira"], madeira + int(Grade.config()["coleta"]["arvore"]), "árvore dá madeira")
	var pedra: int = a.inv.materials["pedra"]
	server.build.on_pickaxe(a, arvore, ImpactMaterial.PEDRA)
	assert_eq(a.inv.materials["pedra"], pedra + int(Grade.config()["coleta"]["pedra"]), "rocha dá pedra")
	arvore.free()
	# peça de jogador: a picareta danifica (50) e não dá material
	_construir(b, 0, Vector3i(11, 0, 10), 0, 0)
	_ticks(40)
	var id: int = server.build.estado.por_slot[Grade.key(Grade.PAREDE_X, Vector3i(11, 0, 10))]
	var corpo: Node = server.build.corpos[id]
	var antes: int = a.inv.materials["madeira"]
	for i in 3:
		server.build.on_pickaxe(a, corpo, ImpactMaterial.MADEIRA)
	assert_false(server.build.estado.pecas.has(id), "parede de madeira (150) cai em 3 golpes")
	assert_eq(a.inv.materials["madeira"], antes, "construção de jogador não dá material")


func test_edicao_so_do_dono() -> void:
	_construir(a, 0, Vector3i(10, 0, 10))
	var id: int = server.build.estado.por_slot[Grade.key(Grade.PAREDE_X, Vector3i(10, 0, 10))]
	var porta := 511 & ~((1 << 1) | (1 << 4))
	assert_eq(server.build.try_edit(b, id, porta), Inventory.Err.NOT_OWNER)
	assert_eq(server.build.try_edit(a, id, 0), Inventory.Err.INVALID)
	assert_eq(server.build.try_edit(a, id, porta), Inventory.Err.OK)
	assert_eq(server.build.estado.pecas[id].mask, porta)
	await physics_frames(2)
	# a porta deixa passar no meio e bloqueia nas laterais
	var espaco := mundo.get_world_3d().direct_space_state
	var meio := espaco.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(42, 1, 38), Vector3(42, 1, 42), Pawn.LAYER_WORLD))
	var lado := espaco.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(40.6, 1, 38), Vector3(40.6, 1, 42), Pawn.LAYER_WORLD))
	assert_true(meio.is_empty() or BuildClient.piece_of(meio["collider"]) != id, "porta aberta no meio")
	assert_false(lado.is_empty(), "lateral da parede continua sólida")


func test_limite_de_pecas() -> void:
	var cfg := Grade.config()
	var antes: int = cfg["limite_pecas"]
	cfg["limite_pecas"] = 2
	a.inv.materials["madeira"] = 999
	_construir(a, 1, Vector3i(10, 0, 10))
	_construir(a, 1, Vector3i(11, 0, 10))
	assert_eq(_construir(a, 1, Vector3i(9, 0, 10)), Inventory.Err.PIECE_LIMIT)
	cfg["limite_pecas"] = antes
