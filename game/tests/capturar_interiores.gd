extends SceneTree
## Fotos dos interiores numa partida local (precisa de janela): cada escada vista do
## cômodo vizinho e de cima, e cada cômodo mobiliado (quando houver). Câmera livre,
## sem HUD.
## Uso: godot --path game --rendering-driver opengl3 -s res://tests/capturar_interiores.gd -- <pasta> [escadas|comodos|tudo]

func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var pasta: String = a[0]
	var o_que: String = a[1] if a.size() > 1 else "tudo"
	await process_frame
	root.theme = VentaniaTheme.build(false)
	await root.get_node("SceneManager").go("game", {"modo": "br_local", "bots": 0})
	var jogo = current_scene
	for i in 90:
		await physics_frame
	jogo.combat_hud.visible = false
	jogo.hud.visible = false
	jogo.match_hud.visible = false
	jogo.touch.visible = false
	var cam := Camera3D.new()
	cam.fov = 62
	cam.far = 120
	root.add_child(cam)
	cam.current = true
	var n := 0
	if o_que != "comodos":
		for e: Dictionary in jogo.mundo.stairs():
			var base: Vector3 = e["pos"]
			var giro := Basis(Vector3.UP, deg_to_rad(float(e["rot"])))
			cam.global_position = base + giro * Vector3(5.6, 1.75, 1.6)
			cam.look_at(base + giro * Vector3(-0.6, 1.4, -0.2))
			await _foto(pasta, "escada_%d_baixo" % n)
			cam.global_position = base + giro * Vector3(5.4, 5.7, -1.6)
			cam.look_at(base + giro * Vector3(0.0, 3.0, 0.0))
			await _foto(pasta, "escada_%d_cima" % n)
			n += 1
	if o_que != "escadas" and jogo.mundo.has_method("rooms"):
		var k := 0
		for c: Dictionary in jogo.mundo.rooms():
			var centro: Vector3 = c["centro"]
			cam.global_position = centro + Vector3(c["olhar"].x, 2.3, c["olhar"].y)
			cam.look_at(centro + Vector3(0, 0.6, 0))
			await _foto(pasta, "comodo_%02d_%s" % [k, c["tipo"]])
			k += 1
	print("INTERIORES %d fotos" % n)
	quit()


func _foto(pasta: String, nome: String) -> void:
	for i in 6:
		await process_frame
	root.get_texture().get_image().save_png("%s/%s.png" % [pasta, nome])
