extends TestCase
## Inventário completo: picareta permanente, troca de posição, pilhas e limites,
## divisão, descarte, coleta com substituição explícita, conservação (nada some
## nem duplica) e o protocolo v4 das operações.

var enviados: Array = []
var loot: LootServer


func before_each() -> void:
	enviados = []
	loot = LootServer.new(null, func(d): enviados.append(d), 77)


## Soma de itens no inventário + no chão (por id). Usado para provar conservação.
func _total(inv: Inventory) -> Dictionary:
	var t := inv.totals()
	for l in loot.loot.values():
		var k := ""
		if l["ammo"] != 0:
			k = "municao:" + ItemDB.ammo_types()[l["ammo"] - 1]
		elif l["mat"] != 0:
			k = "material:" + ItemDB.material_types()[l["mat"] - 1]
		else:
			k = ItemDB.id_of(l["item"])
		t[k] = int(t.get(k, 0)) + int(l["count"])
	return t


func test_picareta_permanente() -> void:
	var inv := Inventory.new()
	assert_true(inv.pickaxe_selected(), "todo jogador começa com a picareta na mão")
	assert_eq(inv.current().item, "picareta")
	assert_true(ItemDB.is_tool_item("picareta") and not ItemDB.is_slot_item("picareta"))
	assert_false(ItemDB.can_drop("picareta"))
	assert_eq(inv.first_free(), 0, "não ocupa nenhum dos 5 espaços")
	assert_eq(inv.take_from_slot(Inventory.PICKAXE, 1)["error"], Inventory.Err.NOT_DROPPABLE, "não pode ser largada")
	assert_eq(inv.split(Inventory.PICKAXE, 1), Inventory.Err.NOT_DROPPABLE)
	assert_eq(inv.add_item("picareta", 0)["error"], Inventory.Err.INVALID, "não entra nos espaços")
	assert_eq(inv.swap(Inventory.PICKAXE, 0), Inventory.Err.INVALID, "não troca de posição")
	inv.add_item("rajada", 0)
	inv.select(0)
	inv.drop_all()
	assert_true(inv.pickaxe_selected(), "ao morrer, os itens caem e a picareta fica na mão")
	assert_eq(inv.current().item, "picareta")
	assert_true(ResourceLoader.exists("res://assets/armas/%s.glb" % ItemDB.tool_def("picareta")["modelo"]))


func test_trocar_posicoes_e_selecao_segue_o_item() -> void:
	var inv := Inventory.new()
	inv.add_item("rajada", 3)
	inv.add_item("curativo", 0, 4)
	inv.select(0)
	assert_eq(inv.swap(0, 4), Inventory.Err.OK, "mover para um espaço vazio")
	assert_eq(inv.slots[4].item, "rajada")
	assert_true(inv.slots[0].is_empty())
	assert_eq(inv.selected, 4, "a seleção acompanha o item na mão")
	assert_eq(inv.swap(1, 4), Inventory.Err.OK)
	assert_eq(inv.slots[1].item, "rajada")
	assert_eq(inv.slots[4].item, "curativo")
	assert_eq(inv.selected, 1)
	assert_eq(inv.swap(0, 2), Inventory.Err.EMPTY, "dois vazios: nada a fazer")
	assert_eq(inv.swap(1, 1), Inventory.Err.INVALID)
	assert_eq(inv.swap(1, 7), Inventory.Err.INVALID)


func test_limites_de_pilha() -> void:
	var inv := Inventory.new()
	assert_eq(ItemDB.stack_limit("curativo"), 15)
	assert_eq(ItemDB.stack_limit("rajada"), 1)
	assert_eq(ItemDB.stack_limit("media"), 360)
	assert_eq(ItemDB.stack_limit("madeira"), 999)
	var r := inv.add_item("kit_cura", 0, 5)   # pilha 3
	assert_eq(r["taken"], 5)
	assert_eq(inv.slots[0].count, 3)
	assert_eq(inv.slots[1].count, 2, "excedente vai para outro espaço, nunca passa do limite")
	assert_eq(inv.add_ammo("pesada", 100), 60, "munição respeita o máximo")
	assert_eq(inv.add_ammo("pesada", 1), 0)
	assert_eq(inv.add_material("madeira", 1500), 999)
	assert_eq(inv.room_for("kit_cura"), 1 + 3 * 3)


func test_cheio_coleta_parcial_sem_perder() -> void:
	var inv := Inventory.new()
	for id in ["rajada", "trovao", "zumbido", "faisca"]:
		inv.add_item(id, 0)
	inv.add_item("curativo", 0, 13)
	var antes := _total(inv)
	var id := loot.spawn_item("curativo", 0, 5, -1, Vector3(5, 0, 5))
	var total_antes := _total(inv)
	assert_eq(loot.pick_up(id, inv, Vector3(5, 0, 5)), Inventory.Err.OK)
	assert_eq(inv.slots[4].count, 15, "completou a pilha")
	assert_true(loot.loot.has(id), "o que não coube ficou no chão (mesmo item)")
	assert_eq(loot.loot[id]["count"], 3)
	assert_eq(_total(inv), total_antes, "nada sumiu nem duplicou")
	assert_eq(loot.pick_up(id, inv, Vector3(5, 0, 5)), Inventory.Err.FULL, "sem espaço: avisa, não pega em silêncio")
	assert_eq(loot.loot[id]["count"], 3)
	assert_true(antes.size() > 0)


func test_substituir_arma_com_inventario_cheio() -> void:
	var inv := Inventory.new()
	for id in ["rajada", "trovao", "zumbido", "faisca", "gaviao"]:
		inv.add_item(id, 1)
	var pos := Vector3(10, 0, 10)
	var nova := loot.spawn_item("rajada", 4, 1, -1, pos)
	var antes := _total(inv)
	assert_eq(loot.pick_up(nova, inv, pos, -1), Inventory.Err.FULL, "sem escolher o espaço não troca")
	assert_eq(loot.pick_up(nova, inv, pos, 3, pos + Vector3(1, 0, 0)), Inventory.Err.OK)
	assert_eq(inv.slots[3].item, "rajada")
	assert_eq(inv.slots[3].rarity, 4)
	var largada := loot.loot.values().filter(func(l): return ItemDB.id_of(l["item"]) == "faisca" and l["pos"].distance_to(pos) < 2.0)
	assert_eq(largada.size(), 1, "a arma substituída caiu no mundo para outro jogador pegar")
	assert_eq(_total(inv), antes, "conservação: a troca não cria nem apaga itens")


func test_dividir_pilha() -> void:
	var inv := Inventory.new()
	inv.add_item("curativo", 0, 10)
	assert_eq(inv.split(0, 4), Inventory.Err.OK)
	assert_eq(inv.slots[0].count, 6)
	assert_eq(inv.slots[1].count, 4)
	assert_eq(inv.split(0, 6), Inventory.Err.INVALID, "não divide a pilha inteira")
	assert_eq(inv.split(0, 0), Inventory.Err.INVALID)
	for id in ["rajada", "trovao", "zumbido"]:
		inv.add_item(id, 0)
	assert_eq(inv.split(0, 2), Inventory.Err.NO_SPACE, "sem espaço livre: recusa com aviso")
	assert_eq(inv.split(2, 1), Inventory.Err.INVALID, "arma não divide")
	assert_eq(inv.split(9, 1), Inventory.Err.INVALID)


func test_largar_quantidades() -> void:
	var inv := Inventory.new()
	inv.add_item("celula_p", 0, 5)
	inv.add_item("trovao", 2, 1, 3)
	var t := inv.take_from_slot(0, 2)
	assert_eq(t["error"], Inventory.Err.OK)
	assert_eq((t["slot"] as Inventory.Slot).count, 2)
	assert_eq(inv.slots[0].count, 3, "largou só parte da pilha")
	var arma := inv.take_from_slot(1, 9)
	assert_eq((arma["slot"] as Inventory.Slot).mag, 3, "a arma largada mantém o pente")
	assert_true(inv.slots[1].is_empty())
	assert_eq(inv.take_from_slot(1, 1)["error"], Inventory.Err.EMPTY)
	inv.add_ammo("leve", 50)
	assert_eq(inv.take_reserve("leve", 20), 20)
	assert_eq(inv.take_reserve("leve", 999), 30, "não larga mais do que tem")
	assert_eq(inv.take_reserve("leve", 1), 0)


func test_largado_nao_volta_na_hora() -> void:
	var inv := Inventory.new()
	var pos := Vector3(20, 0, 20)
	loot.spawn_ammo("leve", pos, 30, 7, 100)
	assert_false(loot.auto_ammo(inv, pos, 7, 110), "quem largou não recoleta automaticamente na hora")
	assert_true(loot.auto_ammo(inv, pos, 8, 110), "outro jogador pega")
	assert_eq(inv.ammo["leve"], 30)


func test_coleta_automatica_parcial() -> void:
	var inv := Inventory.new()
	inv.add_ammo("pesada", 58)
	var id := loot.spawn_ammo("pesada", Vector3(30, 0, 30), 6)
	assert_true(loot.auto_ammo(inv, Vector3(30, 0, 30)))
	assert_eq(inv.ammo["pesada"], 60)
	assert_eq(loot.loot[id]["count"], 4, "o excedente continua no chão")


func test_itens_proximos() -> void:
	var p := Vector3(40, 0, 40)
	var a := loot.spawn_item("faisca", 0, 1, -1, p + Vector3(2.0, 0, 0))
	var b := loot.spawn_item("curativo", 0, 3, -1, p + Vector3(0.5, 0, 0))
	loot.spawn_ammo("leve", p)
	var perto := loot.loot_near(p)
	assert_eq(perto.size(), 2, "munição não aparece na lista (é automática)")
	assert_eq(perto[0]["id"], b, "do mais perto ao mais longe")
	assert_eq(perto[1]["id"], a)


func test_protocolo_v4() -> void:
	assert_true(Protocol.GAME_PROTOCOL >= 4)
	var op := Protocol.unpack_inv(Protocol.pack_inv({"req": 42, "op": Protocol.OP_SPLIT, "a": 2, "n": 7}))
	assert_eq(op["req"], 42)
	assert_eq(op["op"], Protocol.OP_SPLIT)
	assert_eq(op["a"], 2)
	assert_eq(op["b"], Protocol.SEM_ESPACO)
	assert_eq(op["n"], 7)
	assert_true(Protocol.unpack_inv(PackedByteArray([Protocol.C_INV, 0, 0, 99, 0, 0, 0, 0, 0, 0])).is_empty(), "operação desconhecida")
	assert_true(Protocol.unpack_inv(PackedByteArray([Protocol.C_INV, 1])).is_empty(), "tamanho errado")
	var r := Protocol.unpack_inv_result(Protocol.pack_inv_result(9, Protocol.OP_DROP, Inventory.Err.NOT_DROPPABLE))
	assert_eq(r["code"], Inventory.Err.NOT_DROPPABLE)
	var m := Protocol.unpack_melee(Protocol.pack_melee({"swinger": 3, "pos": Vector3(1, 2, 3), "normal": Vector3.UP,
			"material": ImpactMaterial.PEDRA}))
	assert_eq(m["swinger"], 3)
	assert_eq(m["material"], ImpactMaterial.PEDRA)
	assert_true(m["normal"].distance_to(Vector3.UP) < 0.01)
	var c := Protocol.InputCmd.new()
	c.seq = 1
	c.slot = Protocol.SLOT_PICKAXE
	assert_eq(Protocol.unpack_inputs(Protocol.pack_inputs([c]))[0].slot, Protocol.SLOT_PICKAXE)
	var st := {"hp": 100, "shield": 0, "selected": Protocol.SELECTED_PICKAXE, "action": 0, "action_left_ms": 0,
			"action_total_ms": 0, "slots": [], "ammo": [1, 2, 3, 4], "materials": [10, 0, 999]}
	for i in 5:
		st["slots"].append({"item": 0, "rarity": 0, "mag": 0, "count": 0})
	var s2 := Protocol.unpack_status(Protocol.pack_status(st))
	assert_eq(s2["selected"], Protocol.SELECTED_PICKAXE)
	assert_eq(s2["materials"], [10, 0, 999])


func test_ciclo_da_barra() -> void:
	# picareta -> 1 -> ... -> 5 -> picareta
	assert_eq(InputSampler.next_in_cycle(Inventory.PICKAXE, 1), 0)
	assert_eq(InputSampler.next_in_cycle(4, 1), Inventory.PICKAXE)
	assert_eq(InputSampler.next_in_cycle(Inventory.PICKAXE, -1), 4)
	assert_eq(InputSampler.next_in_cycle(0, -1), Inventory.PICKAXE)


func test_material_dos_assets() -> void:
	assert_eq(ImpactMaterial.from_asset("parede_madeira"), ImpactMaterial.MADEIRA)
	assert_eq(ImpactMaterial.from_asset("rampa_pedra"), ImpactMaterial.PEDRA)
	assert_eq(ImpactMaterial.from_asset("piso_metal"), ImpactMaterial.METAL)
	assert_eq(ImpactMaterial.from_asset("pinheiro_01"), ImpactMaterial.MADEIRA)
	assert_eq(ImpactMaterial.from_asset("pedra_01"), ImpactMaterial.PEDRA)
