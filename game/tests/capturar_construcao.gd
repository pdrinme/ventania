extends SceneTree
## Verificação visual da Etapa 5 numa partida local real (campo de treino):
## prévia da peça (azul/vermelho), estrutura construída pelo jogador, obra em
## andamento, rachaduras por dano, porta editada, grade de edição, destruição
## e as casas da Ilha desenhadas pelo sistema de construção.
## Uso: xvfb-run godot --path game --rendering-driver opengl3 --resolution 960x540 -s res://tests/capturar_construcao.gd -- <pasta>

var pasta := ""
var jogo
var cli: GameServer.Cliente
var cam: Camera3D


func _init() -> void:
	pasta = OS.get_cmdline_user_args()[0]
	await process_frame
	root.theme = VentaniaTheme.build(false)
	await root.get_node("SceneManager").go("game", {"modo": "local"})
	jogo = current_scene
	for i in 200:
		await physics_frame
		if jogo.pawn:
			break
	await _quadros(20)
	cli = jogo.server.clientes.values()[0]
	cam = Camera3D.new()
	cam.fov = 50
	jogo.add_child(cam)
	await _teleportar(Vector3(42, 0.1, 50), 0.0, -10.0)
	jogo.modo_build.set_active(true)
	jogo.modo_build.select_piece(0)
	await _quadros(6)
	await _foto("construcao_1_previa_parede")
	# monta uma base: pisos, paredes, rampa e piso de cima (pelo servidor, como o jogador faria)
	var base := Vector3i(10, 0, 10)
	var pedidos := [[1, 0, base, 0], [1, 0, base + Vector3i(1, 0, 0), 0], [0, 0, base, 0], [0, 1, base + Vector3i(1, 0, 0), 0],
			[0, 2, base, 1], [0, 0, base + Vector3i(2, 0, 0), 3], [2, 0, base + Vector3i(0, 0, 1), 0], [1, 0, base + Vector3i(0, 1, 0), 0],
			[1, 0, base + Vector3i(1, 1, 0), 0], [3, 0, base + Vector3i(1, 1, 0), 0]]
	cli.pawn.global_position = Vector3(44, 0.1, 46)
	for p in pedidos:
		var r: int = jogo.server.build.try_build(cli, {"escolha": p[0], "material": p[1], "cell": p[2], "rot": p[3]})
		if r != Inventory.Err.OK:
			print("pedido ", p, " -> ", r)
	await _quadros(5)
	await _foto_de("construcao_2_em_obra", Vector3(47, 6, 54), Vector3(44, 2, 41))
	await _quadros(80)
	await _foto_de("construcao_3_pronta", Vector3(47, 6, 54), Vector3(44, 2, 41))
	# dano progressivo
	var est: Construcoes = jogo.server.build.estado
	var ids := est.pecas.values().filter(func(x): return x.dono == cli.id and (x.tipo == Grade.PAREDE_X or x.tipo == Grade.PAREDE_Z)).map(func(x): return x.id)
	for k in ids.size():
		jogo.server.build.damage(ids[k], est.pecas[ids[k]].hp_max * (0.25 + 0.2 * k), cli)
	await _quadros(10)
	await _foto_de("construcao_4_rachaduras", Vector3(45, 3.0, 32), Vector3(44, 2, 40))
	# porta editada (pelo servidor) e a grade de edição no cliente
	var parede: int = est.por_slot[Grade.key(Grade.PAREDE_X, base)]
	jogo.server.build.try_edit(cli, parede, 511 & ~((1 << 1) | (1 << 4)))
	await _quadros(10)
	await _foto_de("construcao_5_porta", Vector3(42, 2.0, 33), Vector3(42, 1.5, 40))
	await _teleportar(Vector3(43.5, 0.1, 46), 0.0, -5.0)
	jogo.camera.camera().current = true
	jogo.modo_build.editando = est.por_slot[Grade.key(Grade.PAREDE_X, base + Vector3i(0, 0, 0))]
	jogo.modo_build.mask_edicao = 511 & ~(1 << 4)
	jogo.modo_build._desenhar_edicao()
	await _quadros(4)
	await _foto("construcao_6_grade_edicao")
	jogo.modo_build.cancel_edit()
	# destruição: tira o apoio e fotografa os fragmentos
	for id in est.pecas.keys().filter(func(x): return est.pecas[x].dono == cli.id and est.pecas[x].cell.y == 0 and est.pecas[x].tipo != Grade.PISO):
		jogo.server.build.damage(id, 9999.0, cli)
	await _quadros(4)
	await _foto_de("construcao_7_desabando", Vector3(48, 6, 54), Vector3(44, 3, 41))
	print("CONSTRUCAO_OK")
	quit()


func _quadros(n: int) -> void:
	for i in n:
		await physics_frame


func _foto(nome: String) -> void:
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png("%s/%s.png" % [pasta, nome])
	print("FOTO ", nome)


func _foto_de(nome: String, de: Vector3, para: Vector3) -> void:
	cam.look_at_from_position(de, para, Vector3.UP)
	cam.current = true
	await _foto(nome)
	jogo.camera.camera().current = true


func _teleportar(pos: Vector3, yaw: float, pitch: float) -> void:
	cli.pawn.global_position = pos
	cli.pawn.velocity = Vector3.ZERO
	jogo.pawn.global_position = pos
	jogo.camera.yaw = yaw
	jogo.camera.pitch = pitch
	await _quadros(12)
