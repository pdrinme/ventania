extends TestCase


func test_resumo() -> void:
	var frames := PackedFloat32Array()
	for i in 99:
		frames.append(10.0)
	frames.append(100.0)
	var r := Benchmark.summarize(frames, PackedInt32Array([10, 30]), PackedInt32Array([100, 300]))
	assert_eq(r["frames"], 100)
	assert_eq(r["fps_1pct"], 10.0, "o frame de 100 ms é o 1% pior")
	assert_eq(r["frame_max_ms"], 100.0)
	assert_eq(r["draw_calls_medio"], 20)
	assert_true(r["fps_medio"] > 90.0 and r["fps_medio"] < 92.0)


func test_vazio() -> void:
	assert_eq(Benchmark.summarize(PackedFloat32Array(), PackedInt32Array(), PackedInt32Array())["frames"], 0)


func test_salva_json_e_csv() -> void:
	var dir := tmp_dir()
	var caminho := Benchmark.save({"fps_medio": 60.0}, PackedFloat32Array([16.6, 16.7]), dir)
	assert_true(FileAccess.file_exists(caminho))
	assert_true(FileAccess.file_exists(caminho.replace(".json", ".csv")))
	assert_true(SafeFile.read_text(caminho.replace(".json", ".csv")).begins_with("frame,ms"))
