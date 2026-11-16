extends SceneTree
## Tira de filme das animações: uma linha por animação, colunas = momentos do ciclo.
## Uso: godot --path game --rendering-driver opengl3 -s res://tests/capturar_animacoes.gd -- saida.png [yaw]

const ANIMS := ["idle", "andar", "correr", "agachado", "agachado_andar", "pular", "queda", "aterrissar", "acenar"]
const COLUNAS := 6


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var saida := args[0]
	var yaw := float(args[1]) if args.size() > 1 else 90.0
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("8fd3ff")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("c8d2ff")
	env.ambient_light_energy = 0.55
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sol := DirectionalLight3D.new()
	sol.rotation_degrees = Vector3(-35, -40, 0)
	root.add_child(sol)
	var cena: PackedScene = load("res://assets/personagens/recruta_base_01.glb")
	var esp_x := 1.25
	var esp_y := 2.3
	for linha in ANIMS.size():
		var rotulo := Label3D.new()
		rotulo.text = ANIMS[linha]
		rotulo.font_size = 48
		rotulo.pixel_size = 0.006
		rotulo.position = Vector3(-1.1 * esp_x, -linha * esp_y + 1.0, 0)
		rotulo.modulate = Color("24252c")
		root.add_child(rotulo)
		for col in COLUNAS:
			var r := cena.instantiate() as Node3D
			r.position = Vector3(col * esp_x, -linha * esp_y, 0)
			r.rotation_degrees.y = yaw
			root.add_child(r)
			var ap := r.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
			if not ap.has_animation(ANIMS[linha]):
				printerr("FALTA animação " + ANIMS[linha])
				continue
			ap.play(ANIMS[linha])
			ap.seek(ap.get_animation(ANIMS[linha]).length * col / float(COLUNAS), true)
			ap.pause()
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = ANIMS.size() * esp_y + 0.5
	root.add_child(cam)
	var centro := Vector3((COLUNAS - 2) * esp_x * 0.5, -(ANIMS.size() - 1) * esp_y * 0.5 + 0.9, 0)
	cam.look_at_from_position(centro + Vector3(0, 0, 20), centro, Vector3.UP)
	for i in 6:
		await process_frame
	root.get_texture().get_image().save_png(saida)
	print("ANIMS_OK")
	quit()
