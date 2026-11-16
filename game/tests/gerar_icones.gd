extends SceneTree
## Ferramenta: renderiza as miniaturas do inventário a partir dos modelos 3D
## (fundo transparente, ângulo de 3/4, enquadramento automático).
## Precisa de janela (xvfb-run no Linux sem tela):
##   godot --path game --rendering-driver opengl3 -s res://tests/gerar_icones.gd
## Saída: res://assets/ui/icones/<item>.png (256x256)

const TAM := 256
const SAIDA := "res://assets/ui/icones"


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SAIDA))
	var vp := SubViewport.new()
	vp.size = Vector2i(TAM, TAM)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("dfe6ff")
	env.ambient_light_energy = 0.75
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var sol := DirectionalLight3D.new()
	sol.rotation_degrees = Vector3(-35, 35, 0)
	sol.light_energy = 0.9
	vp.add_child(sol)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	vp.add_child(cam)

	var itens := {}
	for id in ItemDB.data()["armas"]:
		itens[id] = "res://assets/armas/%s.glb" % ItemDB.weapon(id)["modelo"]
	for id in ItemDB.data()["consumiveis"]:
		itens[id] = "res://assets/baus_coletaveis/%s.glb" % ItemDB.consumable(id)["modelo"]
	for id in ItemDB.data()["ferramentas"]:
		itens[id] = "res://assets/armas/%s.glb" % ItemDB.tool_def(id)["modelo"]
	itens["municao"] = "res://assets/baus_coletaveis/municao_01.glb"

	for id in itens:
		var m := (load(itens[id]) as PackedScene).instantiate() as Node3D
		vp.add_child(m)
		var arma := ItemDB.is_weapon(id)
		var ferramenta := ItemDB.is_tool_item(id)
		# armas: de lado com o cano para a direita, leve inclinação; outros: 3/4
		m.rotation_degrees = Vector3(0, 90, 8) if arma else (Vector3(-35, 90, 0) if ferramenta else Vector3(0, 35, 0))
		await process_frame
		var caixa := AABB()
		var primeiro := true
		for mi: MeshInstance3D in m.find_children("*", "MeshInstance3D", true, false):
			var a := mi.global_transform * mi.get_aabb()
			caixa = a if primeiro else caixa.merge(a)
			primeiro = false
		var centro := caixa.get_center()
		cam.size = maxf(caixa.size.x, maxf(caixa.size.y, caixa.size.z)) * (1.12 if arma else (1.05 if ferramenta else 1.3))
		var dir := Vector3(0, 0.25, 1).normalized() if arma or ferramenta else Vector3(0.0, 0.55, 1).normalized()
		cam.look_at_from_position(centro + dir * 10.0, centro, Vector3.UP)
		for i in 4:
			await process_frame
		var img := vp.get_texture().get_image()
		img.save_png(ProjectSettings.globalize_path("%s/%s.png" % [SAIDA, id]))
		print("ICONE ", id)
		m.queue_free()
		await process_frame
	quit()
