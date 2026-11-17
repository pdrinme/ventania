class_name NavGrade
extends RefCounted
## Navegação dos bots (Etapa 6): grade de 4 m ALINHADA À GRADE DE CONSTRUÇÃO, com A*.
## Por que não NavigationServer3D/navmesh: assar uma navmesh de 600 m com centenas
## de peças custa segundos no servidor (hardware modesto) e precisaria ser refeita
## a cada construção. Aqui as paredes são ARESTAS bloqueadas entre células (portas
## abertas pelos ladrilhos), atualizadas na hora quando peças surgem ou somem.
##  - célula bloqueada: mar/praia muito rasa, obstáculos grandes (rochas, contêineres…)
##  - aresta bloqueada: parede (exceto porta), degrau de relevo > 2,2 m
## Obstáculos pequenos (troncos de árvore, postes) ficam para o desvio local do bot.

const T := 4.0
const LIMITE := 300.0
const N := 150                       # células por lado
const MAX_EXPANSOES := 6000
enum { L_N, L_L, L_S, L_O }          # bits de aresta bloqueada: norte (-z), leste (+x), sul (+z), oeste (-x)

var _bloq := PackedByteArray()       # 1 = célula bloqueada
var _arestas := PackedByteArray()    # bits L_*
var _altura := PackedFloat32Array()
var mapa: Mapa
var caminhos := 0                    # diagnóstico: A* executados
var expansoes := 0


func _init(m: Mapa) -> void:
	mapa = m
	_bloq.resize(N * N)
	_arestas.resize(N * N)
	_altura.resize(N * N)
	for j in N:
		for i in N:
			var c := centro(i, j)
			var h := m.ground_height(c.x, c.y)
			_altura[j * N + i] = h
			if h < 0.2 or (m.has_method("inland") and m.inland(c.x, c.y) < 3.0):
				_bloq[j * N + i] = 1
	# degraus fortes no relevo viram arestas bloqueadas
	for j in N:
		for i in N:
			if i + 1 < N and absf(_altura[j * N + i] - _altura[j * N + i + 1]) > 2.2:
				_bloquear_aresta(i, j, L_L)
			if j + 1 < N and absf(_altura[j * N + i] - _altura[(j + 1) * N + i]) > 2.2:
				_bloquear_aresta(i, j, L_S)
	if m.has_method("nav_obstacles"):
		for o in m.nav_obstacles():
			_obstaculo(o[0], o[1])


func centro(i: int, j: int) -> Vector2:
	return Vector2(-LIMITE + (i + 0.5) * T, -LIMITE + (j + 0.5) * T)


func cell_of(p: Vector2) -> Vector2i:
	return Vector2i(clampi(floori((p.x + LIMITE) / T), 0, N - 1), clampi(floori((p.y + LIMITE) / T), 0, N - 1))


func blocked(c: Vector2i) -> bool:
	return _bloq[c.y * N + c.x] != 0


func _obstaculo(p: Vector2, raio: float) -> void:
	var a := cell_of(p - Vector2(raio, raio))
	var b := cell_of(p + Vector2(raio, raio))
	for j in range(a.y, b.y + 1):
		for i in range(a.x, b.x + 1):
			if centro(i, j).distance_to(p) < raio + 0.6:
				_bloq[j * N + i] = 1


func _bloquear_aresta(i: int, j: int, lado: int, liberar := false) -> void:
	var viz := {L_N: Vector2i(0, -1), L_L: Vector2i(1, 0), L_S: Vector2i(0, 1), L_O: Vector2i(-1, 0)}[lado] as Vector2i
	var oposto := {L_N: L_S, L_L: L_O, L_S: L_N, L_O: L_L}[lado] as int
	var k := j * N + i
	var ni := i + viz.x
	var nj := j + viz.y
	if liberar:
		_arestas[k] &= ~(1 << lado)
	else:
		_arestas[k] |= 1 << lado
	if ni >= 0 and nj >= 0 and ni < N and nj < N:
		if liberar:
			_arestas[nj * N + ni] &= ~(1 << oposto)
		else:
			_arestas[nj * N + ni] |= 1 << oposto


## Parede da grade de construção (térrea): bloqueia a aresta, a não ser que tenha
## porta (ladrilho de baixo no meio removido). Chamada também pelo BuildServer.
func set_wall(tipo: int, cell: Vector3i, mask: int, existe: bool) -> void:
	if tipo != Grade.PAREDE_X and tipo != Grade.PAREDE_Z:
		return
	var base := mapa.ground_height(cell.x * T + 2.0, cell.z * T + 2.0)
	if absf(cell.y * T - base) > 2.5:
		return                      # paredes de andares de cima não atrapalham quem anda no chão
	var porta := mask & (1 << 1) == 0
	var aberta := not existe or porta
	var i := cell.x + N / 2
	var j := cell.z + N / 2
	if i < 0 or j < 0 or i >= N or j >= N:
		return
	if tipo == Grade.PAREDE_X:
		_bloquear_aresta(i, j, L_N, aberta)          # plano z = cz*4: entre (i, j-1) e (i, j)
	else:
		_bloquear_aresta(i, j, L_O, aberta)          # plano x = cx*4: entre (i-1, j) e (i, j)


func _livre(de: Vector2i, para: Vector2i) -> bool:
	if para.x < 0 or para.y < 0 or para.x >= N or para.y >= N or blocked(para):
		return false
	var d := para - de
	var k := de.y * N + de.x
	if d.x == 0 or d.y == 0:
		var lado := L_L if d.x == 1 else (L_O if d.x == -1 else (L_S if d.y == 1 else L_N))
		return _arestas[k] & (1 << lado) == 0
	# diagonal: as duas ortogonais precisam estar livres
	return _livre(de, de + Vector2i(d.x, 0)) and _livre(de + Vector2i(d.x, 0), para) \
			and _livre(de, de + Vector2i(0, d.y)) and _livre(de + Vector2i(0, d.y), para)


## A* (8 vizinhos, heurística octil ponderada). Retorna os pontos (x, z) do caminho
## ou [] se não achou dentro do orçamento de expansões.
func path(de: Vector2, para: Vector2) -> PackedVector2Array:
	caminhos += 1
	var a := cell_of(de)
	var b := cell_of(para)
	if blocked(b):
		b = _livre_perto(b)
	if blocked(a):
		a = _livre_perto(a)
	var aberto := [[0.0, a]]           # heap binário [f, célula]
	var veio := {a: a}
	var g := {a: 0.0}
	var n := 0
	while not aberto.is_empty() and n < MAX_EXPANSOES:
		var atual: Vector2i = _pop(aberto)[1]
		n += 1
		if atual == b:
			break
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
			var viz: Vector2i = atual + d
			if not _livre(atual, viz):
				continue
			var custo: float = g[atual] + (1.414 if d.x != 0 and d.y != 0 else 1.0)
			if not g.has(viz) or custo < g[viz]:
				g[viz] = custo
				veio[viz] = atual
				var dx := absi(b.x - viz.x)
				var dy := absi(b.y - viz.y)
				var hh := (maxi(dx, dy) + 0.414 * mini(dx, dy)) * 1.3
				_push(aberto, [custo + hh, viz])
	expansoes += n
	if not veio.has(b):
		return PackedVector2Array()
	var celulas: Array[Vector2i] = []
	var c := b
	while c != a:
		celulas.append(c)
		c = veio[c]
	celulas.reverse()
	var out := PackedVector2Array()
	for k in celulas.size():
		# corta pontos colineares (caminho mais limpo para o bot)
		if k > 0 and k < celulas.size() - 1 and celulas[k] - celulas[k - 1] == celulas[k + 1] - celulas[k]:
			continue
		out.append(centro(celulas[k].x, celulas[k].y))
	out.append(para)
	return out


func _livre_perto(c: Vector2i) -> Vector2i:
	for r in range(1, 6):
		for dj in range(-r, r + 1):
			for di in range(-r, r + 1):
				var q := c + Vector2i(di, dj)
				if q.x >= 0 and q.y >= 0 and q.x < N and q.y < N and not blocked(q):
					return q
	return c


static func _push(h: Array, e: Array) -> void:
	h.append(e)
	var i := h.size() - 1
	while i > 0:
		var p := (i - 1) / 2
		if h[p][0] <= h[i][0]:
			break
		var t = h[p]
		h[p] = h[i]
		h[i] = t
		i = p


static func _pop(h: Array) -> Array:
	var topo: Array = h[0]
	var ultimo: Array = h.pop_back()
	if not h.is_empty():
		h[0] = ultimo
		var i := 0
		while true:
			var e := 2 * i + 1
			var d := e + 1
			var m := i
			if e < h.size() and h[e][0] < h[m][0]:
				m = e
			if d < h.size() and h[d][0] < h[m][0]:
				m = d
			if m == i:
				break
			var t = h[m]
			h[m] = h[i]
			h[i] = t
			i = m
	return topo
