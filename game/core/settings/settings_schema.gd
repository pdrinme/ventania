class_name SettingsSchema
extends RefCounted
## Definição de todas as configurações: tipo, padrão, limites, opções.
## Fonte única usada pelo armazenamento, pela validação e pela tela de opções.

## tipo: "float" (min, max, step), "int_enum"/"str_enum" (options), "bool", "string", "dict"
const SPEC := {
	"graphics": {
		"profile": {"type": "str_enum", "options": ["performance", "balanced", "quality", "custom"], "default": "balanced"},
		"render_scale": {"type": "float", "min": 0.5, "max": 1.0, "step": 0.05, "default": 0.85},
		"msaa": {"type": "int_enum", "options": [0, 2, 4], "default": 0},
		"shadows": {"type": "str_enum", "options": ["off", "low", "high"], "default": "low"},
		"view_distance": {"type": "float", "min": 60.0, "max": 800.0, "step": 10.0, "default": 250.0},
		"fps_limit": {"type": "int_enum", "options": [30, 60, 90, 120, 0], "default": 60},
		"vsync": {"type": "bool", "default": true},
		"window_mode": {"type": "str_enum", "options": ["windowed", "fullscreen"], "default": "windowed", "pc_only": true},
		"show_fps": {"type": "bool", "default": false},
	},
	"audio": {
		"master": {"type": "float", "min": 0.0, "max": 1.0, "step": 0.05, "default": 0.8},
		"music": {"type": "float", "min": 0.0, "max": 1.0, "step": 0.05, "default": 0.7},
		"sfx": {"type": "float", "min": 0.0, "max": 1.0, "step": 0.05, "default": 0.8},
		"ui": {"type": "float", "min": 0.0, "max": 1.0, "step": 0.05, "default": 0.7},
	},
	"controls": {
		"mouse_sensitivity": {"type": "float", "min": 0.1, "max": 5.0, "step": 0.05, "default": 1.0, "pc_only": true},
		"gamepad_sensitivity": {"type": "float", "min": 0.1, "max": 5.0, "step": 0.05, "default": 1.0, "pc_only": true},
		"touch_sensitivity": {"type": "float", "min": 0.1, "max": 5.0, "step": 0.05, "default": 1.0, "mobile_only": true},
		"invert_y": {"type": "bool", "default": false},
		"bindings": {"type": "dict", "default": {}},
	},
	"interface": {
		"ui_scale": {"type": "float", "min": 0.75, "max": 1.5, "step": 0.05, "default": 1.0},
	},
	"network": {
		"server_url": {"type": "string", "default": "http://127.0.0.1:8080", "max_len": 200},
	},
}

## Rótulos em português para a interface.
const LABELS := {
	"profile": "Perfil gráfico", "render_scale": "Resolução 3D", "msaa": "Antisserrilhado (MSAA)",
	"shadows": "Sombras", "view_distance": "Distância de visão", "fps_limit": "Limite de FPS",
	"vsync": "Sincronização vertical", "window_mode": "Modo de janela", "show_fps": "Mostrar FPS",
	"master": "Volume geral", "music": "Música", "sfx": "Efeitos", "ui": "Interface",
	"mouse_sensitivity": "Sensibilidade do mouse", "gamepad_sensitivity": "Sensibilidade do controle",
	"touch_sensitivity": "Sensibilidade do toque", "invert_y": "Inverter eixo vertical",
	"ui_scale": "Escala da interface",
	"server_url": "Endereço do servidor",
	"performance": "Desempenho", "balanced": "Equilibrado", "quality": "Qualidade", "custom": "Personalizado",
	"off": "Desligadas", "low": "Baixas", "high": "Altas", "windowed": "Janela", "fullscreen": "Tela cheia",
}


static func label(key: Variant) -> String:
	return LABELS.get(str(key), str(key))


static func has(section: String, key: String) -> bool:
	return SPEC.has(section) and SPEC[section].has(key)


static func default_value(section: String, key: String) -> Variant:
	var d: Variant = SPEC[section][key]["default"]
	return d.duplicate(true) if d is Dictionary else d


## Retorna o valor corrigido (tipo e limites) ou o padrão se for inválido.
static func sanitize(section: String, key: String, value: Variant) -> Variant:
	if not has(section, key):
		return null
	var s: Dictionary = SPEC[section][key]
	match s["type"]:
		"float":
			if not (value is float or value is int):
				return s["default"]
			return clampf(snappedf(float(value), s["step"]), s["min"], s["max"])
		"int_enum":
			if (value is float or value is int) and int(value) in s["options"]:
				return int(value)
			return s["default"]
		"str_enum":
			return value if (value is String and value in s["options"]) else s["default"]
		"bool":
			return value if value is bool else s["default"]
		"string":
			return value.strip_edges().substr(0, s["max_len"]) if value is String else s["default"]
		"dict":
			return value.duplicate(true) if value is Dictionary else {}
	return s["default"]
