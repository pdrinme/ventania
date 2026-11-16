class_name Grade
extends RefCounted
## Grade de construção (Etapa 5): 4 m, alinhada ao mundo (célula (cx, cy, cz)
## ocupa [cx*4, cx*4+4) em x, idem y e z). Tudo aqui é matemática pura,
## compartilhada pelo servidor (decide) e pelo cliente (prévia e visual).
##
## Espaços ("slots") — um por posição, chave Vector4i(tipo, cx, cy, cz):
##  PAREDE_X: plano z = cz*4, de x = cx*4 a cx*4+4 (rot 0 ou 2)
##  PAREDE_Z: plano x = cx*4, de z = cz*4 a cz*4+4 (rot 1 ou 3)
##  PISO, TETO: plano y = cy*4 da célula (o teto é a pirâmide que sobe dali)
##  RAMPA: volume da célula, subindo na direção de rot (0 -Z, 1 -X, 2 +Z, 3 +X)
## Conexões: duas peças se apoiam se compartilham uma ARESTA da grade. Uma peça
## está ancorada se a parte de baixo toca o chão (terreno na altura da base ou acima).

enum { PAREDE_X, PAREDE_Z, PISO, RAMPA, TETO }
const TIPOS := ["parede", "piso", "rampa", "teto"]          # escolha do jogador (rede: 0..3)
const MATERIAIS := ["madeira", "pedra", "metal"]
const ARQUIVO := "res://data/construcao.json"
const T := 4.0

static var _cfg := {}
static var _kit := {}                 # caminho -> {"malhas": [[Mesh, Transform3D]], "formas": [[Shape3D, Transform3D]]}


static func config() -> Dictionary:
	if _cfg.is_empty():
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(ARQUIVO))
		_cfg = d if d is Dictionary else {}
	return _cfg


## Tipo de slot a partir da escolha do jogador (0..3) e da rotação.
static func slot_type(escolha: int, rot: int) -> int:
	match escolha:
		0:
			return PAREDE_X if rot % 2 == 0 else PAREDE_Z
		1:
			return PISO
		2:
			return RAMPA
	return TETO


static func choice_of(tipo_slot: int) -> int:
	match tipo_slot:
		PAREDE_X, PAREDE_Z:
			return 0
		PISO:
			return 1
		RAMPA:
			return 2
	return 3


static func key(tipo_slot: int, cell: Vector3i) -> Vector4i:
	return Vector4i(tipo_slot, cell.x, cell.y, cell.z)


static func asset_path(tipo_slot: int, material: int) -> String:
	return "res://assets/construcoes/%s_%s.glb" % [TIPOS[choice_of(tipo_slot)], MATERIAIS[clampi(material, 0, 2)]]


## Transformação do asset do kit para o slot (a origem dos assets segue os padrões
## da grade: piso com topo a 0,10; parede centrada no plano; rampa de topo a topo).
static func transform(tipo_slot: int, cell: Vector3i, rot: int) -> Transform3D:
	var x := cell.x * T
	var y := cell.y * T
	var z := cell.z * T
	match tipo_slot:
		PAREDE_X:
			return Transform3D(Basis(Vector3.UP, PI if rot == 2 else 0.0), Vector3(x + 2.0, y, z))
		PAREDE_Z:
			return Transform3D(Basis(Vector3.UP, deg_to_rad(90.0 if rot == 1 else -90.0)), Vector3(x, y, z + 2.0))
		RAMPA:
			return Transform3D(Basis(Vector3.UP, rot * PI * 0.5), Vector3(x + 2.0, y, z + 2.0))
	return Transform3D(Basis(Vector3.UP, (rot % 4) * PI * 0.5), Vector3(x + 2.0, y, z + 2.0))


## Centro aproximado da peça (alcance e efeitos).
static func center(tipo_slot: int, cell: Vector3i) -> Vector3:
	var b := Vector3(cell) * T
	match tipo_slot:
		PAREDE_X:
			return b + Vector3(2, 2, 0)
		PAREDE_Z:
			return b + Vector3(0, 2, 2)
		RAMPA:
			return b + Vector3(2, 2, 2)
		TETO:
			return b + Vector3(2, 0.8, 2)
	return b + Vector3(2, 0, 2)


# ---------------- arestas e conexões ----------------

static func _v(x: int, y: int, z: int) -> int:
	return ((x + 512) << 20) | ((y + 512) << 10) | (z + 512)


static func _e(a: int, b: int) -> int:
	return (mini(a, b) << 30) | maxi(a, b)


## Arestas da grade que a peça ocupa (inteiros únicos).
static func edges(tipo_slot: int, c: Vector3i, rot: int) -> PackedInt64Array:
	var x := c.x
	var y := c.y
	var z := c.z
	var out := PackedInt64Array()
	match tipo_slot:
		PISO, TETO:
			out.append(_e(_v(x, y, z), _v(x + 1, y, z)))
			out.append(_e(_v(x + 1, y, z), _v(x + 1, y, z + 1)))
			out.append(_e(_v(x, y, z + 1), _v(x + 1, y, z + 1)))
			out.append(_e(_v(x, y, z), _v(x, y, z + 1)))
		PAREDE_X:
			out.append(_e(_v(x, y, z), _v(x + 1, y, z)))
			out.append(_e(_v(x, y + 1, z), _v(x + 1, y + 1, z)))
			out.append(_e(_v(x, y, z), _v(x, y + 1, z)))
			out.append(_e(_v(x + 1, y, z), _v(x + 1, y + 1, z)))
		PAREDE_Z:
			out.append(_e(_v(x, y, z), _v(x, y, z + 1)))
			out.append(_e(_v(x, y + 1, z), _v(x, y + 1, z + 1)))
			out.append(_e(_v(x, y, z), _v(x, y + 1, z)))
			out.append(_e(_v(x, y, z + 1), _v(x, y + 1, z + 1)))
		RAMPA:
			# aresta de baixo (lado oposto à subida) e de cima (y+1, lado da subida) + laterais diagonais
			var baixo: Array
			var cima: Array
			match rot:
				0:
					baixo = [Vector3i(x, y, z + 1), Vector3i(x + 1, y, z + 1)]
					cima = [Vector3i(x, y + 1, z), Vector3i(x + 1, y + 1, z)]
				1:
					baixo = [Vector3i(x + 1, y, z), Vector3i(x + 1, y, z + 1)]
					cima = [Vector3i(x, y + 1, z), Vector3i(x, y + 1, z + 1)]
				2:
					baixo = [Vector3i(x, y, z), Vector3i(x + 1, y, z)]
					cima = [Vector3i(x, y + 1, z + 1), Vector3i(x + 1, y + 1, z + 1)]
				_:
					baixo = [Vector3i(x, y, z), Vector3i(x, y, z + 1)]
					cima = [Vector3i(x + 1, y + 1, z), Vector3i(x + 1, y + 1, z + 1)]
			var vb: Array = baixo.map(func(p): return _v(p.x, p.y, p.z))
			var vc: Array = cima.map(func(p): return _v(p.x, p.y, p.z))
			out.append(_e(vb[0], vb[1]))
			out.append(_e(vc[0], vc[1]))
			out.append(_e(vb[0], vc[0]))
			out.append(_e(vb[1], vc[1]))
	return out


## Pontos de baixo da peça (ancoragem no terreno).
static func bottom_points(tipo_slot: int, c: Vector3i, rot: int) -> Array[Vector3]:
	var b := Vector3(c) * T
	var out: Array[Vector3] = []
	match tipo_slot:
		PAREDE_X:
			out = [b, b + Vector3(T, 0, 0), b + Vector3(2, 0, 0)]
		PAREDE_Z:
			out = [b, b + Vector3(0, 0, T), b + Vector3(0, 0, 2)]
		RAMPA:
			var lados := {0: [Vector3(0, 0, T), Vector3(T, 0, T)], 1: [Vector3(T, 0, 0), Vector3(T, 0, T)],
					2: [Vector3(0, 0, 0), Vector3(T, 0, 0)], 3: [Vector3(0, 0, 0), Vector3(0, 0, T)]}
			for p in lados[rot % 4]:
				out.append(b + p)
		_:
			out = [b, b + Vector3(T, 0, 0), b + Vector3(0, 0, T), b + Vector3(T, 0, T), b + Vector3(2, 0, 2)]
	return out


## Ancorada: algum ponto de baixo está no chão ou enterrado (até 0,35 m acima do terreno).
static func anchored(tipo_slot: int, c: Vector3i, rot: int, altura: Callable) -> bool:
	for p in bottom_points(tipo_slot, c, rot):
		if altura.call(p.x, p.z) >= p.y - 0.35:
			return true
	return false


# ---------------- edição (ladrilhos) ----------------

static func tiles_of(tipo_slot: int) -> Vector2i:
	match tipo_slot:
		PAREDE_X, PAREDE_Z:
			return Vector2i(3, 3)
		PISO:
			return Vector2i(2, 2)
	return Vector2i.ZERO


static func full_mask(tipo_slot: int) -> int:
	var t := tiles_of(tipo_slot)
	return (1 << (t.x * t.y)) - 1 if t.x > 0 else 0


static func editable(tipo_slot: int) -> bool:
	return full_mask(tipo_slot) > 0


## Máscara válida: só bits do tipo e pelo menos um ladrilho.
static func valid_mask(tipo_slot: int, mask: int) -> bool:
	var f := full_mask(tipo_slot)
	return f > 0 and mask > 0 and (mask & ~f) == 0


## Caixas dos ladrilhos presentes, no espaço local da peça (igual ao do asset):
## [[centro, tamanho], ...]. Parede: x -2..2, y 0..4, espessura 0,24. Piso: x,z -2..2, topo 0,10.
static func tile_boxes(tipo_slot: int, mask: int) -> Array:
	var out := []
	var t := tiles_of(tipo_slot)
	for j in t.y:
		for i in t.x:
			if mask & (1 << (j * t.x + i)) == 0:
				continue
			if tipo_slot == PISO:
				out.append([Vector3(-2.0 + (i + 0.5) * 2.0, 0.0, -2.0 + (j + 0.5) * 2.0), Vector3(2.0, 0.2, 2.0)])
			else:
				var s := T / 3.0
				out.append([Vector3(-2.0 + (i + 0.5) * s, (j + 0.5) * s, 0.0), Vector3(s, s, 0.24)])
	return out


## Ladrilho atingido por um ponto (mundo) numa peça editável, ou -1.
static func tile_at(tipo_slot: int, cell: Vector3i, rot: int, ponto: Vector3) -> int:
	var local := transform(tipo_slot, cell, rot).affine_inverse() * ponto
	var t := tiles_of(tipo_slot)
	if t.x == 0:
		return -1
	var i: int
	var j: int
	if tipo_slot == PISO:
		i = clampi(floori((local.x + 2.0) / 2.0), 0, 1)
		j = clampi(floori((local.z + 2.0) / 2.0), 0, 1)
	else:
		i = clampi(floori((local.x + 2.0) / (T / 3.0)), 0, 2)
		j = clampi(floori(local.y / (T / 3.0)), 0, 2)
	return j * t.x + i


# ---------------- alvo (onde a peça vai) ----------------

## Escolha do slot como nos jogos do gênero: parede na borda da sua célula para
## onde você olha; piso e rampa na célula da frente (piso sob os pés olhando para
## baixo); teto em cima da sua célula. Olhar bem para cima sobe um nível.
## Retorna {"tipo": slot, "cell": Vector3i, "rot": int}.
static func target(escolha: int, pes: Vector3, yaw: float, pitch: float) -> Dictionary:
	var base := Vector3i(floori(pes.x / T), floori((pes.y + 0.3) / T), floori(pes.z / T))
	# direção cardinal do olhar: 0 = -Z, 1 = -X, 2 = +Z, 3 = +X
	var d := posmod(roundi(yaw / (PI * 0.5)), 4)
	var passo: Vector3i = [Vector3i(0, 0, -1), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(1, 0, 0)][d]
	var cima := 1 if pitch > deg_to_rad(38.0) else 0
	match escolha:
		0:
			var c := base + Vector3i(0, cima, 0)
			match d:
				0:
					return {"tipo": PAREDE_X, "cell": c, "rot": 0}
				2:
					return {"tipo": PAREDE_X, "cell": c + Vector3i(0, 0, 1), "rot": 2}
				1:
					return {"tipo": PAREDE_Z, "cell": c, "rot": 1}
				_:
					return {"tipo": PAREDE_Z, "cell": c + Vector3i(1, 0, 0), "rot": 3}
		1:
			if pitch < deg_to_rad(-35.0):
				return {"tipo": PISO, "cell": base, "rot": 0}
			return {"tipo": PISO, "cell": base + passo + Vector3i(0, cima, 0), "rot": 0}
		2:
			return {"tipo": RAMPA, "cell": base + passo + Vector3i(0, cima, 0), "rot": d}
	return {"tipo": TETO, "cell": base + Vector3i(0, 1, 0), "rot": 0}


# ---------------- assets do kit (uma vez) ----------------

## Malhas e formas de colisão de um GLB do kit, relativas à raiz (cache).
static func kit(caminho: String) -> Dictionary:
	if _kit.has(caminho):
		return _kit[caminho]
	var cena := (load(caminho) as PackedScene).instantiate() as Node3D
	var d := {"malhas": [], "formas": []}
	_coletar(cena, Transform3D(), d)
	cena.free()
	_kit[caminho] = d
	return d


static func _coletar(n: Node, acumulado: Transform3D, d: Dictionary) -> void:
	for c in n.get_children():
		var t := acumulado
		if c is Node3D:
			t = acumulado * (c as Node3D).transform
		if c is MeshInstance3D and (c as MeshInstance3D).mesh:
			d["malhas"].append([(c as MeshInstance3D).mesh, t])
		elif c is CollisionShape3D and (c as CollisionShape3D).shape:
			d["formas"].append([(c as CollisionShape3D).shape, t])
		_coletar(c, t, d)


# ---------------- ladrilhos com a malha do kit (edição) ----------------

static var _ladrilhos := {}          # caminho -> Array[Mesh] (um por ladrilho; null se vazio)


## Limites (espaço local da peça) do ladrilho t: [eixo1 min, max, eixo2 min, max];
## eixo1 = x; eixo2 = y (parede) ou z (piso). Bordas externas vão ao infinito para
## não cortar chanfros e detalhes que passam um pouco da grade.
static func _limites(tipo_slot: int, t: int) -> Array:
	var tl := tiles_of(tipo_slot)
	var i := t % tl.x
	var j := t / tl.x
	var s := T / float(tl.x)
	var x0 := -2.0 + i * s
	var a0 := (j * s) if tipo_slot != PISO else (-2.0 + j * s)
	var inf := 1e6
	return [-inf if i == 0 else x0, inf if i == tl.x - 1 else x0 + s,
			-inf if j == 0 else a0, inf if j == tl.y - 1 else a0 + s]


## Recorta um polígono (vértices [pos, normal, uv]) pelo semiplano eixo >= valor (ou <=).
static func _cortar(poly: Array, eixo: int, valor: float, maior: bool) -> Array:
	var out := []
	var n := poly.size()
	for k in n:
		var a: Array = poly[k]
		var b: Array = poly[(k + 1) % n]
		var da: float = (a[0][eixo] - valor) * (1.0 if maior else -1.0)
		var db: float = (b[0][eixo] - valor) * (1.0 if maior else -1.0)
		if da >= 0.0:
			out.append(a)
		if (da >= 0.0) != (db >= 0.0):
			var f := da / (da - db)
			out.append([(a[0] as Vector3).lerp(b[0], f), (a[1] as Vector3).lerp(b[1], f).normalized(), (a[2] as Vector2).lerp(b[2], f)])
	return out


## Malhas dos ladrilhos de uma peça do kit (recorte geométrico dos triângulos pelos
## limites de cada ladrilho, com UV e normais interpolados). Cache por asset.
static func tile_meshes(tipo_slot: int, material: int) -> Array:
	var caminho := asset_path(tipo_slot, material)
	if _ladrilhos.has(caminho):
		return _ladrilhos[caminho]
	var tl := tiles_of(tipo_slot)
	var eixo2 := 1 if tipo_slot != PISO else 2
	var tris := []
	var mat_kit: Material = null
	for m in kit(caminho)["malhas"]:
		var malha: Mesh = m[0]
		var xf: Transform3D = m[1]
		for sfc in malha.get_surface_count():
			mat_kit = malha.surface_get_material(sfc)
			var arr := malha.surface_get_arrays(sfc)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var ns: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			var uvs: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV] if arr[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(vs.size()))
			for k in range(0, idx.size(), 3):
				var tri := []
				for q in 3:
					var v := idx[k + q]
					tri.append([xf * vs[v], (xf.basis * ns[v]).normalized(), uvs[v] if uvs.size() > v else Vector2.ZERO])
				tris.append(tri)
	var out := []
	for t in tl.x * tl.y:
		var lim := _limites(tipo_slot, t)
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var algum := false
		for tri in tris:
			var poly: Array = tri
			poly = _cortar(poly, 0, lim[0], true)
			if poly.size() >= 3:
				poly = _cortar(poly, 0, lim[1], false)
			if poly.size() >= 3:
				poly = _cortar(poly, eixo2, lim[2], true)
			if poly.size() >= 3:
				poly = _cortar(poly, eixo2, lim[3], false)
			if poly.size() < 3:
				continue
			algum = true
			for k in range(1, poly.size() - 1):
				for v in [poly[0], poly[k], poly[k + 1]]:
					st.set_normal(v[1])
					st.set_uv(v[2])
					st.add_vertex(v[0])
		if algum:
			if mat_kit:
				st.set_material(mat_kit)
			out.append(st.commit())
		else:
			out.append(null)
	_ladrilhos[caminho] = out
	return out


## Molduras das aberturas: para cada ladrilho presente, as bordas que dão para um
## ladrilho removido viram uma tira [centro local, tamanho] (fecha a espessura da
## parede e marca portas e janelas).
static func frame_boxes(tipo_slot: int, mask: int) -> Array:
	var out := []
	var tl := tiles_of(tipo_slot)
	if tl.x == 0 or tipo_slot == PISO:
		return out
	var s := T / 3.0
	for j in tl.y:
		for i in tl.x:
			if mask & (1 << (j * 3 + i)) == 0:
				continue
			var cx := -2.0 + (i + 0.5) * s
			var cy := (j + 0.5) * s
			for d in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
				var ni: int = i + d.x
				var nj: int = j + d.y
				if ni < 0 or ni > 2 or nj < 0 or nj > 2 or mask & (1 << (nj * 3 + ni)) != 0:
					continue
				if d.x != 0:
					out.append([Vector3(cx + d.x * (s * 0.5 - 0.05), cy, 0.0), Vector3(0.1, s, 0.32)])
				else:
					out.append([Vector3(cx, cy + d.y * (s * 0.5 - 0.05), 0.0), Vector3(s, 0.1, 0.32)])
	return out
