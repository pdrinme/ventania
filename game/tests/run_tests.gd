extends SceneTree
## Executa todos os testes unitários em res://tests/unit/test_*.gd.
## Uso: godot --headless --path game -s res://tests/run_tests.gd
## Saída 0 = todos passaram.


func _init() -> void:
	var total := 0
	var falhas := 0
	var arquivos := Array(DirAccess.get_files_at("res://tests/unit")).filter(func(f): return f.begins_with("test_") and f.ends_with(".gd"))
	arquivos.sort()
	for arq in arquivos:
		var script: GDScript = load("res://tests/unit/" + arq)
		if script == null or not script.can_instantiate():
			printerr("NÃO COMPILOU: " + arq)
			falhas += 1
			continue
		var metodos := script.get_script_method_list().map(func(m): return m["name"]).filter(func(n): return n.begins_with("test_"))
		for m in metodos:
			var caso: TestCase = script.new()
			caso._atual = "%s::%s" % [arq.get_basename(), m]
			caso.before_each()
			caso.call(m)
			caso.after_each()
			total += 1
			if caso.failures.is_empty():
				print("  ok  " + caso._atual)
			else:
				falhas += 1
				for f in caso.failures:
					printerr("  FALHOU  " + f)
	_limpar("user://teste_tmp")
	print("TESTES: %d executados, %d falharam" % [total, falhas])
	quit(1 if falhas > 0 or total == 0 else 0)


func _limpar(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for sub in DirAccess.get_directories_at(dir):
		_limpar(dir + "/" + sub)
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir + "/" + f)
	DirAccess.remove_absolute(dir)
