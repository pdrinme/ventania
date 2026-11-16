extends TestCase


func test_itens_carregam() -> void:
	assert_eq(ItemDB.id_of(0), "")
	assert_eq(ItemDB.id_of(ItemDB.index_of("rajada")), "rajada")
	assert_true(ItemDB.is_weapon("gaviao") and ItemDB.is_consumable("curativo"))
	assert_eq(ItemDB.rarities().size(), 5)
	assert_true(ItemDB.damage("rajada", 4) > ItemDB.damage("rajada", 0), "lendária causa mais dano")
	assert_true(ItemDB.reload_time("rajada", 4) < ItemDB.reload_time("rajada", 0), "lendária recarrega mais rápido")
	for id in ItemDB.data()["armas"]:
		var w := ItemDB.weapon(id)
		assert_true(ItemDB.ammo_types().has(w["municao"]), "%s usa munição válida" % id)
		assert_true(ResourceLoader.exists("res://assets/armas/%s.glb" % w["modelo"]), "modelo de %s existe" % id)


func test_inventario_armas_e_troca() -> void:
	var inv := Inventory.new()
	for id in ["rajada", "trovao", "zumbido", "faisca", "gaviao"]:
		assert_null(inv.add_item(id, 1)["dropped"])
	assert_eq(inv.first_free(), -1)
	inv.select(2)
	var r := inv.add_item("rajada", 4)
	assert_eq((r["dropped"] as Inventory.Slot).item, "zumbido", "cheio: troca pelo espaço selecionado")
	assert_eq(inv.current().item, "rajada")
	assert_eq(inv.current().rarity, 4)
	assert_eq(inv.current().mag, 30, "arma nova vem com pente cheio")


func test_consumiveis_empilham() -> void:
	var inv := Inventory.new()
	inv.add_item("curativo", 0, 10)
	var r := inv.add_item("curativo", 0, 10)    # pilha máx. 15
	assert_eq(r["taken"], 10)
	assert_eq(inv.slots[0].count, 15)
	assert_eq(inv.slots[1].count, 5, "excedente abre outra pilha")


func test_municao_e_recarga() -> void:
	var inv := Inventory.new()
	inv.add_item("rajada", 0, 1, 5)
	assert_eq(inv.add_ammo("media", 1000), 360, "respeita o máximo")
	assert_eq(inv.reload_amount(), 25)
	assert_eq(inv.finish_reload(), 25)
	assert_eq(inv.current().mag, 30)
	assert_eq(inv.ammo["media"], 335)


func test_dano_escudo_primeiro() -> void:
	var v := Vitals.new()
	v.add_shield(50, 100)
	var d := v.take_damage(70)
	assert_eq(d["shield"], 50)
	assert_eq(d["health"], 20)
	assert_eq(v.health, 80)
	assert_false(d["killed"])
	assert_true(v.take_damage(500)["killed"])
	assert_false(v.alive())


func test_cura_com_limite() -> void:
	var v := Vitals.new()
	v.take_damage(60)
	assert_eq(v.health, 40)
	assert_eq(v.heal(15, 75), 15)
	assert_eq(v.heal(15, 75), 15)
	assert_eq(v.heal(15, 75), 5, "completa só até 75")
	assert_eq(v.heal(15, 75), 0, "curativo para em 75")
	assert_eq(v.add_shield(25, 50), 25)
	assert_eq(v.add_shield(25, 50), 25)
	assert_eq(v.add_shield(25, 50), 0, "célula pequena para em 50")


func test_hitbox_cabeca_corpo_e_erro() -> void:
	var pes := Vector3(0, 0, -10)
	var corpo := Hitbox.test(Vector3(0, 1.0, 0), Vector3(0, 0, -1), pes, false)
	assert_false(corpo.is_empty())
	assert_false(corpo["head"])
	assert_true(absf(corpo["t"] - 9.6) < 0.05, "t=%s" % corpo.get("t"))
	var cabeca := Hitbox.test(Vector3(0, 1.62, 0), Vector3(0, 0, -1), pes, false)
	assert_true(cabeca["head"])
	assert_true(Hitbox.test(Vector3(1.0, 1.0, 0), Vector3(0, 0, -1), pes, false).is_empty(), "passa ao lado")
	assert_true(Hitbox.test(Vector3(0, 1.62, 0), Vector3(0, 0, -1), pes, true).is_empty(), "agachado: tiro na altura da cabeça passa por cima")


func test_dispersao_deterministica() -> void:
	var a := Combat.pellet_dirs(Vector3.FORWARD, 6.0, 10, Combat.shot_seed(3, 77))
	var b := Combat.pellet_dirs(Vector3.FORWARD, 6.0, 10, Combat.shot_seed(3, 77))
	assert_eq(a.size(), 10)
	for i in 10:
		assert_true(a[i].is_equal_approx(b[i]))
		assert_true(rad_to_deg(a[i].angle_to(Vector3.FORWARD)) <= 6.01, "dentro do cone")
	var w := ItemDB.weapon("gaviao")
	assert_eq(Combat.spread_deg(w, true, true, false, true), 0.0, "precisão mirando é exata")
	assert_true(Combat.spread_deg(ItemDB.weapon("rajada"), false, true, false, false) > float(ItemDB.weapon("rajada")["dispersao"]))


func test_raio_de_mira_passa_pelo_ombro() -> void:
	var r := Combat.aim_ray(Vector3.ZERO, false, 0.0, 0.0)
	assert_true((r["origin"] as Vector3).is_equal_approx(Vector3(0.55, 1.55, 0)))
	assert_true((r["dir"] as Vector3).is_equal_approx(Vector3(0, 0, -1)))
	assert_eq(Combat.pellet_damage("rajada", 0, true), 45)
