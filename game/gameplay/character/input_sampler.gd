class_name InputSampler
extends Node
## Junta teclado/mouse, controle e toque em um InputCmd por tick de física.
## Pulos apertados entre dois ticks não se perdem (ficam guardados até o próximo).

var touch_move := Vector2.ZERO     # joystick virtual (x direita, y frente)
var touch_crouch := false          # botão de agachar (alterna)
var touch_jump := false
var touch_fire := false            # botão Atirar segurado
var touch_reload := false          # pedido de recarga (um passo)
var touch_interact := false        # botão Interagir segurado
var morto := false                 # eliminado: não envia ações
var selected := 0                  # espaço atual (vem do servidor); Inventory.PICKAXE = picareta
var _slot_pendente := 0            # 1..5; Protocol.SLOT_PICKAXE = picareta
var bloqueado := false             # pausa
var inventario_aberto := false     # tela de inventário: anda, mas não atira/mira/recarrega
var modo_construcao := false       # construção/edição: Atirar/Recarregar/1-5 são do BuildMode
var _pulo_pendente := false
var _agachar_alterna := false      # controle: R3 alterna agachar
var _agachar_segurado := false     # teclado/mouse: segurar agacha


func _unhandled_input(e: InputEvent) -> void:
	if bloqueado:
		return
	if e.is_action_pressed("jump"):
		_pulo_pendente = true
	if inventario_aberto or modo_construcao:
		return
	for i in 5:
		if e.is_action_pressed("slot_%d" % (i + 1)):
			select_slot(i)
	if e.is_action_pressed("pickaxe"):
		select_slot(Inventory.PICKAXE)
	# roda do mouse / LB-RB: picareta -> 1 -> 2 -> ... -> 5 -> picareta
	if e.is_action_pressed("slot_next"):
		select_slot(next_in_cycle(selected, 1))
	elif e.is_action_pressed("slot_prev"):
		select_slot(next_in_cycle(selected, -1))
	if e.is_action("crouch"):
		if e is InputEventJoypadButton:
			if e.is_pressed():
				_agachar_alterna = not _agachar_alterna
		elif InputDefaults.is_keyboard_mouse(e) and not e.is_echo():
			_agachar_segurado = e.is_pressed()


func request_jump() -> void:
	_pulo_pendente = true


## Ordem da barra: picareta, 1, 2, 3, 4, 5 (com volta).
static func next_in_cycle(atual: int, passo: int) -> int:
	var pos := (atual + 1 + passo + 6) % 6       # picareta = posição 0
	return pos - 1


## i: 0..4 ou Inventory.PICKAXE
func select_slot(i: int) -> void:
	if i == Inventory.PICKAXE:
		_slot_pendente = Protocol.SLOT_PICKAXE
		selected = Inventory.PICKAXE
		return
	_slot_pendente = clampi(i, 0, 4) + 1
	selected = _slot_pendente - 1


func make_cmd(seq: int, yaw: float, pitch: float) -> Protocol.InputCmd:
	var c := Protocol.InputCmd.new()
	c.seq = seq
	c.yaw = yaw
	c.pitch = pitch
	if bloqueado or morto:
		_pulo_pendente = false
		_agachar_segurado = false
		touch_reload = false
		return c
	c.slot = _slot_pendente
	_slot_pendente = 0
	if inventario_aberto:
		touch_reload = false
		c.move = Input.get_vector("move_left", "move_right", "move_back", "move_forward").limit_length(1.0)
		return c
	# construção: anda, pula e corre normalmente; Atirar/Mirar/Recarregar ficam com o BuildMode
	if not modo_construcao:
		if Input.is_action_pressed("fire") or touch_fire:
			c.buttons |= Protocol.BTN_FIRE
		if Input.is_action_pressed("aim"):
			c.buttons |= Protocol.BTN_AIM
		if Input.is_action_pressed("reload") or touch_reload:
			c.buttons |= Protocol.BTN_RELOAD
	touch_reload = false
	if Input.is_action_pressed("interact") or touch_interact:
		c.buttons |= Protocol.BTN_INTERACT
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
