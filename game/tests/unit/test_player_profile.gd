extends TestCase

const EXEMPLO := {"player_id": "p_123", "display_name": "Brisa", "level": 7, "xp": 1200, "currency": 450,
		"equipped": {"traje": "recruta_base_01", "slot_falso": "x"}, "owned": ["recruta_base_01", "recruta_base_01", 5],
		"emotes": ["acenar"], "season_id": "t1", "pass_level": 3, "pass_xp": 90, "updated_at": 1700000000}


func test_from_dict_valida() -> void:
	var p := PlayerProfile.from_dict(EXEMPLO)
	assert_not_null(p)
	assert_eq(p.level, 7)
	assert_eq(p.currency, 450)
	assert_true(p.owns("recruta_base_01"))
	assert_eq(p.owned.size(), 1, "duplicados e não-strings removidos")
	assert_false(p.equipped.has("slot_falso"))


func test_rejeita_sem_id() -> void:
	assert_null(PlayerProfile.from_dict({"display_name": "x"}))
	assert_null(PlayerProfile.from_dict([]))


func test_valores_negativos_corrigidos() -> void:
	var p := PlayerProfile.from_dict({"player_id": "a", "display_name": "b", "level": -3, "currency": -10})
	assert_eq(p.level, 1)
	assert_eq(p.currency, 0)


func test_cache_ida_e_volta() -> void:
	var caminho := tmp_dir() + "/perfil.json"
	var p := PlayerProfile.from_dict(EXEMPLO)
	assert_eq(p.save_cache(caminho), OK)
	var q := PlayerProfile.load_cache(caminho)
	assert_eq(q.to_dict(), p.to_dict())
