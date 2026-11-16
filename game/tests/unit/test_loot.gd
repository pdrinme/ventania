extends TestCase
## LootServer sem rede: baús, coleta, troca com inventário cheio e munição automática.

var enviados: Array = []
var loot: LootServer


func before_each() -> void:
	enviados = []
	loot = LootServer.new(null, func(d): enviados.append(d), 1234)


func test_pontos_de_loot_iniciais() -> void:
	assert_true(loot.loot.size() > 5, "sorteou itens no chão (%d)" % loot.loot.size())
	assert_eq(enviados.size(), loot.loot.size(), "cada item foi anunciado")


func test_abrir_bau() -> void:
	var antes := loot.loot.size()
	assert_eq(loot.nearest_chest(CampoTreino.CHESTS[3][0]), 3)
	loot.open_chest(3)
	assert_eq(loot.loot.size(), antes + 4, "arma, munição da arma, consumível e munição extra")
	assert_eq(loot.nearest_chest(CampoTreino.CHESTS[3][0]), -1, "baú aberto não conta")
	loot.update(1)
	loot.update(1 + LootServer.REABASTECER_BAU_TICKS)
	assert_false(loot.chests[3]["open"], "treino: baú reabastece")


func test_pegar_e_trocar() -> void:
	var inv := Inventory.new()
	for id in ["rajada", "trovao", "zumbido", "faisca", "gaviao"]:
		inv.add_item(id, 0)
	var pos := Vector3(50, 0, 50)
	var id_loot := loot.spawn_item("rajada", 4, 1, -1, pos)
	assert_eq(loot.nearest_loot(pos + Vector3(1, 0, 0)), id_loot)
	var total := loot.loot.size()
	assert_true(loot.pick_up(id_loot, inv, pos))
	assert_eq(inv.current().item, "rajada")
	assert_eq(inv.current().rarity, 4)
	assert_eq(loot.loot.size(), total, "item pego sumiu e o trocado caiu no chão")


func test_municao_automatica() -> void:
	var inv := Inventory.new()
	var pos := Vector3(60, 0, 60)
	loot.spawn_ammo("pesada", pos)
	assert_true(loot.auto_ammo(inv, pos + Vector3(0.5, 0, 0)))
	assert_eq(inv.ammo["pesada"], 6)
	assert_false(loot.auto_ammo(inv, pos), "já foi coletada")


func test_largar_inventario() -> void:
	var inv := Inventory.new()
	inv.add_item("rajada", 2)
	inv.add_item("curativo", 0, 5)
	inv.add_ammo("media", 40)
	var antes := loot.loot.size()
	loot.drop_inventory(inv, Vector3(70, 0, 70))
	assert_eq(loot.loot.size(), antes + 3)
	assert_eq(inv.first_free(), 0, "inventário esvaziado")
	assert_eq(inv.ammo["media"], 0)
