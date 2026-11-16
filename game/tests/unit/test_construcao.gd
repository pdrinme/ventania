extends TestCase
## Grade e conectividade (Etapa 5): slots, arestas, ancoragem, apoio para colocar,
## desabamento sem apoio, edição (ladrilhos), escolha do alvo e as casas do mapa.

func _peca(id: int, tipo: int, cell: Vector3i, rot := 0, ancorada := false) -> Construcoes.Peca:
	var p := Construcoes.Peca.new()
	p.id = id
	p.tipo = tipo
	p.cell = cell
	p.rot = rot
	p.material = 0
	p.hp_max = 150.0
	p.hp = 150.0
	p.mask = Grade.full_mask(tipo)
	p.ancorada = ancorada
	return p


func _chao_zero() -> Callable:
	return func(_x: float, _z: float) -> float: return 0.0


func test_conexoes_por_aresta() -> void:
	var e := Construcoes.new()
	e.add(_peca(1, Grade.PISO, Vector3i(0, 0, 0), 0, true))
	e.add(_peca(2, Grade.PAREDE_X, Vector3i(0, 0, 0)))          # borda -Z do piso
	e.add(_peca(3, Grade.PAREDE_Z, Vector3i(0, 0, 0), 1))       # borda -X do piso
	e.add(_peca(4, Grade.PISO, Vector3i(0, 1, 0)))              # piso de cima (no topo das paredes)
	e.add(_peca(5, Grade.RAMPA, Vector3i(0, 0, 1), 0))          # rampa subindo para -Z até o piso de cima
	assert_true(e.neighbors(1).has(2) and e.neighbors(1).has(3), "paredes apoiadas no piso")
	assert_true(e.neighbors(2).has(3), "duas paredes em L compartilham a aresta vertical")
	assert_true(e.neighbors(4).has(2), "piso de cima apoiado no topo da parede")
	assert_false(e.neighbors(1).has(4), "pisos em níveis diferentes não se tocam direto")
	assert_true(e.neighbors(5).has(4), "o topo da rampa encosta na borda do piso de cima")
	assert_eq(e.por_slot.size(), 5)


func test_desaba_sem_apoio() -> void:
	# torre: piso no chão -> parede -> piso -> parede -> piso
	var e := Construcoes.new()
	e.add(_peca(1, Grade.PISO, Vector3i(0, 0, 0), 0, true))
	e.add(_peca(2, Grade.PAREDE_X, Vector3i(0, 0, 0)))
	e.add(_peca(3, Grade.PISO, Vector3i(0, 1, 0)))
	e.add(_peca(4, Grade.PAREDE_X, Vector3i(0, 1, 0)))
	e.add(_peca(5, Grade.PISO, Vector3i(0, 2, 0)))
	var viz := e.neighbors(2)
	e.remove(2)
	var cai := e.unsupported(viz)
	cai.sort()
	assert_eq(cai, [3, 4, 5], "sem a parede de baixo, tudo acima desaba")
	# ponte com duas âncoras: tirar um pilar não derruba
	var p := Construcoes.new()
	p.add(_peca(1, Grade.PAREDE_X, Vector3i(0, 0, 0), 0, true))
	p.add(_peca(2, Grade.PISO, Vector3i(0, 1, 0)))
	p.add(_peca(3, Grade.PISO, Vector3i(1, 1, 0)))
	p.add(_peca(4, Grade.PISO, Vector3i(2, 1, 0)))
	p.add(_peca(5, Grade.PAREDE_X, Vector3i(2, 0, 0), 0, true))
	var v2 := p.neighbors(1)
	p.remove(1)
	assert_eq(p.unsupported(v2), [], "ainda apoiada pelo outro pilar")
	var v3 := p.neighbors(5)
	p.remove(5)
	assert_eq(p.unsupported(v3).size(), 3, "sem os dois pilares, a ponte cai")


func test_apoio_para_colocar() -> void:
	var e := Construcoes.new()
	assert_false(e.would_be_supported(Grade.PISO, Vector3i(0, 3, 0), 0, false), "piso solto no ar não pode")
	assert_true(e.would_be_supported(Grade.PISO, Vector3i(0, 0, 0), 0, true), "no chão pode")
	e.add(_peca(1, Grade.PISO, Vector3i(0, 0, 0), 0, true))
	assert_true(e.would_be_supported(Grade.PAREDE_X, Vector3i(0, 0, 1), 0, false), "parede encostada no piso pode")
	assert_true(Grade.anchored(Grade.PISO, Vector3i(3, 0, 3), 0, _chao_zero()))
	assert_false(Grade.anchored(Grade.PISO, Vector3i(3, 1, 3), 0, _chao_zero()), "4 m acima do chão não ancora")
	assert_true(Grade.anchored(Grade.RAMPA, Vector3i(0, 0, 0), 2, _chao_zero()))


func test_edicao_ladrilhos() -> void:
	assert_eq(Grade.full_mask(Grade.PAREDE_X), 511)
	assert_eq(Grade.full_mask(Grade.PISO), 15)
	assert_false(Grade.editable(Grade.RAMPA))
	var porta := 511 & ~((1 << 1) | (1 << 4))          # meio de baixo + meio do meio
	assert_true(Grade.valid_mask(Grade.PAREDE_X, porta))
	assert_false(Grade.valid_mask(Grade.PAREDE_X, 0), "não pode tirar tudo")
	assert_false(Grade.valid_mask(Grade.PISO, 16), "bit fora do piso")
	assert_eq(Grade.tile_boxes(Grade.PAREDE_X, porta).size(), 7)
	# ladrilho pelo ponto atingido: centro da parede = ladrilho do meio (4)
	var xf := Grade.transform(Grade.PAREDE_X, Vector3i(2, 0, 1), 0)
	assert_eq(Grade.tile_at(Grade.PAREDE_X, Vector3i(2, 0, 1), 0, xf * Vector3(0, 2, 0)), 4)
	assert_eq(Grade.tile_at(Grade.PAREDE_X, Vector3i(2, 0, 1), 0, xf * Vector3(-1.9, 0.2, 0)), 0)
	assert_eq(Grade.tile_at(Grade.PISO, Vector3i(0, 0, 0), 0, Vector3(3.5, 0.1, 3.5)), 3)


func test_alvo_da_peca() -> void:
	# em pé na célula (0,0,0), olhando para -Z (yaw 0)
	var pes := Vector3(2, 0.1, 2)
	var parede := Grade.target(0, pes, 0.0, 0.0)
	assert_eq(parede["tipo"], Grade.PAREDE_X)
	assert_eq(parede["cell"], Vector3i(0, 0, 0), "parede na borda da frente da célula")
	var tras := Grade.target(0, pes, PI, 0.0)
	assert_eq(tras["cell"], Vector3i(0, 0, 1), "olhando para +Z: borda de trás")
	var lado := Grade.target(0, pes, PI * 0.5, 0.0)
	assert_eq(lado["tipo"], Grade.PAREDE_Z)
	assert_eq(Grade.target(1, pes, 0.0, 0.0)["cell"], Vector3i(0, 0, -1), "piso na célula da frente")
	assert_eq(Grade.target(1, pes, 0.0, deg_to_rad(-60))["cell"], Vector3i(0, 0, 0), "olhando para baixo: sob os pés")
	var rampa := Grade.target(2, pes, 0.0, 0.0)
	assert_eq(rampa["rot"], 0, "rampa sobe para onde se olha")
	assert_eq(Grade.target(3, pes, 0.0, 0.0)["cell"], Vector3i(0, 1, 0), "teto em cima")
	assert_eq(Grade.target(0, pes, 0.0, deg_to_rad(50))["cell"].y, 1, "olhando para cima: um nível acima")


func test_casas_do_mapa_na_grade() -> void:
	var a := IlhaVentania.new()
	var b := IlhaVentania.new()
	var lista := a.building_pieces()
	assert_true(lista.size() > 300, "casas da ilha viraram peças (%d)" % lista.size())
	assert_eq(lista.size(), b.building_pieces().size(), "mesmas peças no servidor e no cliente")
	for i in [0, lista.size() / 2, lista.size() - 1]:
		assert_eq(lista[i], b.building_pieces()[i], "mesma ordem (ids iguais)")
	var e := Construcoes.new()
	var altura := func(x: float, z: float) -> float: return a.ground_height(x, z)
	for i in lista.size():
		var d: Dictionary = lista[i]
		assert_false(e.occupied(d["tipo"], d["cell"]), "sem slots repetidos")
		var p := _peca(i + 1, d["tipo"], d["cell"], d["rot"], Grade.anchored(d["tipo"], d["cell"], d["rot"], altura))
		e.add(p)
	var soltas := e.unsupported(e.pecas.keys())
	assert_eq(soltas.size(), 0, "nenhuma casa do mapa começa flutuando (%d soltas)" % soltas.size())
	a.free()
	b.free()


func test_protocolo_construcao() -> void:
	var b := Protocol.unpack_build(Protocol.pack_build({"req": 5, "escolha": 2, "material": 1, "cell": Vector3i(-40, 3, 77), "rot": 3}))
	assert_eq(b["cell"], Vector3i(-40, 3, 77))
	assert_eq(b["escolha"], 2)
	assert_eq(b["rot"], 3)
	assert_true(Protocol.unpack_build(PackedByteArray([Protocol.C_BUILD, 0, 0, 9, 0, 0, 0, 0, 0, 0, 0, 0])).is_empty(), "escolha inválida")
	var p := _peca(70000, Grade.PAREDE_Z, Vector3i(-3, 2, 5), 1)
	p.hp = 77
	p.obra = 0.5
	p.dono = 12
	p.mask = 300
	var d := Protocol.unpack_piece(Protocol.pack_piece(p.to_dict()))
	assert_eq(d["id"], 70000)
	assert_eq(d["mask"], 300)
	assert_eq(d["hp"], 77.0)
	assert_eq(d["dono"], 12)
	var hp := Protocol.unpack_pieces_hp(Protocol.pack_pieces_hp([[3, 10.4, 0.2], [99999, 500, 0.0]]))
	assert_eq(hp.size(), 2)
	assert_eq(hp[1][0], 99999)
	assert_eq(Protocol.unpack_edit(Protocol.pack_edit(1, 123456, 495))["mask"], 495)
