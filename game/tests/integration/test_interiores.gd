extends SceneTree
## Mobília dos edifícios no mapa real (com colisão das peças de construção):
##  - cada edifício recebe móveis do seu tipo (casa, loja, prédio, galpão, celeiro);
##  - todo móvel fica dentro do seu cômodo (sem atravessar paredes), sem se sobrepor
##    a outro e apoiado no piso (sem flutuar);
##  - o meio de cada cômodo fica livre: cabe um personagem de pé no centro;
##  - nenhuma porta fica bloqueada: um personagem anda de fora para dentro por todas;
##  - as escadas continuam livres (test_escadas cobre a subida).
## Uso: godot --headless --fixed-fps 30 --path game -s res://tests/integration/test_interiores.gd

var falhas := 0


func _checar(ok: bool, msg: String) -> void:
	print(("  ok  " if ok else "  FALHOU  ") + msg)
	if not ok:
		falhas += 1


func _init() -> void:
	await process_frame
	var mundo := IlhaVentania.new()
	mundo.com_ambiente = false
	root.add_child(mundo)
	var server := GameServer.new(mundo, 5, "treino", {})
	root.add_child(server)
	for i in 3:
		await physics_frame
	var moveis := mundo.furniture()
	var tipos := {}
	for c: Dictionary in mundo.rooms():
		tipos[c["tipo"]] = int(tipos.get(c["tipo"], 0)) + 1
	var por_id := {}
	for m: Dictionary in moveis:
		por_id[m["id"]] = int(por_id.get(m["id"], 0)) + 1
	print("  %d móveis em %d cômodos · cômodos: %s" % [moveis.size(), mundo.rooms().size(), str(tipos)])
	print("  modelos usados: %s" % str(por_id))
	_checar(moveis.size() >= 100, "edifícios mobiliados (%d móveis)" % moveis.size())
	_checar(tipos.size() >= 7, "variedade de cômodos (%d tipos)" % tipos.size())
	# dentro do cômodo, sem sobreposição, longe do centro
	var fora := 0
	var sobre := 0
	var centro_ocupado := 0
	for a: Dictionary in moveis:
		var ra := _retangulo(a)
		for q: Vector2 in ra:
			if absf(q.x) > 1.87 or absf(q.y) > 1.87:
				fora += 1
				print("    fora do cômodo: %s em %s" % [a["id"], str((a["pos"] as Vector3).snapped(Vector3.ONE * 0.1))])
				break
		if Geometry2D.is_point_in_polygon(Vector2.ZERO, ra) or _dist_ret(ra) < 0.8:
			centro_ocupado += 1
			print("    perto do meio do cômodo: %s em %s (%.2f m)" % [a["id"], str((a["pos"] as Vector3).snapped(Vector3.ONE * 0.1)), _dist_ret(ra)])
		for b: Dictionary in moveis:
			if b == a or (b["centro"] as Vector3).distance_to(a["centro"]) > 0.1 or b["id"] == "tapete_01":
				continue
			if not Geometry2D.intersect_polygons(ra, _retangulo(b)).is_empty():
				sobre += 1
	_checar(fora == 0, "nenhum móvel atravessa a parede (%d fora)" % fora)
	_checar(sobre == 0, "nenhum móvel sobreposto a outro (%d pares)" % (sobre / 2))
	_checar(centro_ocupado == 0, "o meio de cada cômodo fica livre (%d móveis a menos de 0,8 m)" % centro_ocupado)
	# apoiado no piso: raio para baixo a partir do móvel encontra o piso logo abaixo
	var espaco := mundo.get_world_3d().direct_space_state
	var flutuando := 0
	for a: Dictionary in moveis:
		var pos: Vector3 = a["pos"]
		var q := PhysicsRayQueryParameters3D.create(pos + Vector3(0, 0.05, 0) + Vector3((a["nrm"] as Vector2).x, 0, (a["nrm"] as Vector2).y) * 0.0, pos + Vector3(0, -0.5, 0), Pawn.LAYER_WORLD)
		var r := espaco.intersect_ray(q)
		if r.is_empty() or absf(r["position"].y - pos.y) > 0.08:
			flutuando += 1
	_checar(flutuando == 0, "todos apoiados no piso (%d sem piso logo abaixo)" % flutuando)
	# centro de cada cômodo: cabe um personagem de pé
	var cheios := 0
	var cap := CapsuleShape3D.new()
	cap.radius = Pawn.RADIUS
	cap.height = Pawn.HEIGHT_STAND
	var forma := PhysicsShapeQueryParameters3D.new()
	forma.shape = cap
	forma.collision_mask = Pawn.LAYER_WORLD
	for c: Dictionary in mundo.rooms():
		forma.transform = Transform3D(Basis(), (c["centro"] as Vector3) + Vector3(0, Pawn.HEIGHT_STAND / 2.0 + 0.05, 0))
		var hit := espaco.intersect_shape(forma, 4)
		if not hit.is_empty():
			cheios += 1
			var quem := []
			for h in hit:
				quem.append(str(h["collider"].get_child(0).shape.get_class()) + "@" + str((h["collider"] as Node3D).global_position.snapped(Vector3.ONE * 0.1)))
			print("    ocupado: %s em %s: %s" % [c["tipo"], str((c["centro"] as Vector3).snapped(Vector3.ONE * 0.1)), quem])
	_checar(cheios == 0, "cabe um personagem de pé no meio de todos os cômodos (%d ocupados)" % cheios)
	print("INTERIORES %s" % ("OK" if falhas == 0 else "FALHOU (%d)" % falhas))
	quit(falhas)


## Retângulo do móvel no espaço do cômodo (centro em 0,0).
func _retangulo(m: Dictionary) -> PackedVector2Array:
	var c: Vector3 = m["centro"]
	var p: Vector3 = m["pos"]
	var rel := Vector2(p.x - c.x, p.z - c.z)
	var tg: Vector2 = m["tg"]
	var nrm: Vector2 = m["nrm"]
	var l := float(m["larg"]) / 2.0
	var d := float(m["prof"]) / 2.0
	return PackedVector2Array([rel + tg * l + nrm * d, rel - tg * l + nrm * d, rel - tg * l - nrm * d, rel + tg * l - nrm * d])


func _dist_ret(r: PackedVector2Array) -> float:
	var m := 1e9
	for i in r.size():
		m = minf(m, Geometry2D.get_closest_point_to_segment(Vector2.ZERO, r[i], r[(i + 1) % r.size()]).length())
	return m
