class_name Benchmark
extends RefCounted
## Cálculos e gravação do teste de desempenho (sem dependência de cena: testável).


## frames_ms: duração de cada frame em milissegundos.
static func summarize(frames_ms: PackedFloat32Array, draws: PackedInt32Array, prims: PackedInt32Array) -> Dictionary:
	var n := frames_ms.size()
	if n == 0:
		return {"frames": 0, "fps_medio": 0.0, "fps_1pct": 0.0, "frame_max_ms": 0.0, "draw_calls_medio": 0, "primitivas_medio": 0}
	var total := 0.0
	for f in frames_ms:
		total += f
	var ordenado := frames_ms.duplicate()
	ordenado.sort()
	# "1% pior": média do 1% de frames mais lentos, convertida em FPS
	var k := maxi(1, int(ceil(n * 0.01)))
	var lentos := 0.0
	for i in k:
		lentos += ordenado[n - 1 - i]
	return {
		"frames": n,
		"fps_medio": snappedf(1000.0 * n / total, 0.1),
		"fps_1pct": snappedf(1000.0 / (lentos / k), 0.1),
		"frame_max_ms": snappedf(ordenado[n - 1], 0.01),
		"draw_calls_medio": _media_int(draws),
		"primitivas_medio": _media_int(prims),
	}


static func device_info() -> Dictionary:
	return {
		"versao_jogo": Version.GAME,
		"so": "%s %s" % [OS.get_name(), OS.get_version()],
		"modelo": OS.get_model_name(),
		"cpu": "%s (%d núcleos)" % [OS.get_processor_name(), OS.get_processor_count()],
		"gpu": RenderingServer.get_video_adapter_name(),
		"gpu_fabricante": RenderingServer.get_video_adapter_vendor(),
		"api": RenderingServer.get_video_adapter_api_version(),
		"memoria_video": String.humanize_size(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED)),
		"memoria_estatica": String.humanize_size(OS.get_static_memory_usage()),
		"data": Time.get_datetime_string_from_system(),
	}


static func text_summary(r: Dictionary) -> String:
	return "Ventania %s — teste de desempenho\nFPS médio %.1f · 1%% pior %.1f · frame mais lento %.1f ms\nDraw calls %d · primitivas %d\nPerfil %s · resolução 3D %d%% · sombras %s · MSAA %s · densidade %s · tela %s\n%s · %s\nCPU %s\nGPU %s (%s)\nMemória: vídeo %s, estática %s" % [
		r.get("versao_jogo", ""), r.get("fps_medio", 0.0), r.get("fps_1pct", 0.0), r.get("frame_max_ms", 0.0),
		r.get("draw_calls_medio", 0), r.get("primitivas_medio", 0),
		r.get("perfil", ""), roundi(float(r.get("resolucao_3d", 1.0)) * 100), r.get("sombras", ""), r.get("msaa", ""),
		r.get("densidade", ""), r.get("tela", ""),
		r.get("so", ""), r.get("modelo", ""), r.get("cpu", ""), r.get("gpu", ""), r.get("api", ""),
		r.get("memoria_video", ""), r.get("memoria_estatica", "")]


## Grava resumo (JSON) e frames (CSV). Retorna o caminho do JSON.
static func save(r: Dictionary, frames_ms: PackedFloat32Array, pasta := "user://benchmarks") -> String:
	var nome := "bench_" + Time.get_datetime_string_from_system().replace(":", "-")
	var json := "%s/%s.json" % [pasta, nome]
	SafeFile.write_json(json, r)
	var linhas := PackedStringArray(["frame,ms"])
	for i in frames_ms.size():
		linhas.append("%d,%.3f" % [i, frames_ms[i]])
	SafeFile.write_text("%s/%s.csv" % [pasta, nome], "\n".join(linhas))
	return json


static func _media_int(v: PackedInt32Array) -> int:
	if v.is_empty():
		return 0
	var t := 0
	for x in v:
		t += x
	return t / v.size()
