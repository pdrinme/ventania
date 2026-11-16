class_name KitShowcase
extends Node3D
## Monta o "quarteirão" de demonstração do kit visual: chão, céu, sol,
## construções dos 3 materiais, árvores, pedras, baús e personagens.
## `densidade` repete o quarteirão em grade N x N (teste de carga).
## Sol, câmera e ambiente entram nos grupos que o autoload Settings ajusta.

const BLOCO := 40.0  # metros entre quarteirões repetidos

var densidade := 1
var animados: Array[AnimationPlayer] = []


func _ready() -> void:
	_ambiente()
	montar(densidade)


func montar(n: int) -> void:
	densidade = clampi(n, 1, 6)
	for c in get_children():
		if c.is_in_group("quarteirao"):
			c.queue_free()
	animados.clear()
	var meio := (densidade - 1) / 2.0
	for i in densidade:
		for j in densidade:
			var q := Node3D.new()
			q.add_to_group("quarteirao")
			q.position = Vector3((i - meio) * BLOCO, 0, (j - meio) * BLOCO)
			add_child(q)
			_quarteirao(q)


## Quantidade de quarteirões (para relatórios de benchmark).
func blocos() -> int:
	return densidade * densidade


func _ambiente() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("8fd3ff")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("b9c6ff")
	env.ambient_light_energy = 0.32
	env.fog_enabled = true
	env.fog_light_color = Color("cfe9ff")
	env.fog_density = 0.004
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

	var chao := MeshInstance3D.new()
	var plano := PlaneMesh.new()
	plano.size = Vector2(400, 400)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("6cc24a")
	mat.roughness = 1.0
	plano.material = mat
	chao.mesh = plano
	add_child(chao)


func _cena(pai: Node3D, caminho: String, pos: Vector3, rot_y := 0.0) -> Node3D:
	var n := (load(caminho) as PackedScene).instantiate() as Node3D
	n.position = pos
	n.rotation_degrees.y = rot_y
	pai.add_child(n)
	return n


func _anim(n: Node, nome: String, inicio: float) -> void:
	var lista := n.find_children("*", "AnimationPlayer", true, false)
	if lista.is_empty():
		return
	var ap := lista[0] as AnimationPlayer
	if ap.has_animation(nome):
		ap.play(nome)
		ap.seek(inicio, true)
		animados.append(ap)


func _quarteirao(q: Node3D) -> void:
	var b := "res://assets/construcoes/"
	_cena(q, b + "piso_madeira.glb", Vector3(-8, 0.11, -6))
	_cena(q, b + "parede_madeira.glb", Vector3(-8, 0, -8))
	_cena(q, b + "parede_madeira.glb", Vector3(-10, 0, -6), 90)
	_cena(q, b + "teto_madeira.glb", Vector3(-8, 4, -6))
	_cena(q, b + "rampa_madeira.glb", Vector3(-8, 0, -2))
	_cena(q, b + "rampa_pedra.glb", Vector3(0, 0, -6))
	_cena(q, b + "piso_pedra.glb", Vector3(0, 4, -10))
	_cena(q, b + "parede_pedra.glb", Vector3(0, 4, -12))
	_cena(q, b + "teto_pedra.glb", Vector3(-4, 0, -14))
	_cena(q, b + "piso_metal.glb", Vector3(8, 0.11, -6))
	_cena(q, b + "parede_metal.glb", Vector3(8, 0, -8))
	_cena(q, b + "parede_metal.glb", Vector3(10, 0, -6), -90)
	_cena(q, b + "teto_metal.glb", Vector3(8, 4, -6))
	_cena(q, b + "rampa_metal.glb", Vector3(8, 0, -2))

	var c := "res://assets/cenario/"
	_cena(q, c + "arvore_redonda_01.glb", Vector3(-13, 0, -1), 20)
	_cena(q, c + "pinheiro_01.glb", Vector3(-15, 0, -11))
	_cena(q, c + "pinheiro_01.glb", Vector3(15, 0, -14), 40)
	_cena(q, c + "arvore_redonda_01.glb", Vector3(14, 0, -1), 140)
	_cena(q, c + "pinheiro_01.glb", Vector3(5, 0, -17), 10)
	_cena(q, c + "pedra_01.glb", Vector3(6.5, 0, 1.5), 30)
	_cena(q, c + "arbusto_01.glb", Vector3(-4, 0, 2.5))
	_cena(q, c + "arbusto_01.glb", Vector3(9.5, 0, 3), 70)

	var bau := _cena(q, "res://assets/baus_coletaveis/bau_ventania_01.glb", Vector3(1.8, 0, 2.5), -20)
	_anim(bau, "abrir", 0.6)
	_cena(q, "res://assets/baus_coletaveis/bau_ventania_01.glb", Vector3(3.6, 0, 3.2), 15)

	var p := "res://assets/personagens/recruta_base_01.glb"
	_anim(_cena(q, p, Vector3(-0.6, 0, 4.2), 15), "idle", randf() * 2.0)
	_anim(_cena(q, p, Vector3(0.9, 0, 4.6), -10), "acenar", 0.0)
