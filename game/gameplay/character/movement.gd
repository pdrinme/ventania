class_name Movement
extends RefCounted
## Física de movimento do personagem. Usada IGUAL no servidor (autoridade) e no
## cliente (predição). Nunca leia Input aqui: tudo vem do InputCmd.

const WALK_SPEED := 4.5
const SPRINT_SPEED := 6.5
const CROUCH_SPEED := 2.5
const GRAVITY := 22.0
const JUMP_HEIGHT := 1.4
const JUMP_VELOCITY := 7.4             # ~1,4 m de altura com integração a 30 Hz (medido em teste)
const STICK_VELOCITY := -1.5           # no chão: empurra levemente para baixo para manter contato
const SNAP_DIST := 0.45                # "grudar" no chão ao descer degraus/rampas
const GROUND_ACCEL := 45.0             # m/s² até a velocidade alvo
const AIR_ACCEL := 9.0
const MAX_FALL_SPEED := 45.0
const SPRINT_MIN_FORWARD := 0.5        # só corre andando para a frente


# queda depois de saltar do ônibus
const QUEDA_TERMINAL := 26.0           # m/s (queda livre)
const QUEDA_HORIZONTAL := 10.0         # m/s de controle na queda livre
const PLANADOR_DESCIDA := 6.5          # m/s descendo com o planador aberto
const PLANADOR_HORIZONTAL := 12.0
const PLANADOR_ALTURA := 38.0          # abre sozinho abaixo desta altura sobre o chão
const QUEDA_ACCEL := 12.0


## Simula um passo. Modifica pawn.velocity, posição (move_and_slide) e agachamento.
static func step(pawn: Pawn, cmd: Protocol.InputCmd, dt: float) -> void:
	pawn.yaw = cmd.yaw
	if pawn.queda == Pawn.NO_ONIBUS:
		return                              # a posição vem do ônibus (servidor)
	if pawn.queda != 0:
		_queda(pawn, cmd, dt)
		return
	# agachar / levantar (levantar só se houver espaço acima)
	var quer_agachar := cmd.has(Protocol.BTN_CROUCH)
	if quer_agachar and not pawn.crouched:
		pawn.set_crouched(true)
	elif not quer_agachar and pawn.crouched and pawn.can_stand():
		pawn.set_crouched(false)

	var no_chao := pawn.grounded
	pawn.sprinting = cmd.has(Protocol.BTN_SPRINT) and not pawn.crouched and cmd.move.y >= SPRINT_MIN_FORWARD
	var velocidade := CROUCH_SPEED if pawn.crouched else (SPRINT_SPEED if pawn.sprinting else WALK_SPEED)

	var mov := cmd.move.limit_length(1.0)
	var dir := Basis(Vector3.UP, cmd.yaw) * Vector3(mov.x, 0.0, -mov.y)
	var alvo := dir * velocidade
	var horizontal := Vector3(pawn.velocity.x, 0.0, pawn.velocity.z)
	horizontal = horizontal.move_toward(alvo, (GROUND_ACCEL if no_chao else AIR_ACCEL) * dt)

	var vy := pawn.velocity.y
	var pulou := false
	if no_chao:
		vy = STICK_VELOCITY
		if cmd.has(Protocol.BTN_JUMP) and not pawn.crouched:
			vy = JUMP_VELOCITY
			pulou = true
	else:
		vy = maxf(vy - GRAVITY * dt, -MAX_FALL_SPEED)

	pawn.velocity = Vector3(horizontal.x, vy, horizontal.z)
	pawn.move_and_slide()
	var no_chao_agora := pawn.is_on_floor()
	# "Grudar" manual: o snap nativo depende de estado interno do CharacterBody3D que
	# não viaja pela rede e quebra a predição. Este depende só de `grounded`.
	if no_chao and not no_chao_agora and not pulou:
		var col := KinematicCollision3D.new()
		if pawn.test_move(pawn.global_transform, Vector3(0, -SNAP_DIST, 0), col) \
				and col.get_normal().angle_to(Vector3.UP) <= pawn.floor_max_angle:
			pawn.global_position += col.get_travel()
			no_chao_agora = true
	if no_chao_agora and pawn.velocity.y < 0.0:
		pawn.velocity.y = 0.0
	pawn.grounded = no_chao_agora



## Queda livre (rápida, pouco controle) e planador (abre sozinho perto do chão:
## desce devagar e anda mais). Ao tocar o chão volta ao movimento normal.
static func _queda(pawn: Pawn, cmd: Protocol.InputCmd, dt: float) -> void:
	if pawn.queda == Pawn.QUEDA_LIVRE:
		var q := PhysicsRayQueryParameters3D.create(pawn.global_position, pawn.global_position + Vector3(0, -PLANADOR_ALTURA, 0), Pawn.LAYER_WORLD)
		if not pawn.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
			pawn.queda = Pawn.PLANADOR
	var planando := pawn.queda == Pawn.PLANADOR
	var mov := cmd.move.limit_length(1.0)
	var alvo := Basis(Vector3.UP, cmd.yaw) * Vector3(mov.x, 0.0, -mov.y) * (PLANADOR_HORIZONTAL if planando else QUEDA_HORIZONTAL)
	var horizontal := Vector3(pawn.velocity.x, 0.0, pawn.velocity.z).move_toward(alvo, QUEDA_ACCEL * dt)
	var vy := pawn.velocity.y
	if planando:
		vy = move_toward(vy, -PLANADOR_DESCIDA, GRAVITY * dt)
	else:
		vy = maxf(vy - GRAVITY * dt, -QUEDA_TERMINAL)
	pawn.velocity = Vector3(horizontal.x, vy, horizontal.z)
	pawn.move_and_slide()
	if pawn.is_on_floor():
		pawn.queda = 0
		pawn.grounded = true
		pawn.velocity.y = 0.0
	else:
		pawn.grounded = false
