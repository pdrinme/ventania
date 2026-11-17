extends SceneTree
## Aceitação (Etapa 13): a picareta cosmética só muda o visual.
## Numa partida local de verdade, golpeia a mesma parede de madeira com a picareta
## padrão e com a Âncora de Coleta (equipadas como no perfil) e confere:
## - o modelo na mão do jogador é o da picareta equipada (e o traje, o equipado);
## - os golpes, os impactos e os materiais coletados são idênticos.
## Uso: godot --headless --path game -s res://tests/integration/test_picareta_cosmetica.gd

const GOLPES := 6
var _falhas: Array[String] = []


func _init() -> void:
	await process_frame
	root.theme = VentaniaTheme.build(false)
	var padrao := await _rodada("picareta_padrao", "traje_recruta")
	var ancora := await _rodada("picareta_ancora", "traje_capitao_mare")
	print("padrão: %s" % [padrao])
	print("âncora: %s" % [ancora])
	_conferir(padrao["impactos"] == GOLPES, "todos os golpes acertaram (padrão)")
	_conferir(padrao["madeira"] > 0, "coletou madeira")
	for k in padrao:
		_conferir(padrao[k] == ancora[k], "%s igual com as duas picaretas" % k)
	print("PICARETA_COSMETICA OK" if _falhas.is_empty() else "PICARETA_COSMETICA FALHOU %s" % [_falhas])
	quit(0 if _falhas.is_empty() else 1)


func _rodada(picareta: String, traje: String) -> Dictionary:
	root.get_node("Meta").profile = {"equipped": {"traje": traje, "picareta": picareta}}
	await root.get_node("SceneManager").go("game", {"modo": "local"})
	var jogo = current_scene
	for i in 150:
		await physics_frame
		if jogo.pawn:
			break
	for i in 20:
		await physics_frame
	var cli = jogo.server.clientes.values()[0]
	_conferir(cli.picareta == picareta, "servidor registrou a picareta %s" % picareta)
	_conferir(jogo.visual.picareta_id == picareta, "visual com a picareta %s" % picareta)
	_conferir(jogo.visual.traje == traje, "visual com o traje %s" % traje)
	cli.inv = Inventory.new()
	cli.inv.select(Inventory.PICKAXE)
	cli.dirty = true
	var pos := Vector3(-16.55, 0.1, -10.2)          # de frente para a parede de madeira da cabana
	cli.pawn.global_position = pos
	cli.pawn.velocity = Vector3.ZERO
	jogo.pawn.global_position = pos
	jogo.pawn.velocity = Vector3.ZERO
	jogo.camera.yaw = 0.0
	jogo.camera.pitch = -6.0
	for i in 15:
		await physics_frame
	# o modelo da mão é o da picareta equipada
	var cena_esperada: String = Cosmeticos.pickaxe_scene(picareta)
	var achou := false
	for n in jogo.visual.find_children("*", "Node3D", true, false):
		if n.scene_file_path == cena_esperada:
			achou = true
	_conferir(achou, "modelo %s na mão" % cena_esperada.get_file())
	var h0: int = cli.melee_hits
	for g in GOLPES:
		Input.action_press("fire")
		for i in 3:
			await physics_frame
		Input.action_release("fire")
		for i in Combat.melee_swing_steps() + 4:
			await physics_frame
	var r := {"impactos": cli.melee_hits - h0, "golpes": cli.swings}
	for t in cli.inv.materials:
		r[t] = int(cli.inv.materials[t])
	return r


func _conferir(cond: bool, o_que: String) -> void:
	if not cond:
		_falhas.append(o_que)
		print("FALHA ", o_que)
