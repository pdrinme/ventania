extends TestCase


func test_escreve_e_le_json() -> void:
	var p := tmp_dir() + "/a.json"
	assert_eq(SafeFile.write_json(p, {"x": 1, "y": [1, 2]}), OK)
	var d: Variant = SafeFile.read_json(p)
	assert_eq(int(d["x"]), 1)
	assert_false(FileAccess.file_exists(p + ".tmp"), "não sobra .tmp")
	assert_false(FileAccess.file_exists(p + ".bak"), "não sobra .bak")


func test_sobrescreve() -> void:
	var p := tmp_dir() + "/b.txt"
	SafeFile.write_text(p, "um")
	SafeFile.write_text(p, "dois")
	assert_eq(SafeFile.read_text(p), "dois")


func test_recupera_backup() -> void:
	var p := tmp_dir() + "/c.json"
	SafeFile.write_json(p, {"v": 7})
	DirAccess.rename_absolute(p, p + ".bak")  # simula queda no meio da troca
	assert_eq(int(SafeFile.read_json(p)["v"]), 7)


func test_json_invalido_retorna_null() -> void:
	var p := tmp_dir() + "/d.json"
	SafeFile.write_text(p, "{ quebrado")
	assert_null(SafeFile.read_json(p))
	assert_null(SafeFile.read_json(tmp_dir() + "/nao_existe.json"))
