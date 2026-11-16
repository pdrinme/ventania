class_name IlhaVentania
extends Mapa
## Mapa Battle Royale (Etapa 4, revisada): Ilha Ventania, ~600 × 600 m, gerada de
## forma DETERMINÍSTICA (mesma semente no servidor e no cliente).
##  - Silhueta: o litoral é uma função de raio por ângulo (harmônicos + ruído
##    periódico) com cabos, enseadas e penínsulas, e garante os 6 POIs em terra.
##    O relevo, a malha visual (só os quadrados acima do fundo do mar) e o limite
##    de movimento (anel de colisão na água rasa) seguem esse MESMO litoral.
##  - Geografia: colinas, Serra Cinza ao norte, morro do Mirante no centro, Vale do
##    Vento entre a Vila e a Fazenda, praias de larguras variadas.
##  - Estradas de asfalto e caminhos de terra ligando os POIs (o terreno é aplainado
##    sob elas); ruas com calçadas e faixas de pedestres nas cidades.
##  - Cidades planejadas com as peças da grade de construção (Etapa 5): portas e
##    janelas são ladrilhos editados, então tudo continua destrutível.
##  - Vegetação por regiões (bosques densos e campos abertos) e ambientação.
## Desempenho: terreno em blocos com corte por distância, peças e props em
## MultiMesh por região, colisão com formas compartilhadas.

const NOME := "ilha_ventania"
const SEMENTE := 20261116
const LIMITE := 300.0               # meia largura da grade do relevo
const PASSO := 3.0                  # resolução do relevo (m)
const N := 201                      # amostras por lado (= 2 * LIMITE / PASSO + 1)
const BLOCOS := 8                   # terreno visual em 8 × 8 blocos
const NIVEL_MAR := -1.2
const CELULA := 4.0                 # grade das construções (m)
const COSTA_MAX := 288.0
const BAUS := 37                    # números do Game Design
const PONTOS_LOOT := 102

const B := "res://assets/construcoes/"
const C := "res://assets/cenario/"

## Ladrilhos editados das paredes do mapa (ver Grade.tile_boxes: i + 3j, j de baixo para cima)
const M_PORTA := 511 & ~((1 << 1) | (1 << 4))
const M_JANELA := 511 & ~(1 << 4)
const M_VITRINE := 511 & ~((1 << 3) | (1 << 4) | (1 << 5))
const M_PORTAO := (1 << 6) | (1 << 7) | (1 << 8)

const POIS := [
	{"nome": "Vila Brisa", "pos": Vector2(-150, 55), "raio": 48.0, "tipo": "vila"},
	{"nome": "Pedreira Cinza", "pos": Vector2(40, -170), "raio": 40.0, "tipo": "pedreira"},
	{"nome": "Porto Ferrugem", "pos": Vector2(185, 45), "raio": 44.0, "tipo": "porto", "costa": 52.0},
	{"nome": "Fazenda Girassol", "pos": Vector2(-40, 170), "raio": 44.0, "tipo": "fazenda"},
	{"nome": "Mirante do Vento", "pos": Vector2(10, 5), "raio": 26.0, "tipo": "mirante"},
	{"nome": "Acampamento Coral", "pos": Vector2(-175, -150), "raio": 34.0, "tipo": "acampamento", "costa": 46.0},
]

## Rede de estradas: pontos de passagem (x, z). asfalto 8 m, rua 7 m (com calçadas), terra 4 m.
const ESTRADAS := [
	{"tipo": "asfalto", "pontos": [Vector2(-205, 55), Vector2(-150, 55), Vector2(-100, 58), Vector2(-40, 62), Vector2(10, 58), Vector2(80, 52), Vector2(140, 46), Vector2(185, 45), Vector2(212, 45)]},
	{"tipo": "asfalto", "pontos": [Vector2(10, 58), Vector2(10, 32)]},
	{"tipo": "asfalto", "pontos": [Vector2(10, 58), Vector2(2, 105), Vector2(-25, 140), Vector2(-40, 150)]},
	{"tipo": "asfalto", "pontos": [Vector2(10, -22), Vector2(22, -70), Vector2(35, -115), Vector2(40, -145)]},
	{"tipo": "rua", "pontos": [Vector2(-150, 13), Vector2(-150, 55), Vector2(-150, 97)]},
	{"tipo": "rua", "pontos": [Vector2(185, 45), Vector2(185, 8)]},
	{"tipo": "terra", "pontos": [Vector2(-152, 12), Vector2(-165, -40), Vector2(-178, -95), Vector2(-175, -128)]},
	{"tipo": "terra", "pontos": [Vector2(-20, 178), Vector2(40, 160), Vector2(110, 120), Vector2(160, 80), Vector2(180, 64)]},
	{"tipo": "terra", "pontos": [Vector2(62, -160), Vector2(110, -110), Vector2(150, -40), Vector2(182, 10)]},
	{"tipo": "terra", "pontos": [Vector2(-66, 166), Vector2(-110, 120), Vector2(-140, 88)]},
]
const LARGURA := {"asfalto": 8.0, "rua": 7.0, "terra": 4.0}

var _alturas := PackedFloat32Array()
var _dist_estrada := PackedFloat32Array()     # distância de cada amostra à estrada mais próxima
var _tipo_estrada := PackedByteArray()         # 0 asfalto/rua, 1 terra (para a cor do chão)
var _ruido := FastNoiseLite.new()
var _ruido_costa := FastNoiseLite.new()
var _ruido_bosque := FastNoiseLite.new()
var _pads: Array = []               # [{"pos": Vector2, "raio", "h"}]
var _estradas: Array = []           # [{"tipo","largura","pontos": PackedVector2Array,"perfil": PackedFloat32Array}]
var _baus: Array = []
var _loot: Array = []
var _cand := {"bau_casa": [], "bau_poi": [], "bau_natureza": [], "loot_casa": [], "loot_poi": [], "loot_natureza": []}
var _spawns: Array = []
var _rng := RandomNumberGenerator.new()
var _inst: KitInstancer
var _props: Array = []              # [caminho, Transform3D, material]
var _pecas: Array = []              # construções do mapa: {"tipo","cell","rot","material","mask"} (Etapa 5)
var _slots := {}
var _ocupado: Array = []            # [Vector2 centro, raio]
var _faixas: Array = []             # faixas de pedestres: [centro Vector2, direção Vector2, largura]
var _lagos_terra: Array = []        # chão de terra/rocha (plantação, pedreira): [Vector2, raio(, rocha)]
var _deficit_pois: Array = []       # [ângulo, metros] (garante POIs em terra)


func _init() -> void:
	_rng.seed = SEMENTE
	_ruido.seed = SEMENTE
	_ruido.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_ruido.frequency = 0.0055
	_ruido.fractal_octaves = 3
	_ruido_costa.seed = SEMENTE + 1
	_ruido_costa.frequency = 0.9
	_ruido_costa.fractal_octaves = 2
	_ruido_bosque.seed = SEMENTE + 2
	_ruido_bosque.frequency = 0.011
	_preparar_costa()
	_preparar_estradas()
	_planejar_pads()
	_gerar_alturas()
	# tudo é planejado aqui (sem nós): o servidor e o cliente têm as mesmas listas
	for p in POIS:
		call("_poi_" + p["tipo"], p)
	for p in _pads:
		if p.get("cabana", false):
			_cabana(p)
	_natureza_loot()
	_escolher_loot()
	_vegetacao()
	_spawns_partida()


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


func building_pieces() -> Array:
	return _pecas


func spawn_point(i: int) -> Vector3:
	# área de espera (antes da partida): ao redor do Mirante
	var ang := i * TAU / 16.0
	var p := Vector2(10, 5) + Vector2(cos(ang), sin(ang)) * (34.0 + (i % 3) * 4.0)
	return Vector3(p.x, ground_height(p.x, p.y) + 0.3, p.y)


func death_height() -> float:
	return -20.0


## Extensão do mapa (minimapa): a costa mais distante cabe em ±limit().
func limit() -> float:
	return COSTA_MAX + 8.0


func points_of_interest() -> Array:
	return POIS.map(func(p): return {"nome": p["nome"], "pos": Vector3(p["pos"].x, ground_height(p["pos"].x, p["pos"].y), p["pos"].y), "raio": p["raio"]})


func roads() -> Array:
	return _estradas


# ---------------- litoral ----------------

static func _ang_dif(a: float, b: float) -> float:
	return absf(wrapf(a - b, -PI, PI))


static func _lobo(a: float, centro: float, largura: float) -> float:
	var d := _ang_dif(a, centro) / largura
	return exp(-d * d)


func _raio_base(a: float) -> float:
	var r := 232.0 + 19.0 * sin(2.0 * a + 0.7) + 12.0 * sin(3.0 * a + 2.1) + 8.0 * sin(5.0 * a + 0.4) + 5.0 * sin(8.0 * a + 1.3)
	r += _ruido_costa.get_noise_2d(cos(a) * 3.0, sin(a) * 3.0) * 14.0       # periódico: sem emenda em ±180°
	# identidade do litoral: Cabo do Porto (leste), Enseada do Norte, Ponta Coral (sudoeste),
	# Baía da Fazenda (sul) e Península do Farol (nordeste)
	r -= 34.0 * _lobo(a, 0.22, 0.12)       # Baía do Porto: o porto fica junto ao mar
	r += 30.0 * _lobo(a, 0.62, 0.14) - 42.0 * _lobo(a, -1.62, 0.2) + 26.0 * _lobo(a, -2.42, 0.18) \
			- 30.0 * _lobo(a, 1.95, 0.13) + 34.0 * _lobo(a, -0.75, 0.1) \
			+ 30.0 * _lobo(a, PI, 0.11) - 28.0 * _lobo(a, 1.05, 0.11) - 26.0 * _lobo(a, 2.62, 0.1)   # Cabo Oeste, enseadas SE e SO
	return r


func _preparar_costa() -> void:
	for p in POIS:
		var pos: Vector2 = p["pos"]
		var ang := atan2(pos.y, pos.x)
		# POIs costeiros (Porto, Coral) ficam a poucos metros da praia; os outros, bem dentro
		var precisa := pos.length() + float(p.get("costa", float(p["raio"]) + 24.0))
		var falta := precisa - _raio_base(ang)
		if falta > 0.0 and pos.length() > 40.0:
			_deficit_pois.append([ang, falta])


## Distância do centro até a linha da costa na direção `a` (rad, atan2(z, x)).
func coast_radius(a: float) -> float:
	var r := _raio_base(a)
	for d in _deficit_pois:
		r += float(d[1]) * _lobo(a, d[0], 0.26)
	return clampf(r, 150.0, COSTA_MAX)


## Metros para dentro da costa (negativo = no mar).
func inland(x: float, z: float) -> float:
	return coast_radius(atan2(z, x)) - Vector2(x, z).length()


func is_land(x: float, z: float) -> bool:
	return ground_height(x, z) > 0.4


# ---------------- relevo ----------------

## Relevo do interior: colinas, Serra Cinza (norte), morro do Mirante, Vale do Vento.
func _interior(x: float, z: float) -> float:
	var h := _ruido.get_noise_2d(x, z) * 6.5 + 6.0
	h += 13.0 * exp(-pow(Vector2(x - 10, z - 5).length() / 50.0, 2.0))                     # Mirante
	h += 24.0 * exp(-pow((x - 95.0) / 55.0, 2.0) - pow((z + 150.0) / 40.0, 2.0))           # Serra Cinza
	h += 16.0 * exp(-pow((x + 40.0) / 50.0, 2.0) - pow((z + 205.0) / 30.0, 2.0))
	h += 10.0 * exp(-pow((x - 140.0) / 40.0, 2.0) - pow((z - 150.0) / 35.0, 2.0))          # colinas do sudeste
	# Vale do Vento: faixa baixa da Vila até a Fazenda
	var linha := Vector2(-150, 55).direction_to(Vector2(-40, 170))
	var rel := Vector2(x, z) - Vector2(-150, 55)
	var dist_linha := absf(rel.x * linha.y - rel.y * linha.x)
	h -= 4.5 * exp(-pow(dist_linha / 28.0, 2.0)) * clampf(1.0 - absf(rel.dot(linha) - 80.0) / 110.0, 0.0, 1.0)
	return h


## Relevo antes dos platôs e estradas: interior → praia → fundo do mar, pelo litoral real.
func _altura_bruta(x: float, z: float) -> float:
	var t := inland(x, z)
	if t < 0.0:
		return maxf(0.3 + t * 0.14, -14.0)
	var praia := 0.3 + t * 0.07
	var largura_praia := 10.0 + 14.0 * (_ruido_costa.get_noise_2d(x * 0.02, z * 0.02) * 0.5 + 0.5)
	return lerpf(praia, maxf(_interior(x, z), praia), smoothstep(largura_praia * 0.4, largura_praia + 14.0, t))


func _altura_pads(x: float, z: float) -> float:
	var h := _altura_bruta(x, z)
	for p in _pads:
		var d := Vector2(x, z).distance_to(p["pos"])
		var r: float = p["raio"]
		if d < r + 18.0:
			h = lerpf(h, p["h"], smoothstep(r + 18.0, r, d))
	return h


func _planejar_pads() -> void:
	for p in POIS:
		# platôs na altura da grade de construção (múltiplo de 4 m)
		var h := maxf(4.0, snappedf(_altura_bruta(p["pos"].x, p["pos"].y), CELULA))
		_pads.append({"pos": p["pos"], "raio": p["raio"], "h": h})
	var tentativas := 0
	var cabanas := 0
	while cabanas < 12 and tentativas < 600:
		tentativas += 1
		var q := Vector2(_rng.randf_range(-230, 230), _rng.randf_range(-230, 230))
		if _perto_de_pad(q, 30.0) or inland(q.x, q.y) < 30.0 or _dist_estrada_aprox(q) < 16.0:
			continue
		_pads.append({"pos": q, "raio": 9.0, "h": maxf(4.0, snappedf(_altura_bruta(q.x, q.y), CELULA)), "cabana": true})
		cabanas += 1


func _perto_de_pad(q: Vector2, folga: float) -> bool:
	for p in _pads:
		if q.distance_to(p["pos"]) < float(p["raio"]) + folga:
			return true
	return false


# ---------------- estradas ----------------

static func _catmull(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)


## Amostra a polilinha suavizada a cada ~2 m.
static func _amostrar(pontos: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in pontos.size() - 1:
		var p0: Vector2 = pontos[maxi(i - 1, 0)]
		var p1: Vector2 = pontos[i]
		var p2: Vector2 = pontos[i + 1]
		var p3: Vector2 = pontos[mini(i + 2, pontos.size() - 1)]
		var n := maxi(2, ceili(p1.distance_to(p2) / 2.0))
		for k in n:
			out.append(_catmull(p0, p1, p2, p3, float(k) / n))
	out.append(pontos[-1])
	return out


func _preparar_estradas() -> void:
	for e in ESTRADAS:
		_estradas.append({"tipo": e["tipo"], "largura": LARGURA[e["tipo"]], "pontos": _amostrar(e["pontos"])})


func _dist_estrada_aprox(q: Vector2) -> float:
	var melhor := 1e9
	for e in _estradas:
		for p: Vector2 in e["pontos"]:
			melhor = minf(melhor, q.distance_to(p) - float(e["largura"]) * 0.5)
	return melhor


func _gerar_alturas() -> void:
	_alturas.resize(N * N)
	_dist_estrada.resize(N * N)
	_tipo_estrada.resize(N * N)
	_dist_estrada.fill(1e6)
	for j in N:
		for i in N:
			_alturas[j * N + i] = _altura_pads(-LIMITE + i * PASSO, -LIMITE + j * PASSO)
	# perfil suave de cada estrada (média móvel do relevo com platôs) e aplainamento
	var h_estrada := PackedFloat32Array()
	h_estrada.resize(N * N)
	for e in _estradas:
		var pts: PackedVector2Array = e["pontos"]
		var bruto := PackedFloat32Array()
		for p in pts:
			bruto.append(_altura_pads(p.x, p.y))
		var perfil := PackedFloat32Array()
		for k in pts.size():
			var s := 0.0
			var n := 0
			for m in range(maxi(0, k - 6), mini(pts.size(), k + 7)):
				s += bruto[m]
				n += 1
			perfil.append(s / n)
		e["perfil"] = perfil
		var meia: float = e["largura"] * 0.5
		var alcance := meia + 7.0
		for k in pts.size():
			var p := pts[k]
			var i0 := clampi(floori((p.x - alcance + LIMITE) / PASSO), 0, N - 1)
			var i1 := clampi(ceili((p.x + alcance + LIMITE) / PASSO), 0, N - 1)
			var j0 := clampi(floori((p.y - alcance + LIMITE) / PASSO), 0, N - 1)
			var j1 := clampi(ceili((p.y + alcance + LIMITE) / PASSO), 0, N - 1)
			for j in range(j0, j1 + 1):
				for i in range(i0, i1 + 1):
					var d := Vector2(-LIMITE + i * PASSO, -LIMITE + j * PASSO).distance_to(p) - meia
					var idx := j * N + i
					if d < _dist_estrada[idx]:
						_dist_estrada[idx] = d
						h_estrada[idx] = perfil[k]
						_tipo_estrada[idx] = 1 if e["tipo"] == "terra" else 0
	for idx in N * N:
		var d := _dist_estrada[idx]
		if d < 7.0:
			var forca := 0.65 if _tipo_estrada[idx] == 1 else 1.0
			_alturas[idx] = lerpf(_alturas[idx], h_estrada[idx], smoothstep(7.0, 1.0, d) * forca)


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


func road_distance(x: float, z: float) -> float:
	var i := clampi(roundi((x + LIMITE) / PASSO), 0, N - 1)
	var j := clampi(roundi((z + LIMITE) / PASSO), 0, N - 1)
	return _dist_estrada[j * N + i]


func _h(p: Vector2) -> float:
	return _altura_pads(p.x, p.y)


# ---------------- montagem ----------------

func _ready() -> void:
	if com_ambiente:
		_ambiente()
	_terreno()
	_limite_costa()
	_inst = KitInstancer.new(self, com_ambiente)
	for pr in _props:
		_inst.place(pr[0], pr[1], pr[2])
	var grupos := _inst.build()
	if com_ambiente:
		_malhas_estradas()
	for dados_bau in _baus:
		var bau := (load("res://assets/baus_coletaveis/bau_ventania_01.glb") as PackedScene).instantiate() as Node3D
		bau.position = dados_bau[0]
		bau.rotation_degrees.y = dados_bau[1]
		bau.set_meta("material", ImpactMaterial.MADEIRA)
		add_child(bau)
		chest_nodes.append(bau)
	if OS.is_debug_build():
		print("[ilha] %d corpos, %d grupos visuais, %d peças de construção, %d baús, %d pontos de loot, %d props" % [
				_inst.corpos, grupos, _pecas.size(), _baus.size(), _loot.size(), _props.size()])


func _ambiente() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("8fd3ff")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("b9c6ff")
	env.ambient_light_energy = 0.32
	env.fog_enabled = true
	env.fog_light_color = Color("cfe9ff")
	env.fog_density = 0.0016
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
	plano.size = Vector2(LIMITE * 6, LIMITE * 6)
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
	var sh := load("res://world/ilha/terreno.gdshader") as Shader
	var mat := ShaderMaterial.new()
	mat.shader = sh
	var por_bloco := (N - 1) / BLOCOS
	for bj in BLOCOS:
		for bi in BLOCOS:
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			var algum := false
			for j in range(bj * por_bloco, (bj + 1) * por_bloco):
				for i in range(bi * por_bloco, (bi + 1) * por_bloco):
					# a malha acompanha o litoral: quadrados todos no fundo do mar não existem
					var maior := maxf(maxf(_amostra(i, j), _amostra(i + 1, j)), maxf(_amostra(i, j + 1), _amostra(i + 1, j + 1)))
					if maior < NIVEL_MAR - 2.2:
						continue
					algum = true
					for v in [[i, j], [i + 1, j], [i + 1, j + 1], [i, j], [i + 1, j + 1], [i, j + 1]]:
						_vertice(st, v[0], v[1])
			if not algum:
				continue
			st.generate_normals()
			var mi := MeshInstance3D.new()
			mi.mesh = st.commit()
			mi.material_override = mat
			mi.visibility_range_end = 450.0
			add_child(mi)


## Pesos dos materiais do chão no vértice: r = areia, g = rocha, b = terra.
func _vertice(st: SurfaceTool, i: int, j: int) -> void:
	var h := _amostra(i, j)
	var x := -LIMITE + i * PASSO
	var z := -LIMITE + j * PASSO
	var t := inland(x, z)
	var inclinacao := absf(_amostra(i + 1, j) - _amostra(i - 1, j)) + absf(_amostra(i, j + 1) - _amostra(i, j - 1))
	var areia := clampf(1.0 - (t - 5.0) / 10.0, 0.0, 1.0) * clampf(1.0 - (h - 1.0) / 2.5, 0.0, 1.0)
	var rocha := clampf((inclinacao - 3.4) / 2.5, 0.0, 0.85) + clampf((h - 22.0) / 6.0, 0.0, 0.7)
	var terra := 0.0
	var d := _dist_estrada[j * N + i]
	if _tipo_estrada[j * N + i] == 1:
		terra = clampf(1.0 - (d + 0.5) / 3.0, 0.0, 1.0)
	else:
		terra = clampf(1.0 - (d + 0.5) / 2.0, 0.0, 0.45)      # acostamento estreito junto ao asfalto
	for a in _lagos_terra:
		var dd := Vector2(x, z).distance_to(a[0])
		if dd < float(a[1]):
			if a.size() > 2:
				rocha = maxf(rocha, clampf((float(a[1]) - dd) / 8.0, 0.0, float(a[2])))
			else:
				terra = maxf(terra, clampf((float(a[1]) - dd) / 6.0, 0.0, 0.9))
	st.set_color(Color(areia, minf(rocha, 1.0 - areia), terra, 1.0))
	st.add_vertex(Vector3(x, h, z))


## Limite de movimento que segue o litoral: anel de caixas na água rasa (~9 m da costa).
func _limite_costa() -> void:
	var n := 160
	var corpo := StaticBody3D.new()
	corpo.name = "LimiteCosta"
	for k in n:
		var a0 := k * TAU / n
		var a1 := (k + 1) * TAU / n
		var p0 := Vector2(cos(a0), sin(a0)) * (coast_radius(a0) + 9.0)
		var p1 := Vector2(cos(a1), sin(a1)) * (coast_radius(a1) + 9.0)
		var cs := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = Vector3(p0.distance_to(p1) + 1.5, 140.0, 2.0)
		cs.shape = bx
		var meio := (p0 + p1) * 0.5
		var dir := p0.direction_to(p1)
		cs.transform = Transform3D(Basis(Vector3.UP, -atan2(dir.y, dir.x)), Vector3(meio.x, 50.0, meio.y))
		corpo.add_child(cs)
	add_child(corpo)


## Pistas (asfalto com faixas), calçadas com meio-fio e faixas de pedestres.
func _malhas_estradas() -> void:
	var sh := load("res://world/ilha/estrada.gdshader") as Shader
	var mats := {}
	for modo in [0, 1, 2, 3]:
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("modo", modo)
		mats[modo] = m
	var k := 0
	for e in _estradas:
		if e["tipo"] == "terra":
			continue              # caminhos de terra são cor do chão (sem malha)
		var modo := 0 if e["tipo"] == "asfalto" else 3
		var elev := 0.06 + 0.01 * k
		k += 1
		add_child(_faixa(e["pontos"], -e["largura"] * 0.5, e["largura"] * 0.5, elev, mats[modo]))
		# calçadas dentro das cidades
		for lado in [-1.0, 1.0]:
			for tr in _trechos_urbanos(e["pontos"]):
				var de: float = e["largura"] * 0.5 * lado
				var ate: float = (e["largura"] * 0.5 + 2.4) * lado
				add_child(_faixa(tr, minf(de, ate), maxf(de, ate), 0.2, mats[2], lado < 0.0))
	for f in _faixas:
		var c: Vector2 = f[0]
		var d: Vector2 = f[1]
		var pts := PackedVector2Array([c - d * 1.5, c + d * 1.5])
		add_child(_faixa(pts, -f[2] * 0.5, f[2] * 0.5, 0.12, mats[1]))


func _trechos_urbanos(pts: PackedVector2Array) -> Array:
	var out := []
	var atual := PackedVector2Array()
	for p in pts:
		var urbano := (p.distance_to(Vector2(-150, 55)) < 46.0 or p.distance_to(Vector2(185, 45)) < 34.0) \
				and not (p.distance_to(Vector2(-150, 55)) < 8.0)
		if urbano:
			atual.append(p)
		else:
			if atual.size() > 1:
				out.append(atual)
			atual = PackedVector2Array()
	if atual.size() > 1:
		out.append(atual)
	return out


## Fita ao longo de uma polilinha, de `de` a `ate` metros do eixo, `elev` acima do
## chão. UV.x atravessa (0..1); UV.y = metros ao longo. Calçadas (elev > 0,15)
## ganham a face vertical do meio-fio do lado da rua.
func _faixa(pts: PackedVector2Array, de: float, ate: float, elev: float, mat: Material, inverter := false) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ao_longo := 0.0
	var ant_a := Vector3.ZERO
	var ant_b := Vector3.ZERO
	var ua := 1.0 if inverter else 0.0
	var ub := 1.0 - ua
	for k in pts.size():
		var p := pts[k]
		var dir := (pts[mini(k + 1, pts.size() - 1)] - pts[maxi(k - 1, 0)]).normalized()
		var lado := Vector2(-dir.y, dir.x)
		var a := p + lado * de
		var b := p + lado * ate
		var va := Vector3(a.x, ground_height(a.x, a.y) + elev, a.y)
		var vb := Vector3(b.x, ground_height(b.x, b.y) + elev, b.y)
		if k > 0:
			var v0 := ao_longo
			ao_longo += p.distance_to(pts[k - 1])
			for v in [[ant_a, ua, v0], [vb, ub, ao_longo], [ant_b, ub, v0], [ant_a, ua, v0], [va, ua, ao_longo], [vb, ub, ao_longo]]:
				st.set_uv(Vector2(v[1], v[2]))
				st.add_vertex(v[0])
			if elev > 0.15:
				var interno_ant := ant_a if absf(de) < absf(ate) else ant_b
				var interno := va if absf(de) < absf(ate) else vb
				var baixo := Vector3(0, elev, 0)
				for v in [interno_ant, interno - baixo, interno_ant - baixo, interno_ant, interno, interno - baixo]:
					st.set_uv(Vector2(0.05, ao_longo))
					st.add_vertex(v)
		ant_a = va
		ant_b = vb
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = 380.0
	return mi


# ---------------- construções do mapa (peças da grade) ----------------

## Peça de construção do mapa: vira uma entrada da grade (destrutível, Etapa 5).
## pos/rot no formato do kit (centro do cômodo; parede no plano da borda); mask =
## ladrilhos (portas e janelas), -1 = inteira.
func _peca(nome: String, pos: Vector3, rot_y := 0.0, mask := -1) -> void:
	var partes := nome.split("_")
	var mat := Grade.MATERIAIS.find(partes[1])
	var tipo := Grade.PISO
	var cell: Vector3i
	var rot := 0
	match partes[0]:
		"parede":
			if is_zero_approx(fmod(absf(rot_y), 180.0)):
				tipo = Grade.PAREDE_X
				cell = Vector3i(roundi((pos.x - 2.0) / CELULA), roundi(pos.y / CELULA), roundi(pos.z / CELULA))
				rot = 0 if is_zero_approx(rot_y) else 2
			else:
				tipo = Grade.PAREDE_Z
				cell = Vector3i(roundi(pos.x / CELULA), roundi(pos.y / CELULA), roundi((pos.z - 2.0) / CELULA))
				rot = 1 if rot_y > 0.0 else 3
		_:
			tipo = {"piso": Grade.PISO, "rampa": Grade.RAMPA, "teto": Grade.TETO}[partes[0]]
			cell = Vector3i(roundi((pos.x - 2.0) / CELULA), roundi(pos.y / CELULA), roundi((pos.z - 2.0) / CELULA))
	var k := Grade.key(tipo, cell)
	if _slots.has(k):
		return
	_slots[k] = true
	var m := Grade.full_mask(tipo) if mask < 0 else mask
	_pecas.append({"tipo": tipo, "cell": cell, "rot": rot, "material": mat, "mask": m})


func _prop(nome: String, pos: Vector3, rot_y := 0.0, escala := 1.0, material := ImpactMaterial.NENHUM) -> void:
	var xf := Transform3D(Basis(Vector3.UP, deg_to_rad(rot_y)).scaled(Vector3.ONE * escala), pos)
	_props.append([C + nome + ".glb", xf, material])


func _prop_chao(nome: String, q: Vector2, rot_y := 0.0, escala := 1.0, material := ImpactMaterial.NENHUM) -> void:
	_prop(nome, Vector3(q.x, ground_height(q.x, q.y) - 0.03, q.y), rot_y, escala, material)


## Edifício em grade de 4 m. origem = canto (-x, -z) no nível do chão (alinhado à
## grade); w × d cômodos, `andares` níveis (rampa interna no cômodo (0, d-1)).
## porta: "n", "s", "l", "o" (lado da rua). estilo:
##   casa   — telhado em pirâmide, janelas na frente e nas laterais
##   loja   — vitrine larga na frente, terraço plano
##   predio — janelas em todos os andares, terraço plano
##   galpao — portão alto na frente, sem janelas, terraço plano
func _casa(origem: Vector3, w: int, d: int, andares: int, mat: String, porta := "s", estilo := "casa") -> void:
	var o := Vector3(snappedf(origem.x, CELULA), snappedf(origem.y, CELULA), snappedf(origem.z, CELULA))
	var centro := o + Vector3(w * CELULA * 0.5, 0, d * CELULA * 0.5)
	_ocupado.append([Vector2(centro.x, centro.z), maxf(w, d) * CELULA * 0.75])
	var rampa_cel := Vector2i(0, d - 1)
	var porta_i := w / 2
	var porta_j := d / 2
	for nivel in andares:
		var y := o.y + nivel * CELULA
		for i in w:
			for j in d:
				var c := o + Vector3(i * CELULA + 2.0, nivel * CELULA, j * CELULA + 2.0)
				if not (nivel > 0 and Vector2i(i, j) == rampa_cel):
					_peca("piso_" + mat, c)
		if nivel > 0:
			_peca("rampa_" + mat, o + Vector3(rampa_cel.x * CELULA + 2.0, (nivel - 1) * CELULA, rampa_cel.y * CELULA + 2.0))
		for i in w:
			var x := o.x + i * CELULA + 2.0
			_peca("parede_" + mat, Vector3(x, y, o.z), 0.0, _mascara(estilo, porta == "n", nivel, i == porta_i, i))
			_peca("parede_" + mat, Vector3(x, y, o.z + d * CELULA), 0.0, _mascara(estilo, porta == "s", nivel, i == porta_i, i))
		for j in d:
			var z := o.z + j * CELULA + 2.0
			_peca("parede_" + mat, Vector3(o.x, y, z), 90.0, _mascara(estilo, porta == "o", nivel, j == porta_j, j))
			_peca("parede_" + mat, Vector3(o.x + w * CELULA, y, z), -90.0, _mascara(estilo, porta == "l", nivel, j == porta_j, j))
	for i in w:
		for j in d:
			var topo := o + Vector3(i * CELULA + 2.0, andares * CELULA, j * CELULA + 2.0)
			_peca(("teto_" if estilo == "casa" else "piso_") + mat, topo)
	# baú no cômodo do fundo e loot dentro (candidatos; a escolha final fixa 37/102)
	var piso := o.y + 0.1
	var fundo := Vector2i(w - 1, 0) if porta != "n" else Vector2i(w - 1, d - 1)
	_cand["bau_casa"].append([Vector3(o.x + fundo.x * CELULA + 2.0, piso, o.z + fundo.y * CELULA + 2.0), 0.0 if porta != "n" else 180.0])
	_cand["loot_casa"].append(Vector3(o.x + 2.0, piso, o.z + 2.0) if w * d > 1 else Vector3(o.x + 1.2, piso, o.z + 1.2))
	if andares > 1:
		_cand["loot_casa"].append(Vector3(o.x + (w - 1) * CELULA + 2.0, o.y + CELULA + 0.1, o.z + 2.0))
	if w * d >= 6:
		_cand["loot_casa"].append(Vector3(o.x + (w - 1) * CELULA + 2.0, piso, o.z + (d - 1) * CELULA + 2.0))


## Ladrilhos da parede conforme o estilo (frente = lado da porta).
func _mascara(estilo: String, frente: bool, nivel: int, meio: bool, i: int) -> int:
	match estilo:
		"galpao":
			return M_PORTAO if frente and meio and nivel == 0 else -1
		"loja":
			if frente and nivel == 0:
				return M_PORTA if meio else M_VITRINE
			return M_JANELA if frente else -1
		"predio":
			if frente and meio and nivel == 0:
				return M_PORTA
			return M_JANELA if (frente or i % 2 == 0) else -1
	if frente and meio and nivel == 0:
		return M_PORTA
	if frente:
		return M_JANELA
	return M_JANELA if i % 2 == 1 else -1


## Torre de rampas em linha (rampa → piso → rampa → piso…), subindo para -Z.
func _torre(origem: Vector3, niveis: int, mat: String) -> Vector3:
	var base := Vector3(snappedf(origem.x - 2.0, CELULA) + 2.0, snappedf(origem.y, CELULA), snappedf(origem.z - 2.0, CELULA) + 2.0)
	var z := base.z
	for n in niveis:
		_peca("rampa_" + mat, Vector3(base.x, base.y + n * CELULA, z))
		_peca("piso_" + mat, Vector3(base.x, base.y + (n + 1) * CELULA, z - CELULA))
		z -= CELULA * 2.0
	_ocupado.append([Vector2(base.x, base.z - niveis * CELULA), niveis * CELULA + 4.0])
	_cand["loot_poi"].append(Vector3(base.x + 1.2, base.y + niveis * CELULA + 0.1, z + CELULA))
	return Vector3(base.x, base.y + niveis * CELULA + 0.1, z + CELULA)


## Postes alternando os dois lados de um trecho reto de rua.
func _postes(de: Vector2, ate: Vector2, afast: float, passo := 16.0) -> void:
	var dir := de.direction_to(ate)
	var lado := Vector2(-dir.y, dir.x)
	var n := floori(de.distance_to(ate) / passo)
	for k in n + 1:
		var p := de + dir * (k * passo)
		var s := 1.0 if k % 2 == 0 else -1.0
		var q := p + lado * afast * s
		_prop_chao("poste_01", q, rad_to_deg(atan2(lado.x * s, lado.y * s)), 1.0, ImpactMaterial.METAL)


# ---------------- pontos de interesse ----------------

## Vila Brisa: avenida leste-oeste e rua norte-sul cruzando no centro; quarteirões
## residenciais, lojas, um prédio de 3 andares e uma praça com bancos e postes.
func _poi_vila(p: Dictionary) -> void:
	var c: Vector2 = p["pos"]
	var y := _h(c)
	var cv := Vector3(c.x, y, c.y)
	# [dx, dz, w, d, andares, material, porta, estilo]  (frente para a rua mais próxima)
	var edificios := [
		[8, -20, 2, 2, 2, "madeira", "s", "casa"], [20, -20, 3, 2, 1, "pedra", "s", "loja"], [36, -20, 2, 2, 1, "madeira", "s", "casa"],
		[8, -40, 2, 2, 1, "madeira", "o", "casa"],
		[-16, -20, 2, 2, 1, "madeira", "s", "casa"], [-32, -20, 2, 2, 2, "pedra", "s", "casa"], [-16, -40, 2, 2, 1, "madeira", "l", "casa"],
		[8, 8, 2, 2, 1, "madeira", "n", "loja"], [20, 8, 3, 3, 3, "pedra", "n", "predio"], [8, 24, 2, 2, 1, "madeira", "o", "casa"],
		[-44, 8, 2, 2, 1, "madeira", "n", "casa"], [-16, 28, 2, 2, 2, "madeira", "l", "casa"],
	]
	for e in edificios:
		_casa(cv + Vector3(e[0], 0, e[1]), e[2], e[3], e[4], e[5], e[6], e[7])
	# praça no quarteirão sudoeste
	var praca := c + Vector2(-22, 15)
	for k in 4:
		var ang := k * PI * 0.5
		_prop_chao("banco_01", praca + Vector2(cos(ang), sin(ang)) * 5.0, rad_to_deg(-ang) - 90.0, 1.0, ImpactMaterial.MADEIRA)
	_prop_chao("arvore_redonda_01", praca, 0.0, 1.1, ImpactMaterial.MADEIRA)
	_prop_chao("lixeira_01", praca + Vector2(6.5, 6.5), 0.0, 1.0, ImpactMaterial.METAL)
	_prop_chao("poste_01", praca + Vector2(-6.5, -6.5), 45.0, 1.0, ImpactMaterial.METAL)
	_ocupado.append([praca, 8.0])
	_cand["bau_poi"].append([Vector3(praca.x + 3.0, y, praca.y - 3.0), 45.0])
	_cand["loot_poi"].append(Vector3(praca.x - 2.5, y, praca.y + 2.5))
	# postes e placas ao longo das ruas
	_postes(c + Vector2(-44, 0), c + Vector2(44, 0), 6.6)
	_postes(c + Vector2(0, -40), c + Vector2(0, 40), 6.1)
	_prop_chao("placa_01", c + Vector2(-50, -7), 90.0, 1.0, ImpactMaterial.METAL)
	_prop_chao("placa_01", c + Vector2(50, 7), -90.0, 1.0, ImpactMaterial.METAL)
	# faixas de pedestres nas quatro saídas do cruzamento
	for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		_faixas.append([c + d * 7.5, Vector2(-d.y, d.x), 3.0])
	for k in 6:
		var q := c + Vector2(_rng.randf_range(-36, 36), [-5.5, 5.5][k % 2])
		_cand["loot_poi"].append(Vector3(q.x, y, q.y))


## Pedreira Cinza: cava de pedra com encostas rochosas, carrinhos e trilhos, torres
## de pedra (plataformas), escritório e galpão de metal.
func _poi_pedreira(p: Dictionary) -> void:
	var c: Vector2 = p["pos"]
	var y := _h(c)
	_lagos_terra.append([c, 46.0, 0.9])     # chão de rocha (pesos de rocha no terreno)
	_torre(Vector3(c.x - 18, y, c.y + 14), 2, "pedra")
	_torre(Vector3(c.x + 18, y, c.y + 12), 3, "pedra")
	_casa(Vector3(c.x - 8, y, c.y - 28), 3, 2, 1, "pedra", "s", "predio")
	_casa(Vector3(c.x + 20, y, c.y - 24), 3, 2, 1, "metal", "o", "galpao")
	for k in 18:
		var ang := k * TAU / 18.0 + _rng.randf_range(-0.1, 0.1)
		var q := c + Vector2(cos(ang), sin(ang)) * _rng.randf_range(26, 40)
		_prop("pedra_01", Vector3(q.x, _h(q) - 0.2, q.y), _rng.randf() * 360.0, _rng.randf_range(1.2, 2.6), ImpactMaterial.PEDRA)
	for k in 4:
		_prop_chao("carrinho_01", c + Vector2(-14 + k * 9, 2), 90.0, 1.0, ImpactMaterial.METAL)
	_ocupado.append([c + Vector2(0, 2), 12.0])
	_cand["bau_poi"].append([Vector3(c.x + 2, y, c.y + 6), 0.0])
	for k in 5:
		var q := c + Vector2(_rng.randf_range(-16, 16), _rng.randf_range(6, 12))
		_cand["loot_poi"].append(Vector3(q.x, y, q.y))


## Porto Ferrugem: galpões de metal, pátio de contêineres empilhados, rua de acesso.
func _poi_porto(p: Dictionary) -> void:
	var c: Vector2 = p["pos"]
	var y := _h(c)
	_casa(Vector3(c.x - 36, y, c.y - 30), 3, 3, 1, "metal", "s", "galpao")
	_casa(Vector3(c.x - 36, y, c.y + 8), 3, 2, 1, "metal", "n", "galpao")
	_casa(Vector3(c.x + 8, y, c.y - 32), 2, 3, 2, "metal", "o", "predio")
	_casa(Vector3(c.x - 12, y, c.y + 12), 2, 2, 1, "pedra", "n", "loja")
	var cores := ["conteiner_01", "conteiner_02", "conteiner_03"]
	# contêineres de 6 × 2,4 m em fileiras (corredores de 2,6 m entre as fileiras)
	for fila in 4:
		for k in 3:
			var q := c + Vector2(17 + k * 7.0, 8 + fila * 5.0)
			_prop(cores[(fila + k) % 3], Vector3(q.x, y, q.y), 0.0, 1.0, ImpactMaterial.METAL)
			if (fila + k) % 2 == 0:
				_prop(cores[(fila + k + 1) % 3], Vector3(q.x, y + 2.6, q.y), 0.0, 1.0, ImpactMaterial.METAL)
	_ocupado.append([c + Vector2(21, 14), 14.0])
	_postes(c + Vector2(-30, 0), c + Vector2(26, 0), 6.6)
	_prop_chao("placa_01", c + Vector2(-40, 7), -90.0, 1.0, ImpactMaterial.METAL)
	_faixas.append([c + Vector2(0, -6.5), Vector2(1, 0), 3.0])
	_cand["bau_poi"].append([Vector3(c.x + 20.5, y, c.y + 10.5), 0.0])
	_cand["bau_poi"].append([Vector3(c.x + 27.5, y, c.y + 20.5), 0.0])
	for k in 7:
		var q := c + Vector2(_rng.randf_range(-28, 30), [-5.0, 4.5, 15.5][k % 3])
		_cand["loot_poi"].append(Vector3(q.x, y, q.y))


## Fazenda Girassol: celeiro de 2 andares, casa da fazenda, silo, plantação de
## girassóis cercada e caminhos de terra.
func _poi_fazenda(p: Dictionary) -> void:
	var c: Vector2 = p["pos"]
	var y := _h(c)
	_casa(Vector3(c.x - 12, y, c.y - 20), 3, 3, 2, "madeira", "s", "galpao")
	_casa(Vector3(c.x + 14, y, c.y - 14), 2, 2, 1, "madeira", "o", "casa")
	_casa(Vector3(c.x - 32, y, c.y + 2), 2, 2, 1, "pedra", "l", "casa")
	_prop_chao("silo_01", c + Vector2(-20, -8), 0.0, 1.0, ImpactMaterial.METAL)
	_ocupado.append([c + Vector2(-20, -8), 4.0])
	var campo := c + Vector2(4, 16)
	_lagos_terra.append([campo + Vector2(12, 10), 16.0])
	for i in 10:
		for j in 7:
			var q := campo + Vector2(i * 2.6, j * 3.0) + Vector2(_rng.randf_range(-0.3, 0.3), 0)
			_prop_chao("girassol_01", q, _rng.randf_range(-20, 20), _rng.randf_range(0.9, 1.15))
	for k in 7:
		_prop_chao("cerca_01", campo + Vector2(k * 4.0, -2.5), 0.0, 1.0, ImpactMaterial.MADEIRA)
		_prop_chao("cerca_01", campo + Vector2(k * 4.0, 21.5), 0.0, 1.0, ImpactMaterial.MADEIRA)
	_ocupado.append([campo + Vector2(12, 10), 16.0])
	_cand["bau_poi"].append([Vector3(c.x + 4, y, c.y - 2), 0.0])
	for k in 5:
		var q := c + Vector2(_rng.randf_range(-24, 0), _rng.randf_range(-2, 6))
		_cand["loot_poi"].append(Vector3(q.x, y, q.y))


## Mirante do Vento: torre de pedra no topo do morro (referência visual), casa de
## pedra, mirante com bancos e placa.
func _poi_mirante(p: Dictionary) -> void:
	var c: Vector2 = p["pos"]
	var y := _h(c)
	var topo := _torre(Vector3(c.x, y, c.y + 10), 3, "pedra")
	_casa(Vector3(c.x - 20, y, c.y - 4), 2, 2, 1, "pedra", "l", "casa")
	_cand["bau_poi"].append([topo + Vector3(-1.0, 0, 0), 0.0])
	for k in 3:
		_prop_chao("banco_01", c + Vector2(-12 + k * 12, 20), 180.0, 1.0, ImpactMaterial.MADEIRA)
	_prop_chao("placa_01", c + Vector2(6, 24), 0.0, 1.0, ImpactMaterial.METAL)
	_prop_chao("poste_01", c + Vector2(-6, 24), 0.0, 1.0, ImpactMaterial.METAL)
	for k in 3:
		var q := c + Vector2(_rng.randf_range(-14, 14), _rng.randf_range(14, 20))
		_cand["loot_poi"].append(Vector3(q.x, y, q.y))


## Acampamento Coral: cabanas e barracas numa clareira, fogueira com troncos,
## caminho de terra e bosque em volta.
func _poi_acampamento(p: Dictionary) -> void:
	var c: Vector2 = p["pos"]
	var y := _h(c)
	_lagos_terra.append([c, 14.0])
	_casa(Vector3(c.x - 18, y, c.y - 14), 1, 2, 1, "madeira", "l", "casa")
	_casa(Vector3(c.x + 8, y, c.y - 16), 2, 1, 1, "madeira", "s", "casa")
	_casa(Vector3(c.x - 6, y, c.y + 10), 1, 1, 1, "madeira", "n", "casa")
	for k in 5:
		var ang := k * TAU / 5.0 + 0.4
		var q := c + Vector2(cos(ang), sin(ang)) * 17.0
		_prop_chao("tenda_01", q, rad_to_deg(-ang), 1.0, ImpactMaterial.MADEIRA)
		_ocupado.append([q, 2.5])
	for k in 4:
		var ang := k * TAU / 4.0
		_prop_chao("tronco_01", c + Vector2(cos(ang), sin(ang)) * 3.2, rad_to_deg(-ang) + 90.0, 0.8, ImpactMaterial.MADEIRA)
	_ocupado.append([c, 5.0])
	_cand["bau_poi"].append([Vector3(c.x + 2, y, c.y + 6), 45.0])
	for k in 4:
		var q := c + Vector2(_rng.randf_range(-12, 12), [-6.0, 6.5][k % 2])
		_cand["loot_poi"].append(Vector3(q.x, y, q.y))


func _cabana(p: Dictionary) -> void:
	var c: Vector2 = p["pos"]
	var mats := ["madeira", "madeira", "pedra", "metal"]
	var portas := ["n", "s", "l", "o"]
	_casa(Vector3(c.x - 2, p["h"], c.y - 2), 1, 1, 1, mats[_rng.randi() % mats.size()], portas[_rng.randi() % 4], "casa")


# ---------------- loot ----------------

## Candidatos em regiões naturais (campo aberto, perto de árvores, rochas, caminhos).
func _natureza_loot() -> void:
	var tentativas := 0
	while (_cand["loot_natureza"].size() < 60 or _cand["bau_natureza"].size() < 16) and tentativas < 4000:
		tentativas += 1
		var q := Vector2(_rng.randf_range(-250, 250), _rng.randf_range(-250, 250))
		if inland(q.x, q.y) < 14.0 or _h(q) < 1.2 or _sobre_construcao(q) or road_distance(q.x, q.y) < 3.0:
			continue
		var pos := Vector3(q.x, ground_height(q.x, q.y), q.y)
		if _cand["bau_natureza"].size() < 16 and tentativas % 3 == 0:
			_cand["bau_natureza"].append([pos, _rng.randf() * 360.0])
			_ocupado.append([q, 2.5])
		else:
			_cand["loot_natureza"].append(pos)


## Fixa exatamente 37 baús e 102 pontos de loot (Game Design), com cotas por região
## (dentro de construções, áreas externas dos POIs e natureza), de forma determinística.
func _escolher_loot() -> void:
	for k in _cand:
		var l: Array = _cand[k]
		for i in range(l.size() - 1, 0, -1):
			var j := _rng.randi_range(0, i)
			var t = l[i]
			l[i] = l[j]
			l[j] = t
	_baus = _pegar(["bau_casa", "bau_poi", "bau_natureza"], [20, 7, 10], BAUS)
	_loot = _pegar(["loot_casa", "loot_poi", "loot_natureza"], [42, 30, 30], PONTOS_LOOT)


func _pegar(chaves: Array, cotas: Array, total: int) -> Array:
	var out := []
	var sobras := []
	for i in chaves.size():
		var l: Array = _cand[chaves[i]]
		out.append_array(l.slice(0, cotas[i]))
		sobras.append_array(l.slice(cotas[i]))
	while out.size() < total and not sobras.is_empty():
		out.append(sobras.pop_front())
	return out.slice(0, total)


# ---------------- vegetação ----------------

func _sobre_construcao(q: Vector2) -> bool:
	for o in _ocupado:
		if q.distance_to(o[0]) < float(o[1]) + 3.0:
			return true
	for p in POIS:
		if q.distance_to(p["pos"]) < float(p["raio"]) * 0.8:
			return true
	return false


## Bosques densos (ruído) e campos abertos; pinheiros nas partes altas, árvores
## redondas nos vales; arbustos na costa; rochas nas encostas; troncos nos bosques.
func _vegetacao() -> void:
	var feitos := {"arvore": 0, "rocha": 0, "arbusto": 0, "planta": 0, "tronco": 0}
	var metas := {"arvore": 330, "rocha": 70, "arbusto": 150, "planta": 140, "tronco": 18}
	var tentativas := 0
	while tentativas < 30000:
		tentativas += 1
		if feitos.keys().all(func(k): return feitos[k] >= metas[k]):
			break
		var q := Vector2(_rng.randf_range(-COSTA_MAX, COSTA_MAX), _rng.randf_range(-COSTA_MAX, COSTA_MAX))
		var h := _h(q)
		var dentro := inland(q.x, q.y)
		if dentro < 2.0 or h < 0.6 or _sobre_construcao(q) or road_distance(q.x, q.y) < 4.0:
			continue
		var bosque := _ruido_bosque.get_noise_2d(q.x, q.y)
		var pos := Vector3(q.x, ground_height(q.x, q.y) - 0.05, q.y)
		var giro := _rng.randf() * 360.0
		if dentro < 16.0:
			if feitos["arbusto"] < metas["arbusto"] and _rng.randf() < 0.5:
				_prop("arbusto_01", pos, giro, _rng.randf_range(0.8, 1.2), ImpactMaterial.MADEIRA)
				feitos["arbusto"] += 1
			elif feitos["rocha"] < metas["rocha"] and _rng.randf() < 0.15:
				_prop("pedra_01", pos, giro, _rng.randf_range(0.7, 1.4), ImpactMaterial.PEDRA)
				feitos["rocha"] += 1
			continue
		if bosque > 0.12:
			if feitos["arvore"] < metas["arvore"]:
				_prop("pinheiro_01" if h > 12.0 or _rng.randf() < 0.45 else "arvore_redonda_01", pos, giro, _rng.randf_range(0.85, 1.35), ImpactMaterial.MADEIRA)
				feitos["arvore"] += 1
			elif feitos["tronco"] < metas["tronco"] and _rng.randf() < 0.1:
				_prop("tronco_01", pos + Vector3(0, 0.05, 0), giro, 1.0, ImpactMaterial.MADEIRA)
				feitos["tronco"] += 1
			continue
		var r := _rng.randf()
		if r < 0.06 and feitos["arvore"] < metas["arvore"]:
			_prop("arvore_redonda_01", pos, giro, _rng.randf_range(0.9, 1.3), ImpactMaterial.MADEIRA)
			feitos["arvore"] += 1
		elif r < 0.4 and feitos["planta"] < metas["planta"]:
			_prop("arbusto_01", pos, giro, _rng.randf_range(0.35, 0.6), ImpactMaterial.MADEIRA)   # plantas baixas
			feitos["planta"] += 1
		elif r < 0.55 and feitos["rocha"] < metas["rocha"] and h > 8.0:
			_prop("pedra_01", pos, giro, _rng.randf_range(0.8, 1.8), ImpactMaterial.PEDRA)
			feitos["rocha"] += 1
		elif r < 0.7 and feitos["arbusto"] < metas["arbusto"]:
			_prop("arbusto_01", pos, giro, _rng.randf_range(0.8, 1.2), ImpactMaterial.MADEIRA)
			feitos["arbusto"] += 1


## 24 pontos de início espalhados (reserva; a entrada normal é pelo Ônibus de Batalha).
func _spawns_partida() -> void:
	var tentativas := 0
	while _spawns.size() < 24 and tentativas < 3000:
		tentativas += 1
		var q := Vector2(_rng.randf_range(-230, 230), _rng.randf_range(-230, 230))
		if inland(q.x, q.y) < 20.0 or _sobre_construcao(q):
			continue
		var longe := true
		for s in _spawns:
			if Vector2(s.x, s.z).distance_to(q) < 55.0:
				longe = false
				break
		if longe:
			_spawns.append(Vector3(q.x, _h(q) + 0.3, q.y))
