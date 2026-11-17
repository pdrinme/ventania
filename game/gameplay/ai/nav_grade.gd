class_name NavGrade
extends RefCounted
## Navegação dos bots: grafo sobre a GRADE DE CONSTRUÇÃO (4 m), com A*.
## Por que não NavigationServer3D/navmesh: assar uma navmesh de 600 m com centenas
## de peças custa segundos no servidor (hardware modesto) e precisaria ser refeita
## a cada construção. Aqui tudo é atualizado na hora, peça por peça.
##
## Nós:
##  - CHÃO: 150 × 150 células (bloqueadas: mar/praia muito rasa, obstáculos grandes
##    como rochas e contêineres, o cômodo térreo das escadas);
##  - ANDARES: uma por peça de PISO acima do chão (> 2,5 m do relevo), por nível.
## Arestas:
##  - chão: 8 vizinhos; parede = aresta bloqueada (porta aberta pelo ladrilho);
##    degrau de relevo > 2,2 m bloqueia;
##  - andares: 4 vizinhos no mesmo nível, sem parede no meio;
##  - LIGAÇÕES entre níveis, com pontos de passagem exatos: escadas dos edifícios
##    (caminho em U, gerar_interiores.py) e rampas de construção (do mapa e as que os
##    jogadores constroem).
## Portas viram pontos de passagem exatos (no meio do vão), para o bot não cortar a
## quina do batente. Obstáculos pequenos (troncos, postes, mobília) ficam para o
## desvio local do bot.

const T := 4.0
const LIMITE := 300.0
const N := 150                       # células por lado
const MAX_EXPANSOES := 7000
const ALTURA_ANDAR := 2.5            # piso acima disso (do relevo) é um andar
const DESNIVEL_MAX := 3.4            # entre centros de células vizinhas do chão
enum { L_N, L_L, L_S, L_O }          # bits de aresta: norte (-z), leste (+x), sul (+z), oeste (-x)
const DIRS := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
## Caminho em U das escadas, no espaço da escada (origem no centro do cômodo, piso
## de baixo; chega pelo cômodo vizinho +x). Mesmo desenho de gerar_interiores.py.
const ROTA_ESCADA := [Vector3(1.5, 0.1, 1.0), Vector3(-1.25, 2.1, 1.0), Vector3(-1.25, 2.1, -1.0),
		Vector3(-0.3, 2.1, -1.0), Vector3(2.0, 4.1, -1.0)]

var _bloq := PackedByteArray()       # 1 = célula do chão bloqueada
var _arestas := PackedByteArray()    # bits L_* (chão)
var _portas := PackedByteArray()     # bits L_*: aresta do chão com porta (ponto de passagem exato)
var _altura := PackedFloat32Array()
var _sup := {}                       # Vector3i(i, j, nível) -> id do nó de andar
var _sup_pos: Array[Vector3] = []    # id - N*N -> centro do piso (x, topo, z)
var _sup_cel: Array[Vector3i] = []
var _sup_ativo := PackedByteArray()
var _sup_paredes := {}               # Vector4i(i, j, nível, lado) -> true
var _ligacoes := {}                  # id -> [[id2, custo, PackedVector3Array pontos], ...]
var _rampas := {}                    # Vector3i(cell) -> [a, b] (ids ligados pela rampa)
var _rampas_pendentes := {}          # Vector3i(cell) -> rot (rampa sem piso numa das pontas, ainda)
var mapa: Mapa
var caminhos := 0                    # diagnóstico: A* executados
var expansoes := 0
var escadas := 0


func _init(m: Mapa) -> void:
	mapa = m
	_bloq.resize(N * N)
	_arestas.resize(N * N)
	_portas.resize(N * N)
	_altura.resize(N * N)
	for j in N:
		for i in N:
			var c := centro(i, j)
			var h := m.ground_height(c.x, c.y)
			_altura[j * N + i] = h
			if h < 0.2 or (m.has_method("inland") and m.inland(c.x, c.y) < 3.0):
				_bloq[j * N + i] = 1
	# encostas mais íngremes que ~40° (3,4 m em 4 m) viram arestas bloqueadas; o
	# personagem sobe até 50° (Pawn.floor_max_angle): 2,2 m (29°) criava becos falsos
	for j in N:
		for i in N:
			if i + 1 < N and absf(_altura[j * N + i] - _altura[j * N + i + 1]) > DESNIVEL_MAX:
				_bloquear_aresta(i, j, L_L)
			if j + 1 < N and absf(_altura[j * N + i] - _altura[(j + 1) * N + i]) > DESNIVEL_MAX:
				_bloquear_aresta(i, j, L_S)
	if m.has_method("nav_obstacles"):
		for o in m.nav_obstacles():
			if o.size() == 3:
				_obstaculo_ret(o[0], o[1], o[2])
			else:
				_obstaculo(o[0], o[1])
	for e: Dictionary in m.stairs():
		add_stair(e["pos"], float(e["rot"]))


func centro(i: int, j: int) -> Vector2:
	return Vector2(-LIMITE + (i + 0.5) * T, -LIMITE + (j + 0.5) * T)


func cell_of(p: Vector2) -> Vector2i:
	return Vector2i(clampi(floori((p.x + LIMITE) / T), 0, N - 1), clampi(floori((p.y + LIMITE) / T), 0, N - 1))


func blocked(c: Vector2i) -> bool:
	return _bloq[c.y * N + c.x] != 0


func node_count() -> int:
	return N * N + _sup_pos.size()


func floor_nodes() -> int:
	var n := 0
	for a in _sup_ativo:
		n += a
	return n


func _obstaculo(p: Vector2, raio: float) -> void:
	var a := cell_of(p - Vector2(raio, raio))
	var b := cell_of(p + Vector2(raio, raio))
	for j in range(a.y, b.y + 1):
		for i in range(a.x, b.x + 1):
			if centro(i, j).distance_to(p) < raio + 0.6:
				_bloq[j * N + i] = 1


## Retângulo (centro, meias medidas, ângulo): bloqueia as células cujo centro fica
## a menos de 0,45 m dele (raio do personagem + folga).
func _obstaculo_ret(p: Vector2, meio: Vector2, ang: float) -> void:
	var r := meio.length() + 1.0
	var a := cell_of(p - Vector2(r, r))
	var b := cell_of(p + Vector2(r, r))
	for j in range(a.y, b.y + 1):
		for i in range(a.x, b.x + 1):
			var local := (centro(i, j) - p).rotated(-ang)
			if absf(local.x) < meio.x + 0.45 and absf(local.y) < meio.y + 0.45:
				_bloq[j * N + i] = 1


func _bloquear_aresta(i: int, j: int, lado: int, liberar := false, portas := false) -> void:
	var viz: Vector2i = DIRS[lado]
	var oposto := (lado + 2) % 4
	var k := j * N + i
	var ni := i + viz.x
	var nj := j + viz.y
	var dentro := ni >= 0 and nj >= 0 and ni < N and nj < N
	if portas:
		_portas[k] = (_portas[k] & ~(1 << lado)) if liberar else (_portas[k] | (1 << lado))
		if dentro:
			_portas[nj * N + ni] = (_portas[nj * N + ni] & ~(1 << oposto)) if liberar else (_portas[nj * N + ni] | (1 << oposto))
		return
	_arestas[k] = (_arestas[k] & ~(1 << lado)) if liberar else (_arestas[k] | (1 << lado))
	if dentro:
		_arestas[nj * N + ni] = (_arestas[nj * N + ni] & ~(1 << oposto)) if liberar else (_arestas[nj * N + ni] | (1 << oposto))


## Compatibilidade (chamada antiga): só paredes.
func set_wall(tipo: int, cell: Vector3i, mask: int, existe: bool) -> void:
	set_piece(tipo, cell, 0, mask, existe)


## Uma peça de construção surgiu (existe) ou sumiu: paredes (chão e andares),
## pisos de andares (nós) e rampas (ligações entre níveis). Chamada pelo BuildServer.
func set_piece(tipo: int, cell: Vector3i, rot: int, mask: int, existe: bool) -> void:
	var i := cell.x + N / 2
	var j := cell.z + N / 2
	if i < 0 or j < 0 or i >= N or j >= N:
		return
	match tipo:
		Grade.PAREDE_X, Grade.PAREDE_Z:
			var lado := L_N if tipo == Grade.PAREDE_X else L_O
			var porta := mask & (1 << 1) == 0
			var aberta := not existe or porta
			var base := mapa.ground_height(cell.x * T + 2.0, cell.z * T + 2.0)
			if absf(cell.y * T - base) <= ALTURA_ANDAR:
				_bloquear_aresta(i, j, lado, aberta)
				_bloquear_aresta(i, j, lado, not (existe and porta), true)
			else:
				var viz: Vector2i = DIRS[lado]
				var k1 := Vector4i(i, j, cell.y, lado)
				var k2 := Vector4i(i + viz.x, j + viz.y, cell.y, (lado + 2) % 4)
				if aberta:
					_sup_paredes.erase(k1)
					_sup_paredes.erase(k2)
				else:
					_sup_paredes[k1] = true
					_sup_paredes[k2] = true
		Grade.PISO:
			var topo := cell.y * T + 0.1
			if topo - mapa.ground_height(cell.x * T + 2.0, cell.z * T + 2.0) <= ALTURA_ANDAR:
				return                       # piso térreo: é o chão
			var chave := Vector3i(i, j, cell.y)
			if existe:
				if _sup.has(chave):
					_sup_ativo[int(_sup[chave]) - N * N] = 1
					return
				_sup[chave] = N * N + _sup_pos.size()
				_sup_pos.append(Vector3(cell.x * T + 2.0, topo, cell.z * T + 2.0))
				_sup_cel.append(chave)
				_sup_ativo.append(1)
				for rc in _rampas_pendentes.keys():
					_rampa(rc, _rampas_pendentes[rc], true)
			elif _sup.has(chave):
				_sup_ativo[int(_sup[chave]) - N * N] = 0
		Grade.RAMPA:
			_rampa(cell, rot, existe)


## Rampa na célula `cell` subindo na direção de rot (0 -Z, 1 -X, 2 +Z, 3 +X).
func _rampa(cell: Vector3i, rot: int, existe: bool) -> void:
	if _rampas.has(cell):
		var ab: Array = _rampas[cell]
		_desligar(ab[0], ab[1])
		_rampas.erase(cell)
	if not existe:
		return
	var d: Vector2i = [Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(1, 0)][rot % 4]
	var baixo := Vector3i(cell.x - d.x, cell.y, cell.z - d.y)
	var alto := Vector3i(cell.x + d.x, cell.y + 1, cell.z + d.y)
	var a := _no_em_celula(baixo)
	var b := _no_em_celula(alto)
	if a < 0 or b < 0:
		_rampas_pendentes[cell] = rot          # liga quando o piso aparecer
		return
	_rampas_pendentes.erase(cell)
	var c := Vector3(cell.x * T + 2.0, cell.y * T, cell.z * T + 2.0)
	var dv := Vector3(d.x, 0, d.y)
	var pontos := PackedVector3Array([c - dv * 2.0 + Vector3(0, 0.1, 0), c + Vector3(0, 2.1, 0), c + dv * 2.0 + Vector3(0, 4.1, 0)])
	_ligar(a, b, 1.6, pontos)
	_rampas[cell] = [a, b]


## Nó de uma célula da grade de construção num nível (chão se for o nível do relevo).
func _no_em_celula(cel: Vector3i) -> int:
	var i := cel.x + N / 2
	var j := cel.z + N / 2
	if i < 0 or j < 0 or i >= N or j >= N:
		return -1
	if cel.y * T + 0.1 - _altura[j * N + i] <= ALTURA_ANDAR:
		return -1 if _bloq[j * N + i] != 0 else j * N + i
	var chave := Vector3i(i, j, cel.y)
	if _sup.has(chave) and _sup_ativo[int(_sup[chave]) - N * N] != 0:
		return _sup[chave]
	return -1


## Escada em U de um edifício: liga o cômodo vizinho (de chegada) no nível de baixo
## ao mesmo cômodo no nível de cima, pelos pontos do caminho em U.
func add_stair(base: Vector3, rot_graus: float) -> void:
	var giro := Basis(Vector3.UP, deg_to_rad(rot_graus))
	var cel := Vector3i(floori(base.x / T), roundi(base.y / T), floori(base.z / T))
	var dx := 1 if absf(rot_graus) < 1.0 else -1
	# o cômodo da escada no chão não é passagem (está ocupado pela escada)
	var i := cel.x + N / 2
	var j := cel.z + N / 2
	if base.y + 0.1 - _altura[j * N + i] <= ALTURA_ANDAR:
		_bloq[j * N + i] = 1
	var a := _no_em_celula(Vector3i(cel.x + dx, cel.y, cel.z))
	var b := _no_em_celula(Vector3i(cel.x + dx, cel.y + 1, cel.z))
	if a < 0 or b < 0:
		# o andar de cima ainda não existe (as peças entram depois): tenta de novo nelas
		_escadas_pendentes.append([base, rot_graus])
		return
	var pontos := PackedVector3Array()
	for r: Vector3 in ROTA_ESCADA:
		pontos.append(base + giro * r)
	_ligar(a, b, 3.0, pontos)
	escadas += 1


var _escadas_pendentes: Array = []


## Liga as escadas cujos andares foram criados depois (chame após colocar as peças).
func resolve_stairs() -> void:
	var p := _escadas_pendentes
	_escadas_pendentes = []
	for e in p:
		add_stair(e[0], e[1])


func _ligar(a: int, b: int, custo: float, pontos: PackedVector3Array) -> void:
	var inv := pontos.duplicate()
	inv.reverse()
	(_ligacoes.get_or_add(a, []) as Array).append([b, custo, pontos])
	(_ligacoes.get_or_add(b, []) as Array).append([a, custo, inv])


func _desligar(a: int, b: int) -> void:
	for par in [[a, b], [b, a]]:
		var lista: Array = _ligacoes.get(par[0], [])
		for k in range(lista.size() - 1, -1, -1):
			if lista[k][0] == par[1]:
				lista.remove_at(k)


func _livre(de: Vector2i, para: Vector2i) -> bool:
	if para.x < 0 or para.y < 0 or para.x >= N or para.y >= N or blocked(para):
		return false
	var d := para - de
	var k := de.y * N + de.x
	if d.x == 0 or d.y == 0:
		var lado := L_L if d.x == 1 else (L_O if d.x == -1 else (L_S if d.y == 1 else L_N))
		return _arestas[k] & (1 << lado) == 0
	# diagonal: as duas ortogonais precisam estar livres e sem porta (não corta batente)
	var h := de + Vector2i(d.x, 0)
	var v := de + Vector2i(0, d.y)
	if _portas[k] != 0 or _portas[para.y * N + para.x] != 0:
		return false
	return _livre(de, h) and _livre(h, para) and _livre(de, v) and _livre(v, para)


## Posição de um nó (centro da célula, na altura do piso).
func node_pos(id: int) -> Vector3:
	if id < N * N:
		var c := centro(id % N, id / N)
		return Vector3(c.x, _altura[id], c.y)
	return _sup_pos[id - N * N]


## Nó onde está um ponto do mundo (no chão, num andar ou numa escada/rampa).
func node_of(p: Vector3) -> int:
	var c := cell_of(Vector2(p.x, p.z))
	var k := c.y * N + c.x
	if p.y - _altura[k] <= ALTURA_ANDAR - 0.3 or _sup.is_empty():
		return k if _bloq[k] == 0 else _livre_perto(c).y * N + _livre_perto(c).x
	# andar: o piso mais alto abaixo do ponto, nesta célula ou numa vizinha
	var melhor := -1
	var dist := 1e9
	for dj in range(-1, 2):
		for di in range(-1, 2):
			for nivel in [floori((p.y + 0.5) / T), floori((p.y + 0.5) / T) - 1]:
				var chave := Vector3i(c.x + di, c.y + dj, nivel)
				if not _sup.has(chave):
					continue
				var id: int = _sup[chave]
				if _sup_ativo[id - N * N] == 0:
					continue
				var d := _sup_pos[id - N * N].distance_to(p) + (0.0 if di == 0 and dj == 0 else 1.5)
				if d < dist:
					dist = d
					melhor = id
	if melhor >= 0:
		return melhor
	return k if _bloq[k] == 0 else _livre_perto(c).y * N + _livre_perto(c).x


## Compatibilidade: caminho no plano (x, z).
func path(de: Vector2, para: Vector2) -> PackedVector2Array:
	var r := path3(Vector3(de.x, mapa.ground_height(de.x, de.y), de.y), Vector3(para.x, mapa.ground_height(para.x, para.y), para.y))
	var out := PackedVector2Array()
	for p: Vector3 in r["pontos"]:
		out.append(Vector2(p.x, p.z))
	return out


## A* no grafo (chão + andares + ligações). evitar: {chave_aresta: true} (arestas que
## este bot viu travar; ver edge_key). Retorna {"pontos": PackedVector3Array,
## "precisos": PackedByteArray (1 = porta/escada/rampa: chegar perto antes de seguir),
## "nos": PackedInt32Array}; pontos vazio se não achou no orçamento.
func path3(de: Vector3, para: Vector3, evitar := {}) -> Dictionary:
	caminhos += 1
	var a := node_of(de)
	var b := node_of(para)
	var aberto := [[0.0, a]]
	var veio := {a: a}
	var via := {}                     # id -> pontos da ligação usada para chegar nele
	var g := {a: 0.0}
	var n := 0
	var pb := node_pos(b)
	while not aberto.is_empty() and n < MAX_EXPANSOES:
		var atual: int = _pop(aberto)[1]
		n += 1
		if atual == b:
			break
		for viz in _vizinhos(atual):
			var id: int = viz[0]
			if not evitar.is_empty() and evitar.has(edge_key(atual, id)):
				continue
			var custo: float = g[atual] + float(viz[1])
			if not g.has(id) or custo < g[id]:
				g[id] = custo
				veio[id] = atual
				if viz.size() > 2:
					via[id] = viz[2]
				else:
					via.erase(id)
				var pi := node_pos(id)
				var dx := absf(pi.x - pb.x) / T
				var dz := absf(pi.z - pb.z) / T
				var hh := (maxf(dx, dz) + 0.414 * minf(dx, dz) + absf(pi.y - pb.y) / T) * 1.3
				_push(aberto, [custo + hh, id])
	expansoes += n
	if not veio.has(b):
		return {"pontos": PackedVector3Array(), "precisos": PackedByteArray(), "nos": PackedInt32Array()}
	var nos: Array[int] = []
	var c := b
	while c != a:
		nos.append(c)
		c = veio[c]
	nos.append(a)
	nos.reverse()
	var pontos := PackedVector3Array()
	var precisos := PackedByteArray()
	for k in range(1, nos.size()):
		var anterior := nos[k - 1]
		var id := nos[k]
		if via.has(id) and veio[id] == anterior and _e_ligacao(anterior, id):
			for p: Vector3 in via[id]:
				pontos.append(p)
				precisos.append(1)
		elif anterior < N * N and id < N * N and _porta_entre(anterior, id):
			var pa := node_pos(anterior)
			var pn := node_pos(id)
			pontos.append((pa + pn) / 2.0)
			precisos.append(1)
		# corta pontos colineares do chão (caminho mais limpo)
		if k < nos.size() - 1 and id < N * N and nos[k + 1] < N * N and anterior < N * N \
				and not via.has(nos[k + 1]) and id - anterior == nos[k + 1] - id:
			continue
		pontos.append(node_pos(id))
		precisos.append(0)
	pontos.append(para)
	precisos.append(0)
	return {"pontos": pontos, "precisos": precisos, "nos": PackedInt32Array(nos)}


static func edge_key(a: int, b: int) -> int:
	return mini(a, b) * 131072 + maxi(a, b)


func _e_ligacao(a: int, b: int) -> bool:
	for l in _ligacoes.get(a, []):
		if l[0] == b:
			return true
	return false


func _porta_entre(a: int, b: int) -> bool:
	var ca := Vector2i(a % N, a / N)
	var cb := Vector2i(b % N, b / N)
	var d := cb - ca
	if absi(d.x) + absi(d.y) != 1:
		return false
	var lado := L_L if d.x == 1 else (L_O if d.x == -1 else (L_S if d.y == 1 else L_N))
	return _portas[a] & (1 << lado) != 0


## [[id, custo(, pontos)], ...]
func _vizinhos(id: int) -> Array:
	var out := []
	if id < N * N:
		var c := Vector2i(id % N, id / N)
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
			var v: Vector2i = c + d
			if _livre(c, v):
				out.append([v.y * N + v.x, 1.414 if d.x != 0 and d.y != 0 else 1.0])
	else:
		var cel := _sup_cel[id - N * N]
		for lado in 4:
			if _sup_paredes.has(Vector4i(cel.x, cel.y, cel.z, lado)):
				continue
			var dv: Vector2i = DIRS[lado]
			var chave := Vector3i(cel.x + dv.x, cel.y + dv.y, cel.z)
			if _sup.has(chave) and _sup_ativo[int(_sup[chave]) - N * N] != 0:
				out.append([_sup[chave], 1.0])
	for l in _ligacoes.get(id, []):
		if l[0] >= N * N and _sup_ativo[int(l[0]) - N * N] == 0:
			continue
		out.append(l)
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
