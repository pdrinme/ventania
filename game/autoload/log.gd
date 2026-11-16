extends Node
## Log com categorias. Também mantém as últimas linhas em memória (tela de
## diagnóstico / copiar para reportar problemas). O arquivo em disco é o log
## nativo da Godot (user://logs/godot.log), ligado no project.godot.

const MAX_LINHAS := 300
var lines: PackedStringArray = []


func info(cat: String, msg: String) -> void:
	_add("INFO", cat, msg)


func warn(cat: String, msg: String) -> void:
	_add("AVISO", cat, msg)
	push_warning("[%s] %s" % [cat, msg])


func error(cat: String, msg: String) -> void:
	_add("ERRO", cat, msg)
	push_error("[%s] %s" % [cat, msg])


func _add(nivel: String, cat: String, msg: String) -> void:
	var t := Time.get_time_string_from_system()
	var linha := "%s %s [%s] %s" % [t, nivel, cat, msg]
	print(linha)
	lines.append(linha)
	if lines.size() > MAX_LINHAS:
		lines = lines.slice(lines.size() - MAX_LINHAS)
