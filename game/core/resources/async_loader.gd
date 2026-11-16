class_name AsyncLoader
extends RefCounted
## Carregamento de recursos em segundo plano (ResourceLoader com threads).
## Uso: var l := AsyncLoader.new(caminho); a cada frame: l.poll(); l.progress; l.done; l.resource

var path := ""
var progress := 0.0
var done := false
var failed := false
var resource: Resource
var _progresso := []


func _init(caminho: String) -> void:
	path = caminho
	if ResourceLoader.has_cached(path):
		resource = ResourceLoader.load(path)
		progress = 1.0
		done = true
		return
	if ResourceLoader.load_threaded_request(path, "", true) != OK:
		failed = true
		done = true


func poll() -> void:
	if done:
		return
	match ResourceLoader.load_threaded_get_status(path, _progresso):
		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			progress = float(_progresso[0]) if _progresso.size() > 0 else progress
		ResourceLoader.THREAD_LOAD_LOADED:
			resource = ResourceLoader.load_threaded_get(path)
			progress = 1.0
			done = true
		_:
			failed = true
			done = true
