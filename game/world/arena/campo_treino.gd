class_name CampoTreino
extends Node3D
## Mapa de teste da Etapa 2: chão, construções do kit (com colisão) e props.
## O mesmo mapa roda no servidor (colisão) e no cliente (visual + colisão para predição).

const NOME := "campo_treino"
const LIMITE := 110.0
const ALTURA_MORTE := -30.0

var com_ambiente := true   # céu/sol/neblina só no cliente
var chest_nodes: Array[Node3D] = []

## Baús: [posição, rotação Y]. O índice é o id do baú na rede.
## Alturas: piso no nível N tem o topo em N + 0,10 (padrão da grade).
const CHESTS := [
	[Vector3(-16, 0.1, -10.6), 0.0], [Vector3(0, 8.1, -26.6), 0.0], [Vector3(16, 4.1, -10), 90.0],
	[Vector3(-7, 0, 3), 30.0], [Vector3(10, 0, 5), -40.0], [Vector3(-34, 0, -28), 0.0], [Vector3(36, 0, 30), 180.0],
]
## Pontos de loot no chão (sorteados no início da partida).
const LOOT_POINTS := [
	Vector3(-16, 0.1, -9), Vector3(0, 4.1, -18), Vector3(16, 0.1, -9), Vector3(16, 4.1, -11.2),
	Vector3(-16, 1.6, 6), Vector3(-24, 0, 12), Vector3(24, 0, 12), Vector3(-26, 0, -18), Vector3(26, 0, -20),
	Vector3(0, 0, 22), Vector3(-10, 0, 24), Vector3(12, 0, 24), Vector3(-40, 0, 0), Vector3(40, 0, 0),
	Vector3(0, 0, -40), Vector3(-3, 0, 8), Vector3(3, 0, 8),
]
## Bonecos de treino (alvos que não revidam).
const DUMMIES := [Vector3(-5, 0, -2), Vector3(0, 0, -4), Vector3(5, 0, -2)]


func _ready() -> void:
	if com_ambiente:
		_ambiente()
	_chao()
	_construcoes()
	_props()


func spawn_point(i: int) -> Vector3:
	var ang := i * TAU / 8.0
	return Vector3(cos(ang) * 4.0, 0.2, 10.0 + sin(ang) * 4.0)


func _ambiente() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("8fd3ff")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("b9c6ff")
	env.ambient_light_energy = 0.32
	env.fog_light_color = Color("cfe9ff")
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


func _chao() -> void:
	var corpo := StaticBody3D.new()
	corpo.name = "Chao"
	corpo.set_meta("material", ImpactMaterial.TERRA)
	var forma := CollisionShape3D.new()
	var caixa := BoxShape3D.new()
	caixa.size = Vector3(LIMITE * 2.2, 2.0, LIMITE * 2.2)
	forma.shape = caixa
	forma.position.y = -1.0
	corpo.add_child(forma)
	add_child(corpo)
	if com_ambiente:
		var malha := MeshInstance3D.new()
		var plano := PlaneMesh.new()
		plano.size = Vector2(LIMITE * 2.2, LIMITE * 2.2)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color("6cc24a")
		mat.roughness = 1.0
		plano.material = mat
		malha.mesh = plano
		add_child(malha)
	# bordas invisíveis
	for lado in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		var parede := StaticBody3D.new()
		var f := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = Vector3(2, 60, LIMITE * 2) if lado.x != 0 else Vector3(LIMITE * 2, 60, 2)
		f.shape = b
		parede.add_child(f)
		parede.position = lado * LIMITE + Vector3(0, 30, 0)
		add_child(parede)


func _peca(caminho: String, pos: Vector3, rot_y := 0.0) -> void:
	var n := (load(caminho) as PackedScene).instantiate() as Node3D
	n.position = pos
	n.rotation_degrees.y = rot_y
	n.set_meta("material", ImpactMaterial.from_asset(caminho.get_file().get_basename()))
	add_child(n)


func _construcoes() -> void:
	var b := "res://assets/construcoes/"
	# cabana de madeira (frente aberta)
	_peca(b + "piso_madeira.glb", Vector3(-16, 0, -10))
	_peca(b + "parede_madeira.glb", Vector3(-16, 0, -12))
	_peca(b + "parede_madeira.glb", Vector3(-18, 0, -10), 90)
	_peca(b + "parede_madeira.glb", Vector3(-14, 0, -10), -90)
	_peca(b + "teto_madeira.glb", Vector3(-16, 4, -10))
	# torre de pedra: rampa -> piso a 4 m -> rampa -> piso a 8 m
	_peca(b + "rampa_pedra.glb", Vector3(0, 0, -14))
	_peca(b + "piso_pedra.glb", Vector3(0, 4, -18))
	_peca(b + "rampa_pedra.glb", Vector3(0, 4, -22))
	_peca(b + "piso_pedra.glb", Vector3(0, 8, -26))
	_peca(b + "parede_pedra.glb", Vector3(0, 8, -28))
	_peca(b + "parede_pedra.glb", Vector3(-2, 4, -18), 90)
	# caixa de metal com rampa até o telhado
	_peca(b + "piso_metal.glb", Vector3(16, 0, -10))
	_peca(b + "parede_metal.glb", Vector3(16, 0, -12))
	_peca(b + "parede_metal.glb", Vector3(18, 0, -10), -90)
	_peca(b + "parede_metal.glb", Vector3(14, 0, -10), 90)
	_peca(b + "piso_metal.glb", Vector3(16, 4, -10))
	_peca(b + "rampa_metal.glb", Vector3(16, 0, -6))
	# túnel baixo: placa de baixo a 1,4 m (agachado 1,15 m passa; em pé 1,8 m não)
	_peca(b + "piso_madeira.glb", Vector3(-16, 1.5, 4))
	_peca(b + "piso_madeira.glb", Vector3(-16, 1.5, 8))


func _props() -> void:
	var c := "res://assets/cenario/"
	var rnd := RandomNumberGenerator.new()
	rnd.seed = 42  # mesma posição no servidor e no cliente
	var tipos := ["arvore_redonda_01", "pinheiro_01", "pinheiro_01", "pedra_01", "arbusto_01"]
	for i in 40:
		var ang := rnd.randf() * TAU
		var dist := rnd.randf_range(32.0, LIMITE - 8.0)
		_peca(c + tipos[i % tipos.size()] + ".glb", Vector3(cos(ang) * dist, 0, sin(ang) * dist), rnd.randf() * 360.0)
	for dados_bau in CHESTS:
		var bau := (load("res://assets/baus_coletaveis/bau_ventania_01.glb") as PackedScene).instantiate() as Node3D
		bau.position = dados_bau[0]
		bau.rotation_degrees.y = dados_bau[1]
		bau.set_meta("material", ImpactMaterial.MADEIRA)
		add_child(bau)
		chest_nodes.append(bau)
