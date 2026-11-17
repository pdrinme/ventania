extends SceneTree
## Fases da entrada na partida, numa partida BR local de verdade (precisa de janela):
## porta do ônibus, salto, queda livre, curva, mergulho, abertura do planador,
## planador e aterrissagem. Salva uma imagem por fase.
## Uso: godot --path game --rendering-driver opengl3 -s res://tests/capturar_entrada.gd -- <pasta> [traje]

var jogo
var pasta := ""


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	pasta = a[0]
	await process_frame
	root.theme = VentaniaTheme.build(false)
	if a.size() > 1:
		root.get_node("Meta").profile = {"equipped": {"traje": a[1]}}
	await root.get_node("SceneManager").go("game", {"modo": "br_local", "bots": 0})
	jogo = current_scene
	for i in 30 * 40:
		await physics_frame
		if jogo.server and jogo.server.partida.estado == Protocol.MATCH_ONIBUS and jogo.onibus:
			break
	# espera as portas abrirem
	for i in 30 * 40:
		await physics_frame
		if jogo.onibus.doors_open(jogo.server_tick_now()) and jogo.server_tick_now() > jogo.onibus.abre + 60:
			break
	# câmera atrás do ônibus, olhando para a porta traseira
	var d: Vector3 = jogo.onibus.direction()
	jogo.camera.yaw = rad_to_deg(atan2(-d.x, -d.z)) + 180.0 + 25.0
	jogo.camera.pitch = -12.0
	await _esperar(10)
	# câmera de inspeção perto da porta traseira (a câmera do jogo fica longe do ônibus)
	var cam := Camera3D.new()
	cam.fov = 50
	root.add_child(cam)
	var ob: Node3D = jogo._onibus_vis
	for i in 12:
		cam.global_transform = ob.global_transform * Transform3D(Basis(), Vector3(2.6, 1.6, -9.5)).looking_at(Vector3(0, 1.0, -4.5))
		await process_frame
	cam.make_current()
	await _foto("1_porta_do_onibus", 2)
	cam.queue_free()
	jogo.camera.yaw = rad_to_deg(atan2(-d.x, -d.z)) + 30.0
	for i in 30:
		jogo.sampler.touch_jump = true          # mesmo caminho do botão Pular
		await physics_frame
		if jogo.pawn.queda != Pawn.NO_ONIBUS:
			break
	await _foto("2_saltar", 6)
	await _foto("3_queda_livre", 12)
	Input.action_press("move_right")
	await _foto("4_curva", 12)
	Input.action_release("move_right")
	# mergulho: olhando para baixo e indo para a frente (mantém durante a foto)
	Input.action_press("move_forward")
	for i in 90:
		jogo.camera.pitch = -60.0
		await physics_frame
		if jogo.pawn.velocity.y < -33.0 or jogo.pawn.queda != Pawn.QUEDA_LIVRE:
			break
	for i in 8:
		jogo.camera.pitch = -60.0
		await physics_frame
	await _foto("5_mergulho", 0)
	Input.action_release("move_forward")
	jogo.camera.pitch = -15.0
	for i in 30 * 30:
		await physics_frame
		if jogo.pawn.queda == Pawn.PLANADOR:
			break
	await _foto("6_abrindo_planador", 6)
	await _foto("7_planador", 40)
	for i in 30 * 40:
		await physics_frame
		if jogo.pawn.queda == 0:
			break
	await _foto("8_aterrissagem", 6)
	await _foto("9_recuperacao", 20)
	print("ENTRADA_OK")
	quit()


func _esperar(n: int) -> void:
	for i in n:
		await physics_frame


func _foto(nome: String, quadros: int) -> void:
	await _esperar(quadros)
	await process_frame
	root.get_texture().get_image().save_png("%s/%s.png" % [pasta, nome])
	print("FOTO ", nome, " queda=", jogo.pawn.queda, " vy=", snappedf(jogo.pawn.velocity.y, 0.1))
