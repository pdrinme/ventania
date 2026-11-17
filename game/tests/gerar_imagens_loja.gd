extends SceneTree
## Gera as imagens dos cosméticos para a loja, a coleção e o passe, a partir dos
## MODELOS REAIS do jogo (os mesmos da partida): personagem de corpo inteiro em
## 3/4 (com o efeito do traje, ex.: aquário), picareta e planador em destaque.
## Fundo na cor da raridade com rajadas de vento (identidade do Ventania).
## Saída: game/assets/ui/loja/<id_do_item>.png (512x640). Precisa de janela (xvfb-run).
## Uso: godot --path game --rendering-driver opengl3 --resolution 512x640 -s res://tests/gerar_imagens_loja.gd [-- id ...]

const CORES := {"comum": Color("8a93a8"), "incomum": Color("3fbf74"), "raro": Color("3a8ee6"),
		"epico": Color("9b5de5"), "lendario": Color("f2a33a"), "mitico": Color("ff6fd0")}
const PASTA := "res://assets/ui/loja"

func _init() -> void:
	await process_frame
	var catalogo := _catalogo()
	var so: PackedStringArray = OS.get_cmdline_user_args()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PASTA))
	var feitos := 0
	for id in catalogo:
		if not so.is_empty() and not id in so:
			continue
		var item: Dictionary = catalogo[id]
		var cena := _cena_do_item(item)
		if cena.is_empty():
			continue                       # sem modelo (ex.: emote): sem imagem
		await _fotografar(item, cena)
		feitos += 1
	print("IMAGENS_LOJA %d" % feitos)
	quit()


func _catalogo() -> Dictionary:
	var pasta := ProjectSettings.globalize_path("res://").path_join("../backend/config/catalog")
	var out := {}
	for f in DirAccess.get_files_at(pasta):
		if f.ends_with(".json"):
			var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(pasta.path_join(f)))
			for it in (d as Dictionary).get("itens", []):
				out[it["id"]] = it
	return out


func _cena_do_item(item: Dictionary) -> String:
	var cfg := Cosmeticos.config()
	match item["categoria"]:
		"traje":
			return cfg["trajes"].get(item["id"], "")
		"picareta":
			return cfg.get("picaretas", {}).get(item["id"], "")
		"planador":
			return cfg.get("planadores", {}).get(item["id"], "")
	return ""


func _fotografar(item: Dictionary, cena: String) -> void:
	var raiz := Node3D.new()
	root.add_child(raiz)
	var cor: Color = CORES.get(item["raridade"], CORES["comum"])
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = cor.darkened(0.55)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("d6dcff")
	env.ambient_light_energy = 0.65
	var we := WorldEnvironment.new()
	we.environment = env
	raiz.add_child(we)
	var sol := DirectionalLight3D.new()
	sol.rotation_degrees = Vector3(-30, -35, 0)
	sol.light_energy = 1.05
	raiz.add_child(sol)
	var contra := DirectionalLight3D.new()
	contra.rotation_degrees = Vector3(-15, 150, 0)
	contra.light_energy = 0.7
	contra.light_color = cor.lightened(0.4)
	raiz.add_child(contra)
	# painel de fundo: degradê da raridade + rajadas de vento
	var painel := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(9, 11)
	painel.mesh = quad
	var mat := ShaderMaterial.new()
	mat.shader = load("res://ui/shared/fundo_cosmetico.gdshader")
	mat.set_shader_parameter("cor", cor)
	painel.material_override = mat
	raiz.add_child(painel)
	var m := (load(cena) as PackedScene).instantiate() as Node3D
	raiz.add_child(m)
	var cam := Camera3D.new()
	cam.fov = 30
	raiz.add_child(cam)
	match item["categoria"]:
		"traje":
			m.rotation_degrees.y = -24
			var aps := m.find_children("*", "AnimationPlayer", true, false)
			if not aps.is_empty():
				var ap := aps[0] as AnimationPlayer
				ap.play("idle")
				ap.seek(0.6, true)
			TrajeFx.attach(m, item["id"])
			painel.position = Vector3(0, 1.1, -2.5)
			cam.look_at_from_position(Vector3(0.3, 1.2, 4.15), Vector3(0, 0.98, 0))
		"picareta":
			m.rotation_degrees = Vector3(0, 70, -32)
			VitrineCosmetico.encaixar(m, 1.75, Vector3(0, 1.05, 0))
			painel.position = Vector3(0, 1.0, -2.0)
			cam.look_at_from_position(Vector3(0, 1.05, 4.6), Vector3(0, 1.05, 0))
		"planador":
			m.rotation_degrees = Vector3(-38, 28, 8)
			VitrineCosmetico.encaixar(m, 2.0, Vector3(0, 1.05, 0))
			painel.position = Vector3(0, 1.0, -2.5)
			cam.look_at_from_position(Vector3(0, 1.15, 5.0), Vector3(0, 1.05, 0))
	for i in 24:
		await process_frame
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("%s/%s.png" % [PASTA, item["id"]]))
	print("IMAGEM ", item["id"])
	raiz.queue_free()
	await process_frame

