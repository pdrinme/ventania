class_name InputSerializer
extends RefCounted
## Converte eventos de entrada em dicionários JSON e de volta (para salvar remapeamentos).


static func to_dict(e: InputEvent) -> Dictionary:
	if e is InputEventKey:
		return {"t": "key", "code": int((e as InputEventKey).physical_keycode)}
	if e is InputEventMouseButton:
		return {"t": "mouse", "button": int((e as InputEventMouseButton).button_index)}
	if e is InputEventJoypadButton:
		return {"t": "joy", "button": int((e as InputEventJoypadButton).button_index)}
	if e is InputEventJoypadMotion:
		var m := e as InputEventJoypadMotion
		return {"t": "axis", "axis": int(m.axis), "value": signf(m.axis_value)}
	return {}


## Retorna null para dados inválidos.
static func from_dict(d: Variant) -> InputEvent:
	if not (d is Dictionary) or not d.has("t"):
		return null
	match d["t"]:
		"key":
			var code := int(d.get("code", 0))
			if code <= 0:
				return null
			var k := InputEventKey.new()
			k.physical_keycode = code as Key
			return k
		"mouse":
			var b := int(d.get("button", 0))
			if b < MOUSE_BUTTON_LEFT or b > MOUSE_BUTTON_XBUTTON2:
				return null
			var m := InputEventMouseButton.new()
			m.button_index = b as MouseButton
			return m
		"joy":
			var jb := InputEventJoypadButton.new()
			jb.button_index = int(d.get("button", 0)) as JoyButton
			return jb
		"axis":
			var jm := InputEventJoypadMotion.new()
			jm.axis = int(d.get("axis", 0)) as JoyAxis
			jm.axis_value = 1.0 if float(d.get("value", 1.0)) >= 0.0 else -1.0
			return jm
	return null


## Texto legível para a interface.
static func describe(e: InputEvent) -> String:
	if e is InputEventKey:
		var fisica := (e as InputEventKey).physical_keycode
		# sem tela (servidor/testes) não há layout de teclado para consultar
		if DisplayServer.get_name() == "headless":
			return OS.get_keycode_string(fisica)
		return OS.get_keycode_string(DisplayServer.keyboard_get_keycode_from_physical(fisica))
	if e is InputEventMouseButton:
		match (e as InputEventMouseButton).button_index:
			MOUSE_BUTTON_LEFT: return "Mouse esquerdo"
			MOUSE_BUTTON_RIGHT: return "Mouse direito"
			MOUSE_BUTTON_MIDDLE: return "Mouse do meio"
			MOUSE_BUTTON_WHEEL_UP: return "Roda para cima"
			MOUSE_BUTTON_WHEEL_DOWN: return "Roda para baixo"
			_: return "Mouse %d" % (e as InputEventMouseButton).button_index
	if e is InputEventJoypadButton:
		return "Controle botão %d" % (e as InputEventJoypadButton).button_index
	if e is InputEventJoypadMotion:
		return "Controle eixo %d" % (e as InputEventJoypadMotion).axis
	return "?"
