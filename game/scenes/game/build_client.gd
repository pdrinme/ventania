class_name BuildClient
extends Node3D
## Construções no cliente: cópia do estado do servidor (Construcoes), colisão
## (para a predição do movimento e a mira) e visual.
## Visual: peças inteiras em MultiMesh dinâmico por (malha, região de 64 m) com
## dados por instância (x = dano 0..1 → rachaduras no shader; y = obra 0..1 →
## tom de "em construção"); peças editadas desenhadas pelos ladrilhos.

signal piece_destroyed(pos: Vector3, material: int, motivo: int)

const REGIAO := 64.0
const CORES := [Color("b8773d"), Color("8f8a80"), Color("6c7d8c")]

class Grupo:
	var mmi: MultiMeshInstance3D
	var ids: Array = []
	var xforms: Array = []
	var sujo := true

var estado := Construcoes.new()
var mundo: Mapa
var _corpos := {}                   # id -> StaticBody3D
var _grupos := {}                   # chave -> Grupo
var _onde := {}                     # id -> [[chave, índice da malha], ...]
var _editadas := {}                 # id -> MeshInstance3D
var _mat_tiles: Array = []
var com_visual := true


func setup(m: Mapa) -> void:
	mundo = m
	for c in CORES:
		var mt := StandardMaterial3D.new()
		mt.albedo_color = c
		mt.roughness = 1.0
		_mat_tiles.append(mt)
	_mapa()


func _altura() -> Callable:
	return func(x: float, z: float) -> float: return mundo.ground_height(x, z)


func _mapa() -> void:
	var lista := mundo.building_pieces()
	for i in lista.size():
		var d: Dictionary = lista[i]
		var p := Construcoes.Peca.new()
		p.id = i + 1
		p.tipo = d["tipo"]
		p.cell = d["cell"]
		p.rot = d["rot"]
		p.material = d["material"]
		p.hp_max = Construcoes.max_hp(p.material)
		p.hp = p.hp_max
		p.mask = Grade.full_mask(p.tipo)
		p.ancorada = Grade.anchored(p.tipo, p.cell, p.rot, _altura())
		_adicionar(p)


func _adicionar(p: Construcoes.Peca) -> void:
	estado.add(p)
	var corpo := BuildServer.make_body(p)
	add_child(corpo)
	_corpos[p.id] = corpo
	if com_visual:
		_visual(p)


func _visual(p: Construcoes.Peca) -> void:
	var xf := Grade.transform(p.tipo, p.cell, p.rot)
	if p.edited():
		var mi := MeshInstance3D.new()
		mi.mesh = _malha_ladrilhos(p)
		mi.transform = xf
		mi.material_override = _mat_tiles[p.material]
		mi.visibility_range_end = 320.0
		add_child(mi)
		_editadas[p.id] = mi
		return
	var malhas: Array = Grade.kit(Grade.asset_path(p.tipo, p.material))["malhas"]
	var lugares := []
	for i in malhas.size():
		var chave := "%s|%d|%d|%d" % [Grade.asset_path(p.tipo, p.material), i, floori(xf.origin.x / REGIAO), floori(xf.origin.z / REGIAO)]
		var g: Grupo = _grupos.get(chave)
		if g == null:
			g = Grupo.new()
			g.mmi = MultiMeshInstance3D.new()
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_custom_data = true
			mm.mesh = malhas[i][0]
			g.mmi.multimesh = mm
			g.mmi.visibility_range_end = 320.0
			add_child(g.mmi)
			_grupos[chave] = g
		g.ids.append(p.id)
		g.xforms.append(xf * malhas[i][1])
		g.sujo = true
		lugares.append(chave)
	_onde[p.id] = lugares


func _tirar_visual(id: int) -> void:
	if _editadas.has(id):
		(_editadas[id] as Node).queue_free()
		_editadas.erase(id)
	for chave in _onde.get(id, []):
		var g: Grupo = _grupos[chave]
		var k := g.ids.find(id)
		if k >= 0:
			g.ids.remove_at(k)
			g.xforms.remove_at(k)
			g.sujo = true
	_onde.erase(id)


static func _malha_ladrilhos(p: Construcoes.Peca) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for t in Grade.tile_boxes(p.tipo, p.mask):
		var bx := BoxMesh.new()
		bx.size = (t[1] as Vector3) - Vector3(0.04, 0.0, 0.0) if p.tipo != Grade.PISO else (t[1] as Vector3) - Vector3(0.04, 0, 0.04)
		st.append_from(bx, 0, Transform3D(Basis(), t[0]))
	st.generate_normals()
	return st.commit()


## Dados por instância: dano (rachaduras) e obra.
func _custom(p: Construcoes.Peca) -> Color:
	return Color(p.damage_frac(), p.obra, 0.0, 0.0)


func _process(_delta: float) -> void:
	for g: Grupo in _grupos.values():
		if not g.sujo:
			continue
		g.sujo = false
		var mm := g.mmi.multimesh
		mm.instance_count = g.ids.size()
		for i in g.ids.size():
			mm.set_instance_transform(i, g.xforms[i])
			var p: Construcoes.Peca = estado.pecas.get(g.ids[i])
			mm.set_instance_custom_data(i, _custom(p) if p else Color())


func _atualizar_custom(p: Construcoes.Peca) -> void:
	for chave in _onde.get(p.id, []):
		var g: Grupo = _grupos[chave]
		if g.sujo:
			continue
		var k := g.ids.find(p.id)
		if k >= 0:
			g.mmi.multimesh.set_instance_custom_data(k, _custom(p))


# ---------------- mensagens do servidor ----------------

func on_piece(d: Dictionary) -> void:
	var antiga: Construcoes.Peca = estado.pecas.get(d["id"])
	if antiga:
		var mudou_forma: bool = antiga.mask != d["mask"]
		antiga.hp = d["hp"]
		antiga.hp_max = d["hp_max"]
		antiga.obra = d["obra"]
		if mudou_forma:
			antiga.mask = d["mask"]
			(_corpos[antiga.id] as Node).free()
			var corpo := BuildServer.make_body(antiga)
			add_child(corpo)
			_corpos[antiga.id] = corpo
			_tirar_visual(antiga.id)
			if com_visual:
				_visual(antiga)
		else:
			_atualizar_custom(antiga)
		return
	var p := Construcoes.Peca.new()
	p.id = d["id"]
	p.tipo = d["tipo"]
	p.cell = d["cell"]
	p.rot = d["rot"]
	p.material = d["material"]
	p.dono = d["dono"]
	p.hp = d["hp"]
	p.hp_max = d["hp_max"]
	p.obra = d["obra"]
	p.mask = d["mask"]
	p.ancorada = Grade.anchored(p.tipo, p.cell, p.rot, _altura())
	if estado.occupied(p.tipo, p.cell):
		on_gone(estado.por_slot[Grade.key(p.tipo, p.cell)], -1)
	_adicionar(p)


func on_gone(id: int, motivo: int) -> void:
	var p := estado.remove(id)
	if p == null:
		return
	if _corpos.has(id):
		(_corpos[id] as Node).queue_free()
		_corpos.erase(id)
	_tirar_visual(id)
	if motivo >= 0:
		piece_destroyed.emit(Grade.center(p.tipo, p.cell), p.material, motivo)


func on_hp(lista: Array) -> void:
	for e in lista:
		var p: Construcoes.Peca = estado.pecas.get(e[0])
		if p:
			p.hp = e[1]
			p.obra = e[2]
			_atualizar_custom(p)


func on_reset() -> void:
	for id in estado.pecas.keys():
		on_gone(id, -1)
	estado = Construcoes.new()
	_mapa()


## Peça sob um ponto de colisão (mira): id ou -1.
static func piece_of(collider: Object) -> int:
	if collider is Node and (collider as Node).has_meta("peca_id"):
		return int((collider as Node).get_meta("peca_id"))
	return -1


## Chamadas de desenho das construções (diagnóstico).
func visual_groups() -> int:
	return _grupos.values().filter(func(g): return not g.ids.is_empty()).size() + _editadas.size()
