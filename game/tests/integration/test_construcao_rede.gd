extends SceneTree
## ACEITE DA ETAPA 5: dois clientes construindo e editando pela rede (ENet) sem
## divergência. Servidor e cada cliente têm o próprio mundo físico (SubViewport
## com own_world_3d) e a própria Ilha Ventania; os clientes só aplicam o que o
## servidor envia (BuildClient). Compara peça a peça (tipo, slot, rotação,
## material, ladrilhos e vida) entre servidor, A, B e um terceiro que entra depois.
## Uso: godot --headless --path game -s res://tests/integration/test_construcao_rede.gd

var falhas := 0
var server: GameServer


class Jogador:
	extends Node
	var client := GameClient.new()
	var build := BuildClient.new()
	var mundo: IlhaVentania
	var seq := 0
	var resultados: Array = []

	func iniciar(nome: String, porta: int) -> void:
		var vp := SubViewport.new()
		vp.own_world_3d = true
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		add_child(vp)
		mundo = IlhaVentania.new()
		mundo.com_ambiente = false
		vp.add_child(mundo)
		build.com_visual = false
		vp.add_child(build)
		build.setup(mundo)
		add_child(client)
		client.piece.connect(build.on_piece)
		client.piece_gone.connect(build.on_gone)
		client.pieces_hp.connect(build.on_hp)
		client.build_reset.connect(build.on_reset)
		client.inventory_result.connect(func(r): resultados.append(r))
		client.connect_to("127.0.0.1", porta, nome)

	func _physics_process(_dt: float) -> void:
		client.poll()
		if client.connected:
			seq += 1
			var c := Protocol.InputCmd.new()
			c.seq = seq
			client.send_inputs([c])


func _checar(ok: bool, msg: String) -> void:
	print(("  ok  " if ok else "  FALHOU  ") + msg)
	if not ok:
		falhas += 1


func _esperar(n: int) -> void:
	for i in n:
		await physics_frame


func _igual(nome: String, j: Jogador) -> void:
	var s := server.build.estado.snapshot()
	var c := j.build.estado.snapshot()
	var dif := []
	for id in s:
		if not c.has(id) or c[id] != s[id]:
			dif.append([id, s[id], c.get(id)])
	for id in c:
		if not s.has(id):
			dif.append([id, null, c[id]])
	_checar(dif.is_empty(), "%s igual ao servidor (%d peças)%s" % [nome, s.size(), "" if dif.is_empty() else " — diferenças: %s" % str(dif.slice(0, 3))])


func _init() -> void:
	await process_frame
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(vp)
	var mundo := IlhaVentania.new()
	mundo.com_ambiente = false
	vp.add_child(mundo)
	server = GameServer.new(mundo, 5, "treino")
	root.add_child(server)
	var porta := 0
	for p in [24861, 24862, 24863]:
		if server.start(p, "127.0.0.1") == OK:
			porta = p
			break
	var a := Jogador.new()
	var b := Jogador.new()
	root.add_child(a)
	root.add_child(b)
	a.iniciar("A", porta)
	b.iniciar("B", porta)
	for i in 120:
		await physics_frame
		if a.client.connected and b.client.connected and server.player_count() == 2:
			break
	await _esperar(10)
	_checar(server.build.estado.pecas.size() > 300, "servidor criou as casas do mapa (%d peças)" % server.build.estado.pecas.size())
	_igual("A (só o mapa)", a)
	var ca: GameServer.Cliente = server.client_by_id(a.client.my_id)
	var cb: GameServer.Cliente = server.client_by_id(b.client.my_id)
	# os dois lado a lado num campo aberto
	# terreno livre: em terra, longe da costa, sem construções do mapa num raio de ~16 m
	var base := Vector3(-100, 0, -40)
	for tentativa in 200:
		var q := Vector3(-160.0 + (tentativa % 20) * 16.0, 0, -160.0 + (tentativa / 20) * 32.0)
		if mundo.ground_height(q.x, q.z) < 2.0 or mundo.inland(q.x, q.z) < 40.0:
			continue
		var cq := Vector3i(floori(q.x / 4.0), 0, floori(q.z / 4.0))
		var livre := true
		for p: Construcoes.Peca in server.build.estado.pecas.values():
			if absi(p.cell.x - cq.x) <= 4 and absi(p.cell.z - cq.z) <= 4:
				livre = false
				break
		if livre:
			base = q
			break
	base.y = mundo.ground_height(base.x, base.z) + 0.2
	for c in [ca, cb]:
		c.pawn.global_position = base + (Vector3(0, 0, 0) if c == ca else Vector3(8, 0, 0))
	await _esperar(5)
	var ba := Grade.target(1, ca.pawn.global_position, 0.0, deg_to_rad(-60))["cell"] as Vector3i
	var bb := Grade.target(1, cb.pawn.global_position, 0.0, deg_to_rad(-60))["cell"] as Vector3i
	# A: piso, parede na frente, parede do lado, piso em cima, rampa; B: piso, parede, metal
	var pedidos_a := [[1, 0, ba, 0], [0, 0, ba, 0], [0, 1, ba, 1], [1, 0, ba + Vector3i(0, 1, 0), 0], [2, 0, ba + Vector3i(0, 0, 1), 0]]
	var pedidos_b := [[1, 1, bb, 0], [0, 2, bb, 0], [0, 1, bb + Vector3i(0, 0, 1), 2], [1, 0, bb, 0]]
	for i in maxi(pedidos_a.size(), pedidos_b.size()):
		if i < pedidos_a.size():
			var p: Array = pedidos_a[i]
			a.client.send_build(p[0], p[1], p[2], p[3])
		if i < pedidos_b.size():
			var p: Array = pedidos_b[i]
			b.client.send_build(p[0], p[1], p[2], p[3])
		await _esperar(2)
	await _esperar(20)
	var ok_a := a.resultados.filter(func(r): return r["op"] == Protocol.OP_BUILD and r["code"] == Inventory.Err.OK).size()
	var ok_b := b.resultados.filter(func(r): return r["op"] == Protocol.OP_BUILD and r["code"] == Inventory.Err.OK).size()
	_checar(ok_a == 5, "A construiu 5 peças (%d)" % ok_a)
	_checar(ok_b == 3, "B construiu 3 peças (%d)" % ok_b)
	_checar(b.resultados.any(func(r): return r["code"] == Inventory.Err.OCCUPIED), "slot já ocupado: recusado %s" % str(b.resultados.map(func(r): return r["code"])))
	_checar(ca.inv.materials["madeira"] == 300 - 40 and ca.inv.materials["pedra"] == 300 - 10, "materiais de A descontados (madeira %d, pedra %d)" % [ca.inv.materials["madeira"], ca.inv.materials["pedra"]])
	# edição: A abre uma porta; B tenta editar a parede de A
	var parede_a: int = server.build.estado.por_slot[Grade.key(Grade.PAREDE_X, ba)]
	var porta_mask := 511 & ~((1 << 1) | (1 << 4))
	a.client.send_edit(parede_a, porta_mask)
	b.client.send_edit(parede_a, 1)
	await _esperar(15)
	_checar(server.build.estado.pecas[parede_a].mask == porta_mask, "A editou a própria parede (porta)")
	_checar(b.resultados.any(func(r): return r["op"] == Protocol.OP_EDIT and r["code"] == Inventory.Err.NOT_OWNER), "B não pode editar a parede de A")
	# dano, destruição e desabamento: tiro de B no pé da construção de A; picareta em casa do mapa
	await _esperar(int(2.6 * Protocol.TICK_RATE))
	var lateral: int = server.build.estado.por_slot[Grade.key(Grade.PAREDE_Z, ba)]
	server.build.damage(lateral, 40.0, cb)
	var id_mapa: int = 1
	var madeira_b: int = cb.inv.materials[Grade.MATERIAIS[server.build.estado.pecas[id_mapa].material]]
	server.build.on_pickaxe(cb, server.build.corpos[id_mapa], ImpactMaterial.MADEIRA)
	_checar(cb.inv.materials[Grade.MATERIAIS[server.build.estado.pecas[id_mapa].material]] > madeira_b, "picareta numa casa do mapa coletou material")
	# o piso de cima se apoia nas duas paredes e no topo da rampa: tirando os três, ele desaba
	var de_cima: int = server.build.estado.por_slot[Grade.key(Grade.PISO, ba + Vector3i(0, 1, 0))]
	var rampa: int = server.build.estado.por_slot[Grade.key(Grade.RAMPA, ba + Vector3i(0, 0, 1))]
	var desabaram := server.build.desabaram
	for id in [lateral, parede_a, rampa]:
		server.build.damage(id, 9999.0, cb)
	await _esperar(30)
	_checar(not server.build.estado.pecas.has(de_cima) and server.build.desabaram > desabaram, "sem apoio, o piso de cima desabou")
	await _esperar(20)
	_igual("Cliente A", a)
	_igual("Cliente B", b)
	# terceiro jogador entra depois e recebe o estado completo
	var c3 := Jogador.new()
	root.add_child(c3)
	c3.iniciar("C", porta)
	for i in 150:
		await physics_frame
		if c3.client.connected:
			break
	await _esperar(30)
	_igual("Cliente C (entrou depois)", c3)
	# partida nova: casas do mapa restauradas e construções removidas em todos
	server.build.reset()
	await _esperar(20)
	_checar(server.build.estado.count_players() == 0 and server.build.estado.pecas.has(id_mapa), "reset: sem construções de jogadores, mapa inteiro")
	_igual("Cliente A depois do reset", a)
	_igual("Cliente C depois do reset", c3)
	server.stop()
	print("CONSTRUCAO_REDE %s" % ("OK" if falhas == 0 else "FALHA (%d)" % falhas))
	quit(0 if falhas == 0 else 1)
