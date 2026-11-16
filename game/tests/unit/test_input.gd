extends TestCase


func test_serializa_ida_e_volta() -> void:
	var exemplos := [{"t": "key", "code": KEY_W}, {"t": "mouse", "button": MOUSE_BUTTON_RIGHT},
			{"t": "joy", "button": JOY_BUTTON_A}, {"t": "axis", "axis": JOY_AXIS_LEFT_Y, "value": -1.0}]
	for d in exemplos:
		var e := InputSerializer.from_dict(d)
		assert_not_null(e, str(d))
		assert_eq(InputSerializer.to_dict(e), d)


func test_dados_invalidos() -> void:
	assert_null(InputSerializer.from_dict("x"))
	assert_null(InputSerializer.from_dict({"t": "key", "code": -5}))
	assert_null(InputSerializer.from_dict({"t": "mouse", "button": 99}))
	assert_null(InputSerializer.from_dict({"t": "teletransporte"}))


func test_toda_acao_tem_controle_e_teclado() -> void:
	for acao in InputDefaults.ACTIONS:
		var eventos := InputDefaults.events_for(acao)
		assert_false(eventos.is_empty(), acao)
		var tem_teclado := eventos.any(func(e): return InputDefaults.is_keyboard_mouse(e))
		var tem_controle := eventos.any(func(e): return e is InputEventJoypadButton or e is InputEventJoypadMotion)
		var eh_slot: bool = acao.begins_with("slot_") and acao.length() == 6
		var eh_olhar: bool = acao.begins_with("look_")
		if not eh_olhar:
			assert_true(tem_teclado, acao + " sem teclado/mouse")
		if not eh_slot:
			assert_true(tem_controle, acao + " sem controle")


func test_sem_teclas_duplicadas_no_padrao() -> void:
	var vistos := {}
	for acao in InputDefaults.ACTIONS:
		for e in InputDefaults.events_for(acao):
			if InputDefaults.is_keyboard_mouse(e):
				var chave := str(InputSerializer.to_dict(e))
				assert_false(vistos.has(chave), "%s e %s usam %s" % [vistos.get(chave), acao, chave])
				vistos[chave] = acao
