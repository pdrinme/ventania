class_name SafeFile
extends RefCounted
## Gravação de arquivos à prova de queda de energia/crash:
## escreve em <arquivo>.tmp, move o antigo para .bak, renomeia o .tmp e apaga o .bak.
## Na leitura, se o arquivo principal faltar mas houver .bak, recupera o .bak.


static func write_text(path: String, text: String) -> Error:
	var dir := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		var e := DirAccess.make_dir_recursive_absolute(dir)
		if e != OK:
			return e
	var tmp := path + ".tmp"
	var bak := path + ".bak"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(text)
	f.flush()
	f.close()
	if FileAccess.file_exists(path):
		if FileAccess.file_exists(bak):
			DirAccess.remove_absolute(bak)
		var e1 := DirAccess.rename_absolute(path, bak)
		if e1 != OK:
			return e1
	var e2 := DirAccess.rename_absolute(tmp, path)
	if e2 != OK:
		return e2
	if FileAccess.file_exists(bak):
		DirAccess.remove_absolute(bak)
	return OK


## Retorna "" se não existir nem houver backup.
static func read_text(path: String) -> String:
	var alvo := path
	if not FileAccess.file_exists(alvo):
		if FileAccess.file_exists(path + ".bak"):
			alvo = path + ".bak"
		else:
			return ""
	return FileAccess.get_file_as_string(alvo)


static func write_json(path: String, data: Variant) -> Error:
	return write_text(path, JSON.stringify(data, "\t"))


## Retorna null se o arquivo não existir ou o JSON for inválido.
static func read_json(path: String) -> Variant:
	var texto := read_text(path)
	if texto.is_empty():
		return null
	var json := JSON.new()
	if json.parse(texto) != OK:
		return null
	return json.data
