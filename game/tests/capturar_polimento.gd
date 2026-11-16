extends SceneTree
## Verificação visual do polimento da Etapa 3 dentro de uma partida local real.
## Prepara situações pelo servidor local (itens, posição) e fotografa com uma
## câmera lateral extra. Precisa de janela (xvfb-run).
## Uso: godot --path game --rendering-driver opengl3 --resolution 960x540 -s res://tests/capturar_polimento.gd -- <pasta>

var pasta := ""
var jogo
var cli: GameServer.Cliente
var cam_lado: Camera3D


func _init() -> void:
	pasta = OS.get_cmdline_user_args()[0]
	await process_frame
	root.theme = VentaniaTheme.build(false)
	await root.get_node("SceneManager").go("game", {"modo": "local"})
	jogo = current_scene
	for i in 150:
		await physics_frame
		if jogo.pawn:
			break
	await _quadros(20)
	cli = jogo.server.clientes.values()[0]
	cam_lado = Camera3D.new()
	cam_lado.fov = 40
	jogo.add_child(cam_lado)

	await _inventario()
	await _bau()
	await _recarga("rajada", "recarga_rifle")
	await _recarga("trovao", "recarga_espingarda")
	await _recarga("faisca", "recarga_pistola")
	await _consumivel("celula_p", "uso_celula")
	await _consumivel("curativo", "uso_curativo")
	await _troca()
	await _mira_e_tiro()
	print("POLIMENTO_OK")
	quit()


func _quadros(n: int) -> void:
	for i in n:
		await physics_frame


func _foto(nome: String) -> void:
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png("%s/%s.png" % [pasta, nome])
	print("FOTO ", nome)


func _teleportar(pos: Vector3, yaw_graus: float) -> void:
	cli.pawn.global_position = pos
	cli.pawn.velocity = Vector3.ZERO
	jogo.pawn.global_position = pos
	jogo.pawn.velocity = Vector3.ZERO
	jogo.camera.yaw = yaw_graus
	jogo.camera.pitch = -8.0
	await _quadros(10)


func _dar(itens: Array, sel := 0) -> void:
	cli.inv = Inventory.new()
	for it in itens:
		cli.inv.add_item(it[0], it[1], it[2] if it.size() > 2 else 1)
	for t in ItemDB.ammo_types():
		cli.inv.add_ammo(t, 200)
	cli.inv.selected = sel
	cli.dirty = true
	await _quadros(12)


func _camera_lado(alvo: Vector3, de: Vector3) -> void:
	cam_lado.look_at_from_position(alvo + de, alvo, Vector3.UP)
	cam_lado.current = true


func _camera_jogo() -> void:
	jogo.camera.camera().current = true


func _inventario() -> void:
	_camera_jogo()
	await _dar([["rajada", 0], ["trovao", 1], ["zumbido", 2], ["faisca", 3], ["gaviao", 4]], 1)
	await _foto("inventario_raridades")
	await _dar([["gaviao", 5], ["curativo", 0, 5], ["celula_g", 0, 2], ["kit_cura", 0, 1], ["rajada", 4]], 0)
	await _foto("inventario_mitico_consumiveis")


func _bau() -> void:
	# baú no chão (índice 3), personagem a 1,6 m de frente para ele
	var b: Vector3 = CampoTreino.CHESTS[3][0]
	var rot: float = CampoTreino.CHESTS[3][1]
	var frente := Basis(Vector3.UP, deg_to_rad(rot)) * Vector3(0, 0, 1)
	var pos: Vector3 = b + frente * 1.6
	var dir := (b - pos).normalized()
	await _dar([["rajada", 2]], 0)
	await _teleportar(pos, rad_to_deg(atan2(-dir.x, -dir.z)))
	_camera_jogo()
	await _foto("bau_1_indicador")
	var lado := frente.cross(Vector3.UP).normalized()
	_camera_lado(b + Vector3(0, 0.8, 0) + frente * 0.8, lado * 3.2 + Vector3(0, 0.6, 0))
	Input.action_press("interact")
	await _quadros(7)
	await _foto("bau_2_alcancando")
	await _quadros(12)
	await _foto("bau_3_abrindo")
	await _quadros(10)
	Input.action_release("interact")
	await _foto("bau_4_aberto_itens")
	await _quadros(25)
	_camera_jogo()
	await _foto("bau_5_itens_no_chao")


func _recarga(arma: String, nome: String) -> void:
	await _dar([[arma, 2]], 0)
	await _teleportar(Vector3(20, 0.05, 20), 0.0)
	cli.inv.current().mag = 0
	cli.dirty = true
	await _quadros(4)
	var p: Vector3 = jogo.pawn.global_position
	_camera_lado(p + Vector3(0, 1.2, 0), Vector3(-2.4, 0.3, -0.6))
	Input.action_press("reload")
	await _quadros(2)
	Input.action_release("reload")
	var dur := ItemDB.reload_time(arma, 2)
	for k in [0.2, 0.45, 0.8]:
		await _quadros(maxi(1, int(dur * Protocol.TICK_RATE * (0.2 if k == 0.2 else 0.25 if k == 0.45 else 0.35))))
		await _foto("%s_%d" % [nome, int(k * 100)])
	await _quadros(int(dur * Protocol.TICK_RATE))


func _consumivel(item: String, nome: String) -> void:
	await _dar([[item, 0, 3]], 0)
	await _teleportar(Vector3(20, 0.05, 20), 0.0)
	cli.vit.health = 40
	cli.vit.shield = 0
	cli.dirty = true
	var p: Vector3 = jogo.pawn.global_position
	_camera_lado(p + Vector3(0, 1.2, 0), Vector3(-2.2, 0.3, -1.0))
	await _quadros(4)
	await _foto(nome + "_segurando")
	Input.action_press("fire")
	await _quadros(3)
	Input.action_release("fire")
	var dur := float(ItemDB.consumable(item)["tempo_s"])
	await _quadros(int(dur * Protocol.TICK_RATE * 0.4))
	await _foto(nome + "_usando")
	await _quadros(int(dur * Protocol.TICK_RATE * 0.7))


func _troca() -> void:
	await _dar([["faisca", 1], ["rajada", 3]], 0)
	await _teleportar(Vector3(20, 0.05, 20), 0.0)
	var p: Vector3 = jogo.pawn.global_position
	_camera_lado(p + Vector3(0, 1.2, 0), Vector3(-2.2, 0.3, -1.0))
	await _quadros(10)
	jogo.sampler.select_slot(1)
	await _quadros(3)
	await _foto("troca_meio")
	await _quadros(10)
	await _foto("troca_fim")


func _mira_e_tiro() -> void:
	await _dar([["rajada", 3]], 0)
	await _teleportar(Vector3(20, 0.05, 20), 0.0)
	var p: Vector3 = jogo.pawn.global_position
	_camera_lado(p + Vector3(0, 1.3, 0), Vector3(-2.2, 0.2, -0.9))
	Input.action_press("aim")
	await _quadros(12)
	await _foto("mirando")
	Input.action_press("fire")
	await _quadros(2)
	await _foto("disparando")
	Input.action_release("fire")
	Input.action_release("aim")
	await _quadros(6)
