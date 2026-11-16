extends TestCase


func test_padrao_pc_e_celular() -> void:
	assert_eq(SettingsStore.new(false).get_value("graphics", "profile"), "balanced")
	var cel := SettingsStore.new(true)
	assert_eq(cel.get_value("graphics", "profile"), "performance")
	assert_eq(cel.get_value("graphics", "render_scale"), 0.7)
	assert_eq(cel.get_value("interface", "ui_scale"), 1.15)


func test_perfil_preenche_valores() -> void:
	var s := SettingsStore.new()
	s.set_value("graphics", "profile", "quality")
	assert_eq(s.get_value("graphics", "render_scale"), 1.0)
	assert_eq(s.get_value("graphics", "msaa"), 2)
	assert_eq(s.get_value("graphics", "shadows"), "high")


func test_mudar_opcao_vira_custom_e_volta() -> void:
	var s := SettingsStore.new()
	s.set_value("graphics", "profile", "quality")
	s.set_value("graphics", "shadows", "off")
	assert_eq(s.get_value("graphics", "profile"), "custom")
	s.set_value("graphics", "shadows", "high")
	assert_eq(s.get_value("graphics", "profile"), "quality", "valores iguais ao perfil voltam ao perfil")


func test_validacao_limites_e_tipos() -> void:
	var s := SettingsStore.new()
	assert_eq(s.set_value("graphics", "render_scale", 3.0), 1.0)
	assert_eq(s.set_value("graphics", "render_scale", 0.1), 0.5)
	assert_eq(s.set_value("graphics", "msaa", 3), 0, "msaa fora das opções volta ao padrão")
	assert_eq(s.set_value("graphics", "shadows", "ultra"), "low")
	assert_eq(s.set_value("graphics", "vsync", "sim"), true)
	assert_eq(s.set_value("audio", "master", -1), 0.0)
	assert_eq(s.set_value("network", "server_url", "  http://x:1  "), "http://x:1")


func test_sinal_changed() -> void:
	var s := SettingsStore.new()
	var recebidos := []
	s.changed.connect(func(sec, k, v): recebidos.append("%s/%s" % [sec, k]))
	s.set_value("audio", "music", 0.5)
	assert_true("audio/music" in recebidos)


func test_salvar_e_carregar() -> void:
	var p := tmp_dir() + "/settings.json"
	var a := SettingsStore.new()
	a.set_value("graphics", "render_scale", 0.6)
	a.set_value("audio", "sfx", 0.25)
	a.set_value("controls", "bindings", {"jump": [{"t": "key", "code": KEY_F}]})
	assert_eq(a.save(p), OK)
	var b := SettingsStore.new()
	assert_true(b.load_file(p))
	assert_eq(b.get_value("graphics", "render_scale"), 0.6)
	assert_eq(b.get_value("graphics", "profile"), "custom")
	assert_eq(b.get_value("audio", "sfx"), 0.25)
	assert_eq(int(b.get_value("controls", "bindings")["jump"][0]["code"]), KEY_F)


func test_arquivo_corrompido_usa_padrao() -> void:
	var p := tmp_dir() + "/ruim.json"
	SafeFile.write_text(p, "lixo")
	var s := SettingsStore.new()
	assert_false(s.load_file(p))
	assert_eq(s.get_value("graphics", "profile"), "balanced")


func test_chaves_desconhecidas_ignoradas() -> void:
	var s := SettingsStore.new()
	s.from_dict({"graphics": {"render_scale": 0.9, "hack": 1}, "nao_existe": {"a": 1}, "audio": "x"})
	assert_eq(s.get_value("graphics", "render_scale"), 0.9)
	assert_false(s.to_dict().has("nao_existe"))


func test_perfis_usam_chaves_validas() -> void:
	for nome in GraphicsProfiles.PROFILES:
		for k in GraphicsProfiles.KEYS:
			var v: Variant = GraphicsProfiles.PROFILES[nome][k]
			assert_eq(SettingsSchema.sanitize("graphics", k, v), v, "%s.%s" % [nome, k])
