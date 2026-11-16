extends Node
## Registra as ações do jogo no InputMap, aplica remapeamentos salvos e
## detecta o tipo de dispositivo em uso (para trocar ícones/layout).

signal device_changed(device: String)  # "teclado_mouse" | "controle" | "toque"
signal bindings_changed

var device := "teclado_mouse"


func _ready() -> void:
	_registrar_acoes()
	if Settings.is_mobile:
		device = "toque"


func _registrar_acoes() -> void:
	var salvos: Dictionary = Settings.get_value("controls", "bindings")
	for acao in InputDefaults.ACTIONS:
		if not InputMap.has_action(acao):
			InputMap.add_action(acao, 0.3)
		InputMap.action_erase_events(acao)
		var eventos := InputDefaults.events_for(acao)
		if salvos.has(acao) and salvos[acao] is Array and InputDefaults.ACTIONS[acao]["remap"]:
			var teclado: Array[InputEvent] = []
			for d in salvos[acao]:
				var e := InputSerializer.from_dict(d)
				if e and InputDefaults.is_keyboard_mouse(e):
					teclado.append(e)
			if not teclado.is_empty():
				eventos = eventos.filter(func(x): return not InputDefaults.is_keyboard_mouse(x))
				eventos.append_array(teclado)
		for e in eventos:
			InputMap.action_add_event(acao, e)


## Atalhos de teclado/mouse atuais de uma ação.
func keyboard_events(acao: String) -> Array[InputEvent]:
	var out: Array[InputEvent] = []
	for e in InputMap.action_get_events(acao):
		if InputDefaults.is_keyboard_mouse(e):
			out.append(e)
	return out


## Troca o atalho de teclado/mouse de uma ação. Se outra ação usava o mesmo
## atalho, ela fica com o padrão dela (evita duas ações na mesma tecla).
## Retorna o nome da ação que perdeu o atalho ("" se nenhuma).
func remap(acao: String, evento: InputEvent) -> String:
	if not InputDefaults.ACTIONS.has(acao) or not InputDefaults.is_keyboard_mouse(evento):
		return ""
	var conflito := ""
	for outra in InputDefaults.ACTIONS:
		if outra != acao and InputDefaults.ACTIONS[outra]["remap"]:
			for e in keyboard_events(outra):
				if _mesmo(e, evento):
					conflito = outra
	var salvos: Dictionary = Settings.get_value("controls", "bindings")
	salvos[acao] = [InputSerializer.to_dict(evento)]
	if not conflito.is_empty():
		salvos.erase(conflito)
	Settings.set_value("controls", "bindings", salvos)
	_registrar_acoes()
	bindings_changed.emit()
	return conflito


func reset_bindings() -> void:
	Settings.set_value("controls", "bindings", {})
	_registrar_acoes()
	bindings_changed.emit()


func _mesmo(a: InputEvent, b: InputEvent) -> bool:
	return InputSerializer.to_dict(a) == InputSerializer.to_dict(b)


func _input(e: InputEvent) -> void:
	var novo := device
	if e is InputEventScreenTouch or e is InputEventScreenDrag:
		novo = "toque"
	elif e is InputEventJoypadButton or (e is InputEventJoypadMotion and absf((e as InputEventJoypadMotion).axis_value) > 0.4):
		novo = "controle"
	elif (e is InputEventKey or e is InputEventMouseButton) and not Settings.is_mobile:
		novo = "teclado_mouse"
	if novo != device:
		device = novo
		device_changed.emit(device)
