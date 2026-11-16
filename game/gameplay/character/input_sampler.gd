class_name InputSampler
extends Node
## Junta teclado/mouse, controle e toque em um InputCmd por tick de física.
## Pulos apertados entre dois ticks não se perdem (ficam guardados até o próximo).

var touch_move := Vector2.ZERO     # joystick virtual (x direita, y frente)
var touch_crouch := false          # botão de agachar (alterna)
var touch_jump := false
var bloqueado := false             # pausa
var _pulo_pendente := false
var _agachar_alterna := false      # controle: R3 alterna agachar
var _agachar_segurado := false     # teclado/mouse: segurar agacha


func _unhandled_input(e: InputEvent) -> void:
	if bloqueado:
		return
	if e.is_action_pressed("jump"):
		_pulo_pendente = true
	if e.is_action("crouch"):
		if e is InputEventJoypadButton:
			if e.is_pressed():
				_agachar_alterna = not _agachar_alterna
		elif InputDefaults.is_keyboard_mouse(e) and not e.is_echo():
			_agachar_segurado = e.is_pressed()


func request_jump() -> void:
	_pulo_pendente = true


func make_cmd(seq: int, yaw: float, pitch: float) -> Protocol.InputCmd:
	var c := Protocol.InputCmd.new()
	c.seq = seq
	c.yaw = yaw
	c.pitch = pitch
	if bloqueado:
		_pulo_pendente = false
		_agachar_segurado = false
		return c
	var mov := Input.get_vector("move_left", "move_right", "move_back", "move_forward")
	if touch_move.length() > mov.length():
		mov = touch_move
	c.move = mov.limit_length(1.0)
	if _pulo_pendente or touch_jump:
		c.buttons |= Protocol.BTN_JUMP
	_pulo_pendente = false
	touch_jump = false
	# toque: empurrar o joystick até a borda corre automaticamente
	var correr := Input.is_action_pressed("sprint") or touch_move.length() > 0.92
	if correr:
		c.buttons |= Protocol.BTN_SPRINT
	if _agachar_segurado or _agachar_alterna or touch_crouch:
		c.buttons |= Protocol.BTN_CROUCH
	return c
