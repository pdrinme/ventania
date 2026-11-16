extends SceneTree
## Monta uma vitrine com o kit visual, verifica a importação e salva uma imagem.
## Precisa de janela/GPU (no Linux sem tela: xvfb-run). Não use --headless.
##
## Uso:
##   godot --path game --rendering-driver opengl3 --resolution 1280x720 \
##         -s res://tests/vitrine_kit.gd -- <saida.png> [perfil]
##   perfil: performance | quality (padrão: quality)

const MAT_COMPARTILHADO := "res://assets/texturas_materiais/M_paleta_ventania.tres"
var falhas := 0


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var saida := args[0] if args.size() > 0 else "user://vitrine_kit.png"
	var perfil := args[1] if args.size() > 1 else "quality"
	_montar(perfil)
	for i in 12:
		await process_frame
	var img := root.get_texture().get_image()
	var err := img.save_png(saida)
	print("VITRINE salva=%s err=%d perfil=%s draw_calls=%d objetos=%d prims=%d" % [saida, err, perfil,
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])
	print("VITRINE_FALHAS=%d" % falhas)
	quit(1 if falhas or err != OK else 0)


func _cena(caminho: String, pos: Vector3, rot_y := 0.0) -> Node3D:
	var n := (load(caminho) as PackedScene).instantiate() as Node3D
	n.position = pos
	n.rotation_degrees.y = rot_y
	root.add_child(n)
	_checar_material(caminho, n)
	return n


func _checar_material(caminho: String, n: Node) -> void:
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m: Mesh = (mi as MeshInstance3D).mesh
		for s in m.get_surface_count():
			var mat := m.surface_get_material(s)
			if mat == null or mat.resource_path != MAT_COMPARTILHADO:
				falhas += 1
				printerr("FALHA material %s: %s" % [caminho, mat])


func _animar(n: Node, anim: String, tempo: float, loop_esperado: bool) -> void:
	var ap := n.find_children("*", "AnimationPlayer", true, false)
	if ap.is_empty() or not (ap[0] as AnimationPlayer).has_animation(anim):
		falhas += 1
		printerr("FALHA animação '%s' ausente em %s" % [anim, n.name])
		return
	var p := ap[0] as AnimationPlayer
	var eh_loop := p.get_animation(anim).loop_mode != Animation.LOOP_NONE
	if eh_loop != loop_esperado:
		falhas += 1
		printerr("FALHA loop de '%s' = %s, esperado %s" % [anim, eh_loop, loop_esperado])
	p.play(anim)
	p.seek(tempo, true)
	p.pause()


func _montar(perfil: String) -> void:
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
	root.add_child(we)

	var sol := DirectionalLight3D.new()
	sol.rotation_degrees = Vector3(-50, -35, 0)
	sol.light_color = Color("fff3dc")
	sol.light_energy = 0.85
	sol.shadow_enabled = perfil != "performance"
	sol.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sol.directional_shadow_max_distance = 40.0
	root.add_child(sol)

	var chao := MeshInstance3D.new()
	var plano := PlaneMesh.new()
	plano.size = Vector2(80, 80)
	var mat_chao := StandardMaterial3D.new()
	mat_chao.albedo_color = Color("6cc24a")
	mat_chao.roughness = 1.0
	plano.material = mat_chao
	chao.mesh = plano
	root.add_child(chao)

	# Construções do jogador na grade de 4 m. Uma estrutura por material.
	var b := "res://assets/construcoes/"
	# madeira: cabana (piso, 2 paredes, teto), lado direito aberto
	_cena(b + "piso_madeira.glb", Vector3(-8, 0.11, -6))
	_cena(b + "parede_madeira.glb", Vector3(-8, 0, -8))
	_cena(b + "parede_madeira.glb", Vector3(-10, 0, -6), 90)
	_cena(b + "teto_madeira.glb", Vector3(-8, 4, -6))
	# pedra: rampa até um piso a 4 m, com parede de proteção
	_cena(b + "rampa_pedra.glb", Vector3(0, 0, -6))
	_cena(b + "piso_pedra.glb", Vector3(0, 4, -10))
	_cena(b + "parede_pedra.glb", Vector3(0, 4, -12))
	_cena(b + "teto_pedra.glb", Vector3(-4, 0, -14))
	# metal: canto com 2 paredes, piso, teto e rampa ao lado
	_cena(b + "piso_metal.glb", Vector3(8, 0.11, -6))
	_cena(b + "parede_metal.glb", Vector3(8, 0, -8))
	_cena(b + "parede_metal.glb", Vector3(10, 0, -6), -90)
	_cena(b + "teto_metal.glb", Vector3(8, 4, -6))
	# rampas subindo até os telhados (extremidade alta encosta na borda da célula)
	_cena(b + "rampa_madeira.glb", Vector3(-8, 0, -2))
	_cena(b + "rampa_metal.glb", Vector3(8, 0, -2))

	var c := "res://assets/cenario/"
	_cena(c + "arvore_redonda_01.glb", Vector3(-13, 0, -1), 20)
	_cena(c + "pinheiro_01.glb", Vector3(-15, 0, -11), 0)
	_cena(c + "pinheiro_01.glb", Vector3(15, 0, -14), 40)
	_cena(c + "arvore_redonda_01.glb", Vector3(14, 0, -1), 140)
	_cena(c + "pinheiro_01.glb", Vector3(5, 0, -17), 10)
	_cena(c + "pedra_01.glb", Vector3(6.5, 0, 1.5), 30)
	_cena(c + "arbusto_01.glb", Vector3(-4, 0, 2.5), 0)
	_cena(c + "arbusto_01.glb", Vector3(9.5, 0, 3), 70)

	var bau := _cena("res://assets/baus_coletaveis/bau_ventania_01.glb", Vector3(1.8, 0, 2.5), -20)
	_animar(bau, "abrir", 0.6, false)
	var bau2 := _cena("res://assets/baus_coletaveis/bau_ventania_01.glb", Vector3(3.6, 0, 3.2), 15)
	_animar(bau2, "abrir", 0.0, false)

	var p := "res://assets/personagens/recruta_base_01.glb"
	var r1 := _cena(p, Vector3(-0.6, 0, 4.2), 15)
	_animar(r1, "idle", 0.4, true)
	var r2 := _cena(p, Vector3(0.9, 0, 4.6), -10)
	_animar(r2, "acenar", 0.75, false)

	var cam := Camera3D.new()
	cam.fov = 55
	root.add_child(cam)
	cam.look_at_from_position(Vector3(1.5, 3.6, 12.5), Vector3(1.5, 2.2, -4), Vector3.UP)
