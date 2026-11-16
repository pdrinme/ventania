class_name BuildMode
extends Node
## Modo construção e edição (cliente). Só PEDE ao servidor (C_BUILD / C_EDIT);
## o servidor valida e a peça aparece quando chega o S_PIECE.
##  Construir (Q / B / botão Construir): prévia da peça na grade (azul = pode,
##  vermelho = não pode). 1–4 ou roda/LB-RB escolhem Parede, Piso, Rampa, Teto;
##  Recarregar troca o material; Atirar coloca (segurar = constrói em sequência).
##  Editar (G / ▼ / botão Editar) mirando numa peça sua: Atirar liga/desliga o
##  ladrilho na mira; Editar de novo confirma; Recarregar restaura; Esc cancela.

signal changed

var jogo                            # game.gd
var ativo := false
var escolha := 0                    # 0 parede, 1 piso, 2 rampa, 3 teto
var material := 0                   # 0 madeira, 1 pedra, 2 metal
var editando := -1
var mask_edicao := 0
var alvo := {}                      # slot atual da prévia
var alvo_ok := false
var motivo := ""                    # por que a prévia está vermelha
var enviados := 0                   # pedidos de construção (testes)
var _ultimo := {}
var _fantasma: MeshInstance3D
var _mat_ok: StandardMaterial3D
var _mat_ruim: StandardMaterial3D
var _malha_atual := ""
var _grade_edicao: MeshInstance3D
var _fogo_antes := false


func _ready() -> void:
	_mat_ok = _material(Color(0.35, 0.72, 1.0, 0.38))
	_mat_ruim = _material(Color(1.0, 0.3, 0.25, 0.38))
	_fantasma = MeshInstance3D.new()
	_fantasma.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fantasma.visible = false
	_fantasma.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	jogo.add_child(_fantasma)
	_grade_edicao = MeshInstance3D.new()
	_grade_edicao.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_grade_edicao.visible = false
	_grade_edicao.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	jogo.add_child(_grade_edicao)


static func _material(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = c
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	return m


func set_active(v: bool) -> void:
	if v == ativo:
		return
	ativo = v
	if not v:
		cancel_edit()
	_fantasma.visible = false
	_bloquear()
	changed.emit()


func _bloquear() -> void:
	jogo.sampler.modo_construcao = ativo or editando >= 0


func select_piece(i: int) -> void:
	escolha = posmod(i, 4)
	_ultimo = {}
	changed.emit()


func next_material() -> void:
	material = (material + 1) % 3
	changed.emit()


func materials() -> Array:
	return jogo._status.get("materials", [0, 0, 0])


func _unhandled_input(e: InputEvent) -> void:
	if jogo.pawn == null or jogo._morto or jogo.hud.is_paused() or jogo.inventario.is_open():
		return
	if e.is_action_pressed("build_mode"):
		set_active(not ativo)
		get_viewport().set_input_as_handled()
		return
	if e.is_action_pressed("edit_mode"):
		if editando >= 0:
			confirm_edit()
		else:
			start_edit()
		get_viewport().set_input_as_handled()
		return
	if editando >= 0:
		if e.is_action_pressed("fire"):
			toggle_tile()
			get_viewport().set_input_as_handled()
		elif e.is_action_pressed("reload"):
			mask_edicao = Grade.full_mask(jogo.build.estado.pecas[editando].tipo)
			_desenhar_edicao()
			get_viewport().set_input_as_handled()
		elif e.is_action_pressed("pause") or e.is_action_pressed("ui_cancel"):
			cancel_edit()
			get_viewport().set_input_as_handled()
		return
	if not ativo:
		return
	for i in 4:
		if e.is_action_pressed("slot_%d" % (i + 1)):
			select_piece(i)
			get_viewport().set_input_as_handled()
	if e.is_action_pressed("slot_next"):
		select_piece(escolha + 1)
		get_viewport().set_input_as_handled()
	elif e.is_action_pressed("slot_prev"):
		select_piece(escolha - 1)
		get_viewport().set_input_as_handled()
	elif e.is_action_pressed("reload"):
		next_material()
		get_viewport().set_input_as_handled()
	elif e.is_action_pressed("pickaxe"):
		set_active(false)


## Chamado a cada passo de física pelo jogo (depois do movimento previsto).
func physics_step(fogo: bool) -> void:
	if not ativo or editando >= 0 or jogo.pawn == null:
		_fogo_antes = fogo
		return
	_calcular_alvo()
	# segurar Atirar constrói em sequência: envia cada slot novo uma vez
	if fogo and alvo_ok and (not _fogo_antes or alvo != _ultimo):
		jogo.client.send_build(escolha, material, alvo["cell"], alvo["rot"])
		enviados += 1
		_ultimo = alvo.duplicate()
	if not fogo:
		_ultimo = {}
	elif not alvo_ok and not _fogo_antes and not motivo.is_empty():
		jogo.combat_hud.message(motivo, 1.2)
	_fogo_antes = fogo


func _calcular_alvo() -> void:
	var p: Pawn = jogo.pawn
	alvo = Grade.target(escolha, p.global_position, jogo.camera.yaw_rad(), jogo.camera.pitch_rad())
	var est: Construcoes = jogo.build.estado
	var cfg := Grade.config()
	motivo = ""
	if est.occupied(alvo["tipo"], alvo["cell"]):
		motivo = Inventory.MENSAGENS[Inventory.Err.OCCUPIED]
	elif int(materials()[material]) < int(cfg["custo"]):
		motivo = Inventory.MENSAGENS[Inventory.Err.NO_MATERIAL]
	else:
		var anc := Grade.anchored(alvo["tipo"], alvo["cell"], alvo["rot"], func(x, z): return jogo.mundo.ground_height(x, z))
		if not est.would_be_supported(alvo["tipo"], alvo["cell"], alvo["rot"], anc):
			motivo = Inventory.MENSAGENS[Inventory.Err.NO_SUPPORT]
	alvo_ok = motivo.is_empty()


func _process(_delta: float) -> void:
	if not ativo or editando >= 0 or alvo.is_empty() or jogo._morto:
		_fantasma.visible = false
		return
	var caminho := Grade.asset_path(alvo["tipo"], material)
	if caminho != _malha_atual:
		_malha_atual = caminho
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for m in Grade.kit(caminho)["malhas"]:
			st.append_from(m[0], 0, m[1])
		_fantasma.mesh = st.commit()
	_fantasma.transform = Grade.transform(alvo["tipo"], alvo["cell"], alvo["rot"])
	_fantasma.material_override = _mat_ok if alvo_ok else _mat_ruim
	# ocupado: não desenha por cima da peça existente
	_fantasma.visible = not jogo.build.estado.occupied(alvo["tipo"], alvo["cell"])


# ---------------- edição ----------------

## Peça na mira (raio da câmera até o alcance), ou -1.
func aimed_piece() -> Dictionary:
	var cam: Camera3D = jogo.camera.camera()
	var de := cam.global_position
	var dir := -cam.global_transform.basis.z
	var q := PhysicsRayQueryParameters3D.create(de, de + dir * (float(Grade.config()["alcance"]) + 4.0), Pawn.LAYER_WORLD)
	var r: Dictionary = jogo.pawn.get_world_3d().direct_space_state.intersect_ray(q)
	if r.is_empty():
		return {}
	var id := BuildClient.piece_of(r["collider"])
	return {"id": id, "pos": r["position"]} if id >= 0 else {}


func start_edit() -> void:
	var a := aimed_piece()
	if a.is_empty():
		jogo.combat_hud.message("Mire numa construção sua para editar.", 1.5)
		return
	var p: Construcoes.Peca = jogo.build.estado.pecas.get(a["id"])
	if p == null or p.dono != jogo.pawn.entity_id:
		jogo.combat_hud.message(Inventory.MENSAGENS[Inventory.Err.NOT_OWNER], 1.5)
		return
	if not Grade.editable(p.tipo):
		jogo.combat_hud.message("Só paredes e pisos podem ser editados.", 1.5)
		return
	editando = p.id
	mask_edicao = p.mask
	_bloquear()
	_desenhar_edicao()
	changed.emit()


## Liga/desliga o ladrilho na mira (intersecção do raio com o plano da peça).
func toggle_tile() -> void:
	var p: Construcoes.Peca = jogo.build.estado.pecas.get(editando)
	if p == null:
		cancel_edit()
		return
	var cam: Camera3D = jogo.camera.camera()
	var xf := Grade.transform(p.tipo, p.cell, p.rot)
	var normal := xf.basis.z if p.tipo != Grade.PISO else Vector3.UP
	var ponto_plano := xf.origin + (Vector3(0, 0.1, 0) if p.tipo == Grade.PISO else Vector3.ZERO)
	var plano := Plane(normal, ponto_plano)
	var hit: Variant = plano.intersects_ray(cam.global_position, -cam.global_transform.basis.z)
	if hit == null:
		return
	var t := Grade.tile_at(p.tipo, p.cell, p.rot, hit)
	if t < 0:
		return
	var nova := mask_edicao ^ (1 << t)
	if nova == 0:
		jogo.combat_hud.message("A peça precisa de pelo menos um ladrilho.", 1.2)
		return
	mask_edicao = nova
	Audio.play_sfx("inv_mover", -6.0)
	_desenhar_edicao()


func toggle_tile_index(t: int) -> void:
	var nova := mask_edicao ^ (1 << t)
	if nova != 0:
		mask_edicao = nova
		_desenhar_edicao()


func confirm_edit() -> void:
	if editando >= 0:
		var p: Construcoes.Peca = jogo.build.estado.pecas.get(editando)
		if p and mask_edicao != p.mask:
			jogo.client.send_edit(editando, mask_edicao)
	cancel_edit()


func cancel_edit() -> void:
	editando = -1
	_grade_edicao.visible = false
	_bloquear()
	changed.emit()


## Grade de edição: ladrilhos mantidos em azul, removidos em vermelho claro.
func _desenhar_edicao() -> void:
	var p: Construcoes.Peca = jogo.build.estado.pecas.get(editando)
	if p == null:
		return
	var im := ImmediateMesh.new()
	var todas := Grade.tile_boxes(p.tipo, Grade.full_mask(p.tipo))
	var mantidas := Grade.tile_boxes(p.tipo, mask_edicao)
	for t in todas:
		var fica := mantidas.any(func(m): return m[0] == t[0])
		im.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _mat_ok if fica else _mat_ruim)
		var c: Vector3 = t[0]
		var s: Vector3 = (t[1] as Vector3) * 0.5 * 0.92 + Vector3(0.0, 0.0, 0.02) * (0.0 if p.tipo == Grade.PISO else 1.0)
		if p.tipo == Grade.PISO:
			s.y = 0.13
		_caixa(im, c, s)
		im.surface_end()
	_grade_edicao.mesh = im
	_grade_edicao.transform = Grade.transform(p.tipo, p.cell, p.rot)
	_grade_edicao.visible = true


static func _caixa(im: ImmediateMesh, c: Vector3, s: Vector3) -> void:
	var v := [Vector3(-1, -1, -1), Vector3(1, -1, -1), Vector3(1, 1, -1), Vector3(-1, 1, -1),
			Vector3(-1, -1, 1), Vector3(1, -1, 1), Vector3(1, 1, 1), Vector3(-1, 1, 1)]
	for f in [[0, 1, 2, 3], [5, 4, 7, 6], [4, 0, 3, 7], [1, 5, 6, 2], [3, 2, 6, 7], [4, 5, 1, 0]]:
		for k in [0, 1, 2, 0, 2, 3]:
			im.surface_add_vertex(c + (v[f[k]] as Vector3) * s)
