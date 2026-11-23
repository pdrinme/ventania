extends SceneTree
## Fotos de comparação visual (antes/depois da revisão de arte), sempre dos mesmos
## ângulos: fila com todos os trajes, rostos, personagem no mundo, vila, casa de
## perto, mata, paisagem, armas, loot. Usa o mapa real (Ilha Ventania + construções)
## com o ambiente do jogo. Precisa de janela (xvfb-run).
## Uso: godot --path game --rendering-driver opengl3 --resolution 1280x720 -s res://tests/capturar_visual.gd -- <pasta>

var pasta := ""


func _init() -> void:
	pasta = OS.get_cmdline_user_args()[0]
	await process_frame
	root.get_node("Settings").set_value("graphics", "profile", "quality")
	var mapa := IlhaVentania.new()
	root.add_child(mapa)
	var bc := BuildClient.new()
	root.add_child(bc)
	bc.setup(mapa)
	var cam := Camera3D.new()
	cam.fov = 60
	cam.add_to_group("camera_principal")
	root.add_child(cam)
	cam.current = true
	var cfg := Cosmeticos.config()
	var trajes: Array = cfg["trajes"].keys()
	var vila: Vector3 = mapa.points_of_interest()[0]["pos"]
	var faz: Vector3 = mapa.points_of_interest()[3]["pos"]
	# --- fila de trajes, num ponto aberto perto da vila (luz do jogo)
	var base := vila + Vector3(-30, 0, 32)
	base.y = mapa.ground_height(base.x, base.z)
	var bonecos := []
	for i in trajes.size():
		var m := (load(cfg["trajes"][trajes[i]]) as PackedScene).instantiate() as Node3D
		var p := base + Vector3((i - (trajes.size() - 1) / 2.0) * 1.15, 0, 0)
		p.y = mapa.ground_height(p.x, p.z)
		m.position = p
		m.rotation_degrees.y = -10
		root.add_child(m)
		TrajeFx.attach(m, trajes[i])
		var ap := m.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
		ap.play("idle")
		ap.seek(i * 0.3, true)
		bonecos.append(m)
	cam.fov = 32
	cam.look_at_from_position(base + Vector3(0, 1.6, 13.5), base + Vector3(0, 1.0, 0))
	await _foto("01_trajes_fila")
	# rostos: 4 primeiros humanos de perto
	cam.fov = 26
	for k in [0, 1, 7, 8]:
		if k >= bonecos.size():
			continue
		var b: Node3D = bonecos[k]
		cam.look_at_from_position(b.position + Basis(Vector3.UP, deg_to_rad(-10)) * Vector3(0.25, 1.68, 1.55), b.position + Vector3(0, 1.62, 0))
		await _foto("02_rosto_%s" % trajes[k])
	# personagem no mundo (câmera de 3ª pessoa) correndo
	var heroi: Node3D = bonecos[0]
	heroi.position = vila + Vector3(-6, 0, 3.5)
	heroi.position.y = mapa.ground_height(heroi.position.x, heroi.position.z)
	heroi.rotation_degrees.y = 200
	var ap0 := heroi.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	ap0.play("correr")
	ap0.seek(0.2, true)
	cam.fov = 70
	cam.look_at_from_position(heroi.position + Vector3(0.8, 2.2, -3.4), heroi.position + Vector3(0, 1.4, 4))
	await _foto("03_personagem_no_mundo")
	for b in bonecos:
		(b as Node3D).visible = false
	# vila de cima e casa de perto
	cam.fov = 60
	cam.look_at_from_position(vila + Vector3(-42, 22, 42), vila + Vector3(0, 0, 0))
	await _foto("04_vila")
	cam.look_at_from_position(vila + Vector3(-4, 2.2, -9), vila + Vector3(14, 3.0, -21))
	await _foto("05_casa")
	# mata (bosque), paisagem e fazenda
	var mata := _ponto_mata(mapa)
	cam.look_at_from_position(mata + Vector3(0, 2.0, 0), mata + Vector3(14, 1.2, 10))
	await _foto("06_vegetacao")
	cam.look_at_from_position(Vector3(-150, 110, 230), Vector3(0, 0, 0))
	await _foto("07_paisagem")
	cam.look_at_from_position(faz + Vector3(-30, 12, 36), faz)
	await _foto("08_fazenda")
	# loot como aparece no jogo (LootVisual: anel, coluna de luz por raridade) e o baú
	var linha := vila + Vector3(-30, 0, 32)
	var ids := []
	for k in 64:
		var id := ItemDB.id_of(k)
		if id == "":
			if k == 0:
				continue      # índice 0 = nenhum item
			break
		if ItemDB.is_weapon(id) or ItemDB.is_consumable(id):
			ids.append(k)
	var n := 0
	for k in ids.slice(0, 8):
		var p := linha + Vector3(-4.2 + n * 1.2, 0, 0)
		p.y = mapa.ground_height(p.x, p.z)
		var lv := LootVisual.new()
		lv.setup({"pos": p, "item": k, "ammo": 0, "rarity": n % 5, "count": 1, "mat": 0})
		root.add_child(lv)
		n += 1
	var bau := (load("res://assets/baus_coletaveis/bau_ventania_01.glb") as PackedScene).instantiate() as Node3D
	bau.position = linha + Vector3(5.6, 0, -0.6)
	bau.position.y = mapa.ground_height(bau.position.x, bau.position.z)
	bau.rotation_degrees.y = -25
	root.add_child(bau)
	cam.fov = 40
	cam.look_at_from_position(linha + Vector3(0.6, 2.0, 6.0), linha + Vector3(0.6, 0.5, 0))
	await _foto("09_armas_itens")
	print("VISUAL_OK")
	quit()


func _ponto_mata(mapa: IlhaVentania) -> Vector3:
	# o ponto com mais árvores em volta (dos props do mapa)
	var arvores: Array = mapa.harvest_points().filter(func(p): return mapa.ground_height(p.x, p.z) > 2.0)
	var melhor := Vector3.ZERO
	var nota := -1
	for i in range(0, arvores.size(), 7):
		var c: Vector3 = arvores[i]
		var k := 0
		for q in arvores:
			if c.distance_to(q) < 18.0:
				k += 1
		if k > nota:
			nota = k
			melhor = c
	return melhor + Vector3(-6, 0, -6)


func _foto(nome: String) -> void:
	for i in 12:
		await process_frame
	root.get_texture().get_image().save_png("%s/%s.png" % [pasta, nome])
	print("FOTO ", nome)
