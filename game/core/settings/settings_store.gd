class_name SettingsStore
extends RefCounted
## Dados das configurações + validação + perfis + persistência.
## Sem dependência de nós/engine: testável isoladamente. O autoload Settings
## usa esta classe e aplica os valores no jogo.

signal changed(section: String, key: String, value: Variant)

var is_mobile := false
var _data := {}


func _init(mobile := false) -> void:
	is_mobile = mobile
	reset_all()


func reset_all() -> void:
	_data.clear()
	for section in SettingsSchema.SPEC:
		_data[section] = {}
		for key in SettingsSchema.SPEC[section]:
			_data[section][key] = SettingsSchema.default_value(section, key)
	# padrões por plataforma
	apply_profile(GraphicsProfiles.default_for(is_mobile), false)
	if is_mobile:
		_data["interface"]["ui_scale"] = 1.15
		_data["graphics"]["vsync"] = true


func get_value(section: String, key: String) -> Variant:
	if not SettingsSchema.has(section, key):
		push_error("Configuração desconhecida: %s/%s" % [section, key])
		return null
	var v: Variant = _data[section][key]
	return v.duplicate(true) if v is Dictionary else v


## Define e valida. Retorna o valor efetivamente salvo.
func set_value(section: String, key: String, value: Variant, emit := true) -> Variant:
	if not SettingsSchema.has(section, key):
		push_error("Configuração desconhecida: %s/%s" % [section, key])
		return null
	if section == "graphics" and key == "profile":
		apply_profile(str(value), emit)
		return _data["graphics"]["profile"]
	var limpo: Variant = SettingsSchema.sanitize(section, key, value)
	_data[section][key] = limpo
	if emit:
		changed.emit(section, key, limpo)
	if section == "graphics" and key in GraphicsProfiles.KEYS:
		var novo := GraphicsProfiles.match_profile(_data["graphics"], is_mobile)
		if novo != _data["graphics"]["profile"]:
			_data["graphics"]["profile"] = novo
			if emit:
				changed.emit("graphics", "profile", novo)
	return limpo


func apply_profile(nome: String, emit := true) -> void:
	if not GraphicsProfiles.PROFILES.has(nome):
		if nome == "custom":
			_data["graphics"]["profile"] = "custom"
		return
	var valores := GraphicsProfiles.values(nome, is_mobile)
	for k in GraphicsProfiles.KEYS:
		_data["graphics"][k] = valores[k]
		if emit:
			changed.emit("graphics", k, _data["graphics"][k])
	_data["graphics"]["profile"] = nome
	if emit:
		changed.emit("graphics", "profile", nome)


func reset_section(section: String) -> void:
	for key in SettingsSchema.SPEC[section]:
		set_value(section, key, SettingsSchema.default_value(section, key))
	if section == "graphics":
		apply_profile(GraphicsProfiles.default_for(is_mobile))


func to_dict() -> Dictionary:
	return _data.duplicate(true)


## Carrega de um dicionário, ignorando chaves desconhecidas e corrigindo valores.
func from_dict(d: Dictionary) -> void:
	reset_all()
	for section in d:
		if not (d[section] is Dictionary) or not SettingsSchema.SPEC.has(section):
			continue
		for key in d[section]:
			if not SettingsSchema.has(section, key):
				continue
			if section == "graphics" and key == "profile":
				continue  # o perfil é deduzido dos valores
			_data[section][key] = SettingsSchema.sanitize(section, key, d[section][key])
	_data["graphics"]["profile"] = GraphicsProfiles.match_profile(_data["graphics"], is_mobile)


func save(path: String) -> Error:
	var dados := to_dict()
	dados["_versao"] = 1
	return SafeFile.write_json(path, dados)


## Retorna true se carregou um arquivo válido (senão mantém os padrões).
func load_file(path: String) -> bool:
	var d: Variant = SafeFile.read_json(path)
	if d is Dictionary:
		from_dict(d)
		return true
	reset_all()
	return false
