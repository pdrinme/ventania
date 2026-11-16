class_name IlhaVentania
extends Mapa
## Mapa Battle Royale da Etapa 4: ilha de ~600 m × 600 m, gerada de forma
## DETERMINÍSTICA (mesma semente no servidor e no cliente): relevo suave por
## ruído, praia e mar nas bordas, 6 pontos de interesse originais feitos com as
## peças do kit, cabanas espalhadas, vegetação, baús e pontos de loot.
## Desempenho: terreno em blocos (corte por distância), peças e vegetação em
## MultiMesh por região (KitInstancer) e colisão com formas compartilhadas.

const NOME := "ilha_ventania"
const SEMENTE := 20261116
const LIMITE := 300.0               # meia largura do terreno
const BORDA := 262.0                # paredes invisíveis (praia)
const PASSO := 3.0                  # resolução do relevo (m)
const N := 201                      # amostras por lado (= 2 * LIMITE / PASSO + 1)
const BLOCOS := 8                   # terreno visual em 8 × 8 blocos
const NIVEL_MAR := -1.2
const CELULA := 4.0                 # grade das construções (m)

const B := "res://assets/construcoes/"
const C := "res://assets/cenario/"

## Pontos de interesse originais: centro, raio do "platô" e tipo.
const POIS := [
	{"nome": "Vila Brisa", "pos": Vector2(-150, 55), "raio": 46.0, "tipo": "vila"},
	{"nome": "Pedreira Cinza", "pos": Vector2(40, -170), "raio": 40.0, "tipo": "pedreira"},
	{"nome": "Porto Ferrugem", "pos": Vector2(185, 45), "raio": 42.0, "tipo": "porto"},
	{"nome": "Fazenda Girassol", "pos": Vector2(-40, 170), "raio": 40.0, "tipo": "fazenda"},
	{"nome": "Mirante do Vento", "pos": Vector2(10, 5), "raio": 26.0, "tipo": "mirante"},
	{"nome": "Acampamento Coral", "pos": Vector2(-175, -150), "raio": 34.0, "tipo": "acampamento"},
]

var _alturas := PackedFloat32Array()
var _ruido := FastNoiseLite.new()
var _pads: Array = []               # [{"pos": Vector2, "raio", "h"}]
var _baus: Array = []
var _loot: Array = []
var _spawns: Array = []
var _rng := RandomNumberGenerator.new()
var _inst: KitInstancer
var _ocupado: Array = []            # [Vector2 centro, raio] (evita vegetação sobre construções)


func _init() -> void:
	_rng.seed = SEMENTE
	_ruido.seed = SEMENTE
	_ruido.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_ruido.frequency = 0.0055
	_ruido.fractal_octaves = 3
	_planejar_pads()
	_gerar_alturas()


func map_name() -> String:
	return NOME


func display_name() -> String:
	return "Ilha Ventania"


func chests() -> Array:
	return _baus


func loot_points() -> Array:
	return _loot


func match_spawn_points() -> Array:
	return _spawns


func spawn_point(i: int) -> Vector3:
	# área de espera (antes da partida): ao redor do Mirante
	var ang := i * TAU / 16.0
	var p := Vector2(10, 5) + Vector2(cos(ang), sin(ang)) * (34.0 + (i % 3) * 4.0)
	return Vector3(p.x, ground_height(p.x, p.y) + 0.3, p.y)


func death_height() -> float:
	return -20.0


func limit() -> float:
	return BORDA


func points_of_interest() -> Array:
	return POIS.map(func(p): return {"nome": p["nome"], "pos": Vector3(p["pos"].x, ground_height(p["pos"].x, p["pos"].y), p["pos"].y), "raio": p["raio"]})


# ---------------- relevo ----------------

func _planejar_pads() -> void:
	for p in POIS:
		_pads.append({"pos": p["pos"], "raio": p["raio"], "h": _altura_bruta(p["pos"].x, p["pos"].y)})
	# cabanas espalhadas: posições fixas pela semente, longe dos POIs e da borda
	var tentativas := 0
	var cabanas := 0
	while cabanas < 12 and tentativas < 400:
		tentativas += 1
		var q := Vector2(_rng.randf_range(-230, 230), _rng.randf_range(-230, 230))
		if _perto_de_pad(q, 30.0) or _altura_bruta(q.x, q.y) < 1.0:
			continue
		_pads.append({"pos": q, "raio": 9.0, "h": _altura_bruta(q.x, q.y), "cabana": true})
		cabanas += 1


func _perto_de_pad(q: Vector2, folga: float) -> bool:
	for p in _pads:
		if q.distance_to(p["pos"]) < float(p["raio"]) + folga:
			return true
	return false


## Relevo antes dos platôs: colinas suaves, morro do Mirante e praia nas bordas.
func _altura_bruta(x: float, z: float) -> float:
	var h := _ruido.get_noise_2d(x, z) * 8.0 + 4.5
	h += 9.0 * exp(-pow(Vector2(x - 10, z - 5).length() / 55.0, 2.0))
	var borda := maxf(absf(x), absf(z)) / LIMITE
	if borda > 0.74:
		h = lerpf(h, -2.0, smoothstep(0.74, 0.95, borda))     # praia junto às bordas (262 m)
	return h


func _altura_final(x: float, z: float) -> float:
	var h := _altura_bruta(x, z)
	for p in _pads:
		var d := Vector2(x, z).distance_to(p["pos"])
		var r: float = p["raio"]
		if d < r + 18.0:
			h = lerpf(h, p["h"], smoothstep(r + 18.0, r, d))
	return h


func _gerar_alturas() -> void:
	_alturas.resize(N * N)
	for j in N:
		for i in N:
			_alturas[j * N + i] = _altura_final(-LIMITE + i * PASSO, -LIMITE + j * PASSO)


func _amostra(i: int, j: int) -> float:
	return _alturas[clampi(j, 0, N - 1) * N + clampi(i, 0, N - 1)]


## Altura do terreno (bilinear sobre a grade — a mesma usada na colisão).
func ground_height(x: float, z: float) -> float:
	var fx := (x + LIMITE) / PASSO
	var fz := (z + LIMITE) / PASSO
	var i := floori(fx)
	var j := floori(fz)
	var tx := fx - i
	var tz := fz - j
	var a := lerpf(_amostra(i, j), _amostra(i + 1, j), tx)
	var b := lerpf(_amostra(i, j + 1), _amostra(i + 1, j + 1), tx)
	return lerpf(a, b, tz)


# ---------------- montagem ----------------

func _ready() -> void:
	if com_ambiente:
		_ambiente()
	_terreno()
	_bordas()
	_inst = KitInstancer.new(self, com_ambiente)
	for p in POIS:
		call("_poi_" + p["tipo"], p)
	for p in _pads:
		if p.get("cabana", false):
			_cabana(p)
	_loot_espalhado()
	_vegetacao()
	_spawns_partida()
	var grupos := _inst.build()
	for dados_bau in _baus:
		var bau := (load("res://assets/baus_coletaveis/bau_ventania_01.glb") as PackedScene).instantiate() as Node3D
		bau.position = dados_bau[0]
		bau.rotation_degrees.y = dados_bau[1]
		bau.set_meta("material", ImpactMaterial.MADEIRA)
		add_child(bau)
		chest_nodes.append(bau)
	if OS.is_debug_build():
		print("[ilha] %d corpos, %d grupos visuais, %d baús, %d pontos de loot" % [_inst.corpos, grupos, _baus.size(), _loot.size()])


func _ambiente() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("8fd3ff")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("b9c6ff")
	env.ambient_light_energy = 0.32
	env.fog_enabled = true
	env.fog_light_color = Color("cfe9ff")
	env.fog_density = 0.0022
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	we.add_to_group("ambiente")
	add_child(we)
	var sol := DirectionalLight3D.new()
	sol.rotation_degrees = Vector3(-50, -35, 0)
	sol.light_color = Color("fff3dc")
	sol.light_energy = 0.85
	sol.add_to_group("sol")
	add_child(sol)
	var mar := MeshInstance3D.new()
	var plano := PlaneMesh.new()
	plano.size = Vector2(LIMITE * 5, LIMITE * 5)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("3fb6d9")
	m.roughness = 0.4
	plano.material = m
	mar.mesh = plano
	mar.position.y = NIVEL_MAR
	mar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mar)


func _terreno() -> void:
	var corpo := StaticBody3D.new()
	corpo.name = "Terreno"
	corpo.set_meta("material", ImpactMaterial.TERRA)
	var forma := CollisionShape3D.new()
	var hm := HeightMapShape3D.new()
	hm.map_width = N
	hm.map_depth = N
	hm.map_data = _alturas
	forma.shape = hm
	forma.scale = Vector3(PASSO, 1.0, PASSO)
	corpo.add_child(forma)
	add_child(corpo)
	if not com_ambiente:
		return
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	var por_bloco := (N - 1) / BLOCOS
	for bj in BLOCOS:
		for bi in BLOCOS:
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			for j in range(bj * por_bloco, (bj + 1) * por_bloco):
				for i in range(bi * por_bloco, (bi + 1) * por_bloco):
					# mesma diagonal em todos os quadrados
					for v in [[i, j], [i + 1, j], [i + 1, j + 1], [i, j], [i + 1, j + 1], [i, j + 1]]:
						_vertice(st, v[0], v[1])
			st.generate_normals()
			var mi := MeshInstance3D.new()
			mi.mesh = st.commit()
			mi.material_override = mat
			mi.visibility_range_end = 420.0
			add_child(mi)


func _vertice(st: SurfaceTool, i: int, j: int) -> void:
	var h := _amostra(i, j)
	var x := -LIMITE + i * PASSO
	var z := -LIMITE + j * PASSO
	var inclinacao := absf(_amostra(i + 1, j) - _amostra(i - 1, j)) + absf(_amostra(i, j + 1) - _amostra(i, j - 1))
	var variacao := _ruido.get_noise_2d(x * 4.0, z * 4.0) * 0.06
	var cor := Color("6cc24a").lightened(variacao) if variacao > 0 else Color("6cc24a").darkened(-variacao)
	if h < 0.6:
		cor = Color("e8d49a")                     # praia
	elif h < 1.2:
		cor = Color("e8d49a").lerp(cor, (h - 0.6) / 0.6)
	if inclinacao > 3.2:
		cor = cor.lerp(Color("8f8a7e"), clampf((inclinacao - 3.2) / 2.0, 0.0, 0.8))   # encostas de pedra
	st.set_color(cor)
	st.add_vertex(Vector3(x, h, z))


func _bordas() -> void:
	for lado in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		var parede := StaticBody3D.new()
		var f := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = Vector3(2, 120, BORDA * 2) if lado.x != 0 else Vector3(BORDA * 2, 120, 2)
		f.shape = b
		parede.add_child(f)
		parede.position = lado * (BORDA + 1.0) + Vector3(0, 40, 0)
		add_child(parede)


# ---------------- construções ----------------

func _peca(nome: String, pos: Vector3, rot_y := 0.0) -> void:
	var xf := Transform3D(Basis(Vector3.UP, deg_to_rad(rot_y)), pos)
	_inst.place(B + nome + ".glb", xf, ImpactMaterial.from_asset(nome))


## Casa em grade de 4 m. origem = canto (-x, -z) do 1º cômodo no nível do chão;
## w × d cômodos, `andares` níveis (rampa interna no 1º cômodo da última fileira),
## porta: "n", "s", "l", "o" (cômodo do meio do lado). Registra baú e loot.
func _casa(origem: Vector3, w: int, d: int, andares: int, mat: String, porta := "s", bau := true, rot := 0) -> void:
	var o := origem
	var centro := o + Vector3(w * CELULA * 0.5, 0, d * CELULA * 0.5)
	_ocupado.append([Vector2(centro.x, centro.z), maxf(w, d) * CELULA * 0.75])
	var rampa_cel := Vector2i(0, d - 1)
	for nivel in andares:
		var y := o.y + nivel * CELULA
		for i in w:
			for j in d:
				var c := o + Vector3(i * CELULA + 2.0, nivel * CELULA, j * CELULA + 2.0)
				var buraco := nivel > 0 and Vector2i(i, j) == rampa_cel
				if not buraco:
					_peca("piso_" + mat, c)
		# rampa do nível anterior subindo para -Z até este nível
		if nivel > 0:
			var rc := o + Vector3(rampa_cel.x * CELULA + 2.0, (nivel - 1) * CELULA, rampa_cel.y * CELULA + 2.0)
			_peca("rampa_" + mat, rc)
		# paredes do perímetro
		var porta_i := w / 2
		var porta_j := d / 2
		for i in w:
			var x := o.x + i * CELULA + 2.0
			if not (nivel == 0 and porta == "n" and i == porta_i):
				_peca("parede_" + mat, Vector3(x, y, o.z))
			if not (nivel == 0 and porta == "s" and i == porta_i):
				_peca("parede_" + mat, Vector3(x, y, o.z + d * CELULA))
		for j in d:
			var z := o.z + j * CELULA + 2.0
			if not (nivel == 0 and porta == "o" and j == porta_j):
				_peca("parede_" + mat, Vector3(o.x, y, z), 90.0)
			if not (nivel == 0 and porta == "l" and j == porta_j):
				_peca("parede_" + mat, Vector3(o.x + w * CELULA, y, z), -90.0)
	# telhado
	for i in w:
		for j in d:
			_peca("teto_" + mat, o + Vector3(i * CELULA + 2.0, andares * CELULA, j * CELULA + 2.0))
	# baú no cômodo do fundo (longe da porta e da rampa) e loot nos outros
	var piso := o.y + 0.1
	if bau:
		var bc := Vector2i(w - 1, 0) if porta != "n" else Vector2i(w - 1, d - 1)
		_baus.append([Vector3(o.x + bc.x * CELULA + 2.0, piso, o.z + bc.y * CELULA + 2.0), 0.0 if porta != "n" else 180.0])
	_loot.append(Vector3(o.x + 2.0, piso, o.z + 2.0) if w * d > 1 else Vector3(o.x + 1.2, piso, o.z + 1.2))
	if andares > 1:
		_loot.append(Vector3(o.x + (w - 1) * CELULA + 2.0, o.y + CELULA + 0.1, o.z + 2.0))


## Torre de rampas em linha (rampa → piso → rampa → piso…), subindo para -Z.
func _torre(base: Vector3, niveis: int, mat: String) -> void:
	var z := base.z
	for n in niveis:
		_peca("rampa_" + mat, Vector3(base.x, base.y + n * CELULA, z))
		_peca("piso_" + mat, Vector3(base.x, base.y + (n + 1) * CELULA, z - CELULA))
		z -= CELULA * 2.0
	_ocupado.append([Vector2(base.x, base.z - niveis * CELULA), niveis * CELULA + 4.0])
	_loot.append(Vector3(base.x + 1.2, base.y + niveis * CELULA + 0.1, z + CELULA))


func _h(p: Vector2) -> float:
	return _altura_final(p.x, p.y)


func _poi_vila(p: Dictionary) -> void:
	var c: Vector2 = p["pos"]
	var y := _h(c)
	var casas := [[-30, -26, 2, 2, 1, "s"], [-4, -28, 2, 2, 2, "s"], [20, -24, 2, 2, 1, "o"], [-30, 6, 2, 2, 1, "l"],
			[18, 8, 2, 3, 2, "n"], [-8, 18, 2, 2, 1, "n"]]
	for k in casas:
		_casa(Vector3(c.x + k[0], y, c.y + k[1]), k[2], k[3], k[4], "madeira", k[5])
	for k in 6:
		var q := c + Vector2(_rng.randf_range(-20, 20), _rng.randf_range(-8, 6))
		_loot.append(Vector3(q.x, y, q.y))
	_baus.append([Vector3(c.x - 2, y, c.y - 4), 90.0])


func _poi_pedreira(p: Dictionary) -> void:
	var c: Vector2 = p["pos"]
	var y := _h(c)
	_torre(Vector3(c.x - 16, y, c.y + 14), 2, "pedra")
	_torre(Vector3(c.x + 16, y, c.y + 10), 3, "pedra")
	_casa(Vector3(c.x - 6, y, c.y - 26), 3, 2, 1, "pedra", "s")
	_casa(Vector3(c.x + 22, y, c.y - 20), 2, 2, 1, "pedra", "o")
	for k in 14:
		var ang := k * TAU / 14.0
		var q := c + Vector2(cos(ang), sin(ang)) * _rng.randf_range(24, 36)
		_inst.place(C + "pedra_01.glb", Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * _rng.randf_range(1.0, 2.2)),
				Vector3(q.x, _h(q), q.y)), ImpactMaterial.PEDRA)
	for k in 5:
		var q := c + Vector2(_rng.randf_range(-14, 14), _rng.randf_range(-14, 14))
		_loot.append(Vector3(q.x, y, q.y))
	_baus.append([Vector3(c.x, y, c.y + 2), 0.0])


func _poi_porto(p: Dictionary) -> void:
	var c: Vector2 = p["pos"]
	var y := _h(c)
	_casa(Vector3(c.x - 28, y, c.y - 26), 3, 2, 1, "metal", "s")
	_casa(Vector3(c.x + 4, y, c.y - 28), 2, 3, 2, "metal", "o")
	_casa(Vector3(c.x - 26, y, c.y + 8), 2, 2, 1, "metal", "n")
	_casa(Vector3(c.x + 6, y, c.y + 12), 3, 2, 1, "metal", "o")
	# "contêineres": caixas de metal fechadas de 1 cômodo empilhadas
	for k in 3:
		_casa(Vector3(c.x - 6, y + k * CELULA, c.y - 2), 1, 1, 1, "metal", "x", false)
	for k in 6:
		var q := c + Vector2(_rng.randf_range(-24, 24), _rng.randf_range(-6, 8))
		_loot.append(Vector3(q.x, y, q.y))


func _poi_fazenda(p: Dictionary) -> void:
	var c: Vector2 = p["pos"]
	var y := _h(c)
	_casa(Vector3(c.x - 10, y, c.y - 14), 3, 3, 2, "madeira", "s")      # celeiro
	_casa(Vector3(c.x + 14, y, c.y - 10), 2, 2, 1, "madeira", "o")
	_casa(Vector3(c.x - 30, y, c.y + 6), 2, 2, 1, "pedra", "l")
	# plantação: fileiras de arbustos
	for i in 6:
		for j in 4:
			var q := c + Vector2(4 + i * 4.0, 14 + j * 5.0)
			_inst.place(C + "arbusto_01.glb", Transform3D(Basis(), Vector3(q.x, _h(q), q.y)), ImpactMaterial.MADEIRA)
	_ocupado.append([c + Vector2(14, 22), 16.0])
	for k in 5:
		var q := c + Vector2(_rng.randf_range(-20, 20), _rng.randf_range(-4, 10))
		_loot.append(Vector3(q.x, y, q.y))


func _poi_mirante(p: Dictionary) -> void:
	var c: Vector2 = p["pos"]
	var y := _h(c)
	_torre(Vector3(c.x, y, c.y + 10), 3, "pedra")
	_casa(Vector3(c.x - 18, y, c.y - 4), 2, 2, 1, "pedra", "l")
	_baus.append([Vector3(c.x - 1.0, y + 3 * CELULA + 0.1, c.y + 10 - 5 * CELULA), 0.0])


func _poi_acampamento(p: Dictionary) -> void:
	var c: Vector2 = p["pos"]
	var y := _h(c)
	_casa(Vector3(c.x - 16, y, c.y - 12), 1, 2, 1, "madeira", "l")
	_casa(Vector3(c.x + 6, y, c.y - 14), 2, 1, 1, "madeira", "s")
	_casa(Vector3(c.x - 6, y, c.y + 8), 1, 1, 1, "madeira", "n", false)
	for k in 4:
		var q := c + Vector2(_rng.randf_range(-12, 12), _rng.randf_range(-6, 6))
		_loot.append(Vector3(q.x, y, q.y))
	_baus.append([Vector3(c.x + 2, y, c.y), 45.0])


func _cabana(p: Dictionary) -> void:
	var c: Vector2 = p["pos"]
	var mats := ["madeira", "madeira", "pedra", "metal"]
	var portas := ["n", "s", "l", "o"]
	_casa(Vector3(c.x - 2, p["h"], c.y - 2), 1, 1, 1, mats[_rng.randi() % mats.size()], portas[_rng.randi() % 4], _rng.randf() < 0.6)


## Loot e baús fora dos POIs (campo aberto, perto de árvores e pedras).
func _loot_espalhado() -> void:
	var feitos := 0
	var baus := 0
	var tentativas := 0
	while (feitos < 45 or baus < 10) and tentativas < 3000:
		tentativas += 1
		var q := Vector2(_rng.randf_range(-235, 235), _rng.randf_range(-235, 235))
		if _h(q) < 1.2 or _sobre_construcao(q):
			continue
		if baus < 10 and feitos % 4 == 0:
			_baus.append([Vector3(q.x, _h(q), q.y), _rng.randf() * 360.0])
			_ocupado.append([q, 2.5])
			baus += 1
		else:
			_loot.append(Vector3(q.x, _h(q), q.y))
		feitos += 1


func _vegetacao() -> void:
	var tipos := [["arvore_redonda_01", 70], ["pinheiro_01", 150], ["pedra_01", 55], ["arbusto_01", 90]]
	for t in tipos:
		var feitos := 0
		var tentativas := 0
		while feitos < int(t[1]) and tentativas < int(t[1]) * 8:
			tentativas += 1
			var q := Vector2(_rng.randf_range(-BORDA + 6, BORDA - 6), _rng.randf_range(-BORDA + 6, BORDA - 6))
			var h := _h(q)
			if h < 1.0 or _sobre_construcao(q):
				continue
			var escala := _rng.randf_range(0.85, 1.35)
			var mat := ImpactMaterial.PEDRA if t[0] == "pedra_01" else ImpactMaterial.MADEIRA
			_inst.place(C + t[0] + ".glb", Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * escala), Vector3(q.x, h - 0.05, q.y)), mat)
			feitos += 1


func _sobre_construcao(q: Vector2) -> bool:
	for o in _ocupado:
		if q.distance_to(o[0]) < float(o[1]) + 3.0:
			return true
	for p in POIS:
		if q.distance_to(p["pos"]) < float(p["raio"]) * 0.8:
			return true
	return false


## 24 pontos de início espalhados (campo aberto, longe uns dos outros).
func _spawns_partida() -> void:
	var tentativas := 0
	while _spawns.size() < 24 and tentativas < 2000:
		tentativas += 1
		var q := Vector2(_rng.randf_range(-230, 230), _rng.randf_range(-230, 230))
		if _h(q) < 1.0 or _sobre_construcao(q):
			continue
		var longe := true
		for s in _spawns:
			if Vector2(s.x, s.z).distance_to(q) < 60.0:
				longe = false
				break
		if longe:
			_spawns.append(Vector3(q.x, _h(q) + 0.3, q.y))
