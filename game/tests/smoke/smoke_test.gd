class_name SmokeTest
extends Node
## Teste de fumaça do jogo real (com autoloads): boot -> menu -> configurações
## -> mudar opções -> vitrine (densidade 2, benchmark curto) -> menu -> sair.
## Rodar: godot --headless --path game -- --teste-fumaca
## Código de saída 0 = passou.

var _falhas: PackedStringArray = []


func run(tree: SceneTree) -> void:
	# preso à raiz para sobreviver às trocas de cena
	name = "TesteFumaca"
	tree.root.add_child.call_deferred(self)
	await tree.process_frame
	Log.info("fumaca", "início")
	await _ir(tree, "menu")
	_checar(tree.current_scene != null and tree.current_scene.name == "main_menu", "menu abriu")

	await _ir(tree, "settings")
	_checar(tree.current_scene.name == "settings_menu", "configurações abriu")
	Settings.set_value("graphics", "profile", "quality")
	_checar(Settings.get_value("graphics", "render_scale") == 1.0, "perfil quality aplica render_scale 1.0")
	_checar(is_equal_approx(tree.root.scaling_3d_scale, 1.0), "resolução 3D aplicada na janela")
	Settings.set_value("graphics", "render_scale", 0.6)
	_checar(Settings.get_value("graphics", "profile") == "custom", "mudar opção vira perfil custom")
	Settings.set_value("audio", "master", 0.0)
	_checar(AudioServer.is_bus_mute(AudioServer.get_bus_index("Master")), "volume 0 silencia o Master")
	Settings.set_value("audio", "master", 0.8)
	var tecla := InputEventKey.new()
	tecla.physical_keycode = KEY_F
	InputManager.remap("jump", tecla)
	_checar(InputMap.action_has_event("jump", tecla), "remapear pulo para F")
	InputManager.reset_bindings()
	_checar(not InputMap.action_has_event("jump", tecla), "restaurar atalhos")
	Settings.set_value("graphics", "profile", "performance")

	await _ir(tree, "diagnostics")
	_checar(tree.current_scene.name == "diagnostics", "vitrine abriu")
	var vitrine := tree.current_scene.find_children("*", "KitShowcase", true, false)
	_checar(vitrine.size() == 1, "vitrine montada")
	if vitrine.size() == 1:
		(vitrine[0] as KitShowcase).montar(2)
		await tree.process_frame
		_checar((vitrine[0] as KitShowcase).blocos() == 4, "densidade 2x2")
		_checar(tree.get_nodes_in_group("camera_principal").size() == 1, "câmera no grupo camera_principal")
		var cam := tree.get_nodes_in_group("camera_principal")[0] as Camera3D
		_checar(is_equal_approx(cam.far, Settings.get_value("graphics", "view_distance")), "distância de visão aplicada na câmera")
	for i in 30:
		await tree.process_frame

	var r := Benchmark.summarize(PackedFloat32Array([16.0, 16.0, 33.0]), PackedInt32Array([10, 20, 30]), PackedInt32Array([1, 2, 3]))
	var caminho := Benchmark.save(r, PackedFloat32Array([16.0, 16.0, 33.0]), "user://teste_fumaca")
	_checar(FileAccess.file_exists(caminho), "benchmark salva JSON")

	await _ir(tree, "menu")
	_checar(tree.current_scene.name == "main_menu", "voltou ao menu")
	Settings.save_now()
	_checar(FileAccess.file_exists(Settings.PATH), "configurações salvas em disco")

	if _falhas.is_empty():
		print("FUMACA_OK")
		tree.quit(0)
	else:
		for f in _falhas:
			printerr("FUMACA_FALHA: " + f)
		tree.quit(1)


func _ir(tree: SceneTree, cena: String) -> void:
	var ok: bool = await SceneManager.go(cena)
	_checar(ok, "trocar para " + cena)
	for i in 3:
		await tree.process_frame


func _checar(cond: bool, nome: String) -> void:
	if cond:
		print("  ok  " + nome)
	else:
		_falhas.append(nome)
		printerr("  FALHOU  " + nome)
