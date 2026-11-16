class_name InputDefaults
extends RefCounted
## Ações do jogo e atalhos padrão (teclado/mouse e controle).
## Ações "remapeáveis" aparecem na tela de controles.

## ação -> {label, keys (Key), mouse (MouseButton), joy (JoyButton), axis [JoyAxis, sinal], remap}
const ACTIONS := {
	"move_forward": {"label": "Andar para frente", "keys": [KEY_W], "axis": [[JOY_AXIS_LEFT_Y, -1.0]], "remap": true},
	"move_back": {"label": "Andar para trás", "keys": [KEY_S], "axis": [[JOY_AXIS_LEFT_Y, 1.0]], "remap": true},
	"move_left": {"label": "Andar para a esquerda", "keys": [KEY_A], "axis": [[JOY_AXIS_LEFT_X, -1.0]], "remap": true},
	"move_right": {"label": "Andar para a direita", "keys": [KEY_D], "axis": [[JOY_AXIS_LEFT_X, 1.0]], "remap": true},
	"look_up": {"label": "Olhar para cima", "axis": [[JOY_AXIS_RIGHT_Y, -1.0]], "remap": false},
	"look_down": {"label": "Olhar para baixo", "axis": [[JOY_AXIS_RIGHT_Y, 1.0]], "remap": false},
	"look_left": {"label": "Olhar para a esquerda", "axis": [[JOY_AXIS_RIGHT_X, -1.0]], "remap": false},
	"look_right": {"label": "Olhar para a direita", "axis": [[JOY_AXIS_RIGHT_X, 1.0]], "remap": false},
	"jump": {"label": "Pular", "keys": [KEY_SPACE], "joy": [JOY_BUTTON_A], "remap": true},
	"sprint": {"label": "Correr", "keys": [KEY_SHIFT], "joy": [JOY_BUTTON_LEFT_STICK], "remap": true},
	"crouch": {"label": "Agachar", "keys": [KEY_CTRL], "joy": [JOY_BUTTON_RIGHT_STICK], "remap": true},
	"fire": {"label": "Atirar / usar", "mouse": [MOUSE_BUTTON_LEFT], "axis": [[JOY_AXIS_TRIGGER_RIGHT, 1.0]], "remap": true},
	"aim": {"label": "Mirar", "mouse": [MOUSE_BUTTON_RIGHT], "axis": [[JOY_AXIS_TRIGGER_LEFT, 1.0]], "remap": true},
	"reload": {"label": "Recarregar", "keys": [KEY_R], "joy": [JOY_BUTTON_X], "remap": true},
	"interact": {"label": "Interagir", "keys": [KEY_E], "joy": [JOY_BUTTON_Y], "remap": true},
	"build_mode": {"label": "Modo construção", "keys": [KEY_Q], "joy": [JOY_BUTTON_B], "remap": true},
	"edit_mode": {"label": "Modo edição", "keys": [KEY_G], "joy": [JOY_BUTTON_DPAD_DOWN], "remap": true},
	"slot_next": {"label": "Próximo item", "mouse": [MOUSE_BUTTON_WHEEL_DOWN], "joy": [JOY_BUTTON_RIGHT_SHOULDER], "remap": false},
	"slot_prev": {"label": "Item anterior", "mouse": [MOUSE_BUTTON_WHEEL_UP], "joy": [JOY_BUTTON_LEFT_SHOULDER], "remap": false},
	"pickaxe": {"label": "Picareta", "keys": [KEY_F], "joy": [JOY_BUTTON_DPAD_RIGHT], "remap": true},
	"slot_1": {"label": "Item 1", "keys": [KEY_1], "remap": true},
	"slot_2": {"label": "Item 2", "keys": [KEY_2], "remap": true},
	"slot_3": {"label": "Item 3", "keys": [KEY_3], "remap": true},
	"slot_4": {"label": "Item 4", "keys": [KEY_4], "remap": true},
	"slot_5": {"label": "Item 5", "keys": [KEY_5], "remap": true},
	"inventory": {"label": "Inventário", "keys": [KEY_TAB], "joy": [JOY_BUTTON_BACK], "remap": true},
	"map": {"label": "Mapa", "keys": [KEY_M], "joy": [JOY_BUTTON_DPAD_UP], "remap": true},
	"emote": {"label": "Emote", "keys": [KEY_B], "joy": [JOY_BUTTON_DPAD_LEFT], "remap": true},
	"pause": {"label": "Pausar / menu", "keys": [KEY_ESCAPE], "joy": [JOY_BUTTON_START], "remap": false},
}


## Eventos padrão de uma ação (novos objetos a cada chamada).
static func events_for(action: String) -> Array[InputEvent]:
	var out: Array[InputEvent] = []
	var a: Dictionary = ACTIONS[action]
	for k in a.get("keys", []):
		var e := InputEventKey.new()
		e.physical_keycode = k
		out.append(e)
	for b in a.get("mouse", []):
		var m := InputEventMouseButton.new()
		m.button_index = b
		out.append(m)
	for j in a.get("joy", []):
		var jb := InputEventJoypadButton.new()
		jb.button_index = j
		out.append(jb)
	for ax in a.get("axis", []):
		var jm := InputEventJoypadMotion.new()
		jm.axis = ax[0]
		jm.axis_value = ax[1]
		out.append(jm)
	return out


static func is_keyboard_mouse(e: InputEvent) -> bool:
	return e is InputEventKey or e is InputEventMouseButton
