extends SceneTree
## Teste headless: carrega todos os GLB de res://assets/ e verifica o resultado da importação.
## Uso: godot --headless --path game --import && godot --headless --path game -s res://tests/test_asset_import.gd

var falhas := 0


func _init() -> void:
	var total := _varrer("res://assets")
	print("ASSETS_IMPORTADOS=%d FALHAS=%d" % [total, falhas])
	quit(1 if falhas > 0 or total == 0 else 0)


func _varrer(pasta: String) -> int:
	var n := 0
	for sub in DirAccess.get_directories_at(pasta):
		n += _varrer(pasta + "/" + sub)
	for arq in DirAccess.get_files_at(pasta):
		if arq.ends_with(".glb"):
			n += 1
			_checar(pasta + "/" + arq)
	return n


func _checar(caminho: String) -> void:
	var cena := load(caminho) as PackedScene
	if cena == null:
		_falha(caminho, "não carregou como PackedScene")
		return
	var raiz := cena.instantiate()
	if not raiz.has_meta("stats"):
		_falha(caminho, "post_import.gd não foi aplicado (metadado 'stats' ausente)")
	else:
		print("%s categoria=%s stats=%s colisoes=%d" % [caminho, raiz.get_meta("categoria"),
				raiz.get_meta("stats"), raiz.find_children("*", "CollisionShape3D", true, false).size()])
	for mi in raiz.find_children("*", "MeshInstance3D", true, false):
		var m: Mesh = (mi as MeshInstance3D).mesh
		for s in m.get_surface_count():
			var mat := m.surface_get_material(s) as BaseMaterial3D
			# Padrão do projeto: texturas extraídas para arquivo (permite compressão VRAM ETC2/S3TC).
			if mat and mat.albedo_texture and not mat.albedo_texture.resource_path.get_file().ends_with(".png"):
				_falha(caminho, "textura embutida no GLB importado; esperado arquivo extraído")
	raiz.free()


func _falha(caminho: String, msg: String) -> void:
	falhas += 1
	printerr("FALHA %s: %s" % [caminho, msg])
