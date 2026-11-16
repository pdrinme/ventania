extends TestCase
## Picareta no servidor, com o mapa e a física de verdade: tempo do golpe, um único
## impacto por golpe, material atingido (madeira/pedra/metal), alcance, cadência,
## acerto em boneco, descarte recusado e permanência ao ser eliminado.

var mundo: CampoTreino
var server: GameServer
var c: GameServer.Cliente
var impactos: Array = []


func before_each() -> void:
	mundo = CampoTreino.new()
	mundo.com_ambiente = false
	tree.root.add_child(mundo)
	server = GameServer.new(mundo)
	server.kit_inicial = false
	tree.root.add_child(server)
	c = GameServer.Cliente.new()
	c.id = 1
	c.peer_id = 999
	c.pawn = Pawn.new()
	c.pawn.entity_id = 1
	mundo.add_child(c.pawn)
	server.clientes[999] = c
	impactos = []
	server.melee_hit.connect(func(_id, _col, mat, pos): impactos.append({"material": mat, "pos": pos}))
	await physics_frames(3)


func after_each() -> void:
	server.queue_free()
	mundo.queue_free()


## Simula n passos do jogador (yaw 0 = olhando para -Z) com o botão de atirar.
func _passos(n: int, atirar: bool, alternar := false) -> Array:
	var acoes := []
	for i in n:
		var cmd := Protocol.InputCmd.new()
		c.simulados += 1
		cmd.seq = c.simulados
		var apertado := atirar and (not alternar or i % 2 == 0)
		if apertado:
			cmd.buttons = Protocol.BTN_FIRE
		server.combat.process(c, cmd)
		acoes.append(server.combat.action_of(c))
	return acoes


func _posicionar(pos: Vector3) -> void:
	c.pawn.global_position = pos
	c.pawn.velocity = Vector3.ZERO
	await physics_frames(2)


func test_um_impacto_por_golpe_no_quadro_certo() -> void:
	# dentro da cabana de madeira, olhando para a parede do fundo (z = -12)
	await _posicionar(Vector3(-16.55, 0.1, -10.2))
	var n := Combat.melee_swing_steps()
	var k := Combat.melee_impact_step()
	assert_true(n >= 15 and n <= 22, "golpe dura ~0,6 s (%d passos)" % n)
	# o golpe começa no 1º passo (k = 0); o impacto é no k-ésimo passo depois dele
	_passos(k, true)
	assert_eq(impactos.size(), 0, "nada antes do quadro de impacto")
	_passos(1, true)
	assert_eq(impactos.size(), 1, "impacto exatamente %d passos depois do início" % k)
	if impactos.size() > 0:
		assert_eq(impactos[0]["material"], ImpactMaterial.MADEIRA, "parede de madeira")
	_passos(n - k - 1, false)
	assert_eq(impactos.size(), 1, "um golpe = um impacto (sem duplicar)")
	assert_eq(c.melee_hits, 1)
	assert_eq(c.swings, 1)


func test_golpes_seguidos_alternam_e_respeitam_cadencia() -> void:
	await _posicionar(Vector3(-16.55, 0.1, -10.2))
	var n := Combat.melee_swing_steps()
	var acoes := _passos(n * 3, true)
	assert_eq(c.swings, 3, "segurando: 3 golpes em 3 durações")
	assert_eq(impactos.size(), 3)
	assert_eq(acoes[2][0], Protocol.ACT_SWING, "1º golpe")
	assert_eq(acoes[n + 2][0], Protocol.ACT_SWING_B, "2º golpe da sequência alterna o lado")
	assert_eq(acoes[2 * n + 2][0], Protocol.ACT_SWING, "3º volta ao primeiro")
	# apertar e soltar a cada passo não acelera os golpes
	c.swings = 0
	_passos(n * 4, true, true)
	assert_true(c.swings <= 4, "cadência validada no servidor (%d golpes em %d passos)" % [c.swings, n * 4])


func test_materiais_pedra_e_metal() -> void:
	await _posicionar(Vector3(-0.55, 0.0, -11.5))       # diante da rampa de pedra
	_passos(Combat.melee_swing_steps(), true)
	assert_eq(impactos.size(), 1)
	assert_eq(impactos[-1]["material"], ImpactMaterial.PEDRA, "rampa de pedra")
	await _posicionar(Vector3(15.45, 0.1, -10.2))      # dentro da caixa de metal
	_passos(Combat.melee_swing_steps(), true)
	assert_eq(impactos.size(), 2)
	assert_eq(impactos[-1]["material"], ImpactMaterial.METAL, "parede de metal")


func test_fora_de_alcance_nao_registra() -> void:
	await _posicionar(Vector3(60, 0, 60))                # campo aberto
	_passos(Combat.melee_swing_steps() * 2, true)
	assert_eq(c.swings, 2, "golpeia no ar")
	assert_eq(impactos.size(), 0, "nada ao alcance: nenhum impacto")
	assert_eq(c.melee_hits, 0)


func test_acerta_boneco() -> void:
	# boneco em (0, 0, -4); o raio sai do ombro (0,55 m à direita)
	await _posicionar(Vector3(-0.55, 0.0, -2.4))
	var vit: Vitals = server.bonecos[1]["vit"]
	var escudo_antes := vit.shield
	_passos(Combat.melee_swing_steps(), true)
	assert_eq(c.melee_hits, 1)
	assert_eq(escudo_antes - vit.shield, int(ItemDB.tool_def("picareta")["dano_jogador"]), "dano do golpe no boneco")
	assert_eq(impactos.size(), 0, "jogador/boneco não é impacto de cenário")


func test_nao_golpeia_sem_picareta_na_mao() -> void:
	await _posicionar(Vector3(-16.55, 0.1, -10.2))
	c.inv.add_item("faisca", 0)
	c.inv.select(0)
	_passos(Combat.melee_swing_steps(), true)
	assert_eq(c.swings, 0)
	# trocar para a picareta pela entrada (slot 6)
	var cmd := Protocol.InputCmd.new()
	c.simulados += 1
	cmd.slot = Protocol.SLOT_PICKAXE
	server.combat.process(c, cmd)
	assert_true(c.inv.pickaxe_selected(), "seleção dedicada da picareta")


func test_operacoes_do_servidor() -> void:
	await _posicionar(Vector3(30, 0, 40))
	assert_eq(server.combat.inventory_op(c, {"op": Protocol.OP_DROP, "a": Protocol.SEM_ESPACO, "b": 255, "n": 1}),
			Inventory.Err.NOT_DROPPABLE, "servidor recusa largar a picareta")
	c.inv.add_item("trovao", 3, 1, 2)
	c.inv.add_item("curativo", 0, 9)
	var antes := server.loot.loot.size()
	assert_eq(server.combat.inventory_op(c, {"op": Protocol.OP_DROP, "a": 1, "b": 255, "n": 4}), Inventory.Err.OK)
	assert_eq(c.inv.slots[1].count, 5)
	assert_eq(server.loot.loot.size(), antes + 1, "o item largado aparece no mundo")
	var l: Dictionary = server.loot.loot.values().filter(func(x): return ItemDB.id_of(x["item"]) == "curativo" and x["count"] == 4)[0]
	assert_true(absf(l["pos"].y - 0.02) < 0.05, "caiu no chão (y=%.2f)" % l["pos"].y)
	assert_true(Vector2(l["pos"].x - 30, l["pos"].z - 40).length() > 1.3, "longe o bastante para não recoletar na hora")
	assert_eq(server.combat.inventory_op(c, {"op": Protocol.OP_SWAP, "a": 0, "b": 3, "n": 0}), Inventory.Err.OK)
	assert_eq(c.inv.slots[3].item, "trovao")
	assert_eq(server.combat.inventory_op(c, {"op": Protocol.OP_SPLIT, "a": 1, "b": 255, "n": 2}), Inventory.Err.OK)
	# pegar de volta pela tela de loot (com validação de distância)
	assert_eq(server.combat.inventory_op(c, {"op": Protocol.OP_PICKUP, "a": 255, "b": 255, "n": 0, "loot": l["id"]}), Inventory.Err.OK)
	assert_false(server.loot.loot.has(l["id"]))
	var longe := server.loot.spawn_item("rajada", 0, 1, -1, Vector3(80, 0, 80))
	assert_eq(server.combat.inventory_op(c, {"op": Protocol.OP_PICKUP, "a": 255, "b": 255, "n": 0, "loot": longe}),
			Inventory.Err.TOO_FAR, "não pega de longe")
	assert_eq(server.combat.inventory_op(c, {"op": Protocol.OP_PICKUP, "a": 255, "b": 255, "n": 0, "loot": 64999}),
			Inventory.Err.GONE)


func test_picareta_nao_se_perde_ao_ser_eliminado() -> void:
	await _posicionar(Vector3(30, 0, 30))
	c.inv.add_item("rajada", 2)
	c.inv.select(0)
	server.combat.eliminate(c, 2, "rajada")
	assert_true(c.inv.pickaxe_selected())
	assert_eq(c.inv.current().item, "picareta")
	assert_eq(c.inv.first_free(), 0, "os outros itens caíram")
	assert_true(server.loot.loot.values().any(func(x): return ItemDB.id_of(x["item"]) == "rajada"))
	assert_false(server.loot.loot.values().any(func(x): return ItemDB.id_of(x["item"]) == "picareta"), "a picareta nunca vai ao chão")
