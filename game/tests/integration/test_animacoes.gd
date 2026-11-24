extends SceneTree
## Animações da revisão 1.4 (rodando na Godot, com a AnimationTree de verdade):
##  - todos os trajes têm os clipes novos (caminhar, eliminado, reações das armas);
##  - parado/caminhada/corrida/sprint escolhidos pela velocidade replicada;
##  - a reação de tiro (aditiva, só no tronco) mexe o peito e volta ao normal, sem
##    mexer nas pernas;
##  - a cena de eliminação toca o clipe, o vento leva o corpo e ela se remove.
## Uso: godot --headless --fixed-fps 30 --path game -s res://tests/integration/test_animacoes.gd

const CLIPES := ["idle", "caminhar", "andar", "correr", "agachado", "agachado_andar", "pular", "queda", "aterrissar",
		"eliminado", "reacao_tiro", "reacao_recarga", "reacao_equipar", "acenar", "queda_livre", "planador"]
var falhas := 0


func _checar(ok: bool, msg: String) -> void:
	print(("  ok  " if ok else "  FALHOU  ") + msg)
	if not ok:
		falhas += 1


func _init() -> void:
	await process_frame
	# 1. clipes em todos os trajes
	var cfg := Cosmeticos.config()
	var faltando := []
	for t in cfg["trajes"]:
		var m := (load(cfg["trajes"][t]) as PackedScene).instantiate()
		var ap := m.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
		for c in CLIPES:
			if not ap.has_animation(c):
				faltando.append("%s/%s" % [t, c])
		m.free()
	_checar(faltando.is_empty(), "todos os %d trajes têm os %d clipes %s" % [cfg["trajes"].size(), CLIPES.size(), str(faltando)])
	# nenhuma peça perdida embaixo do chão (bug das sobrancelhas na origem, que
	# apareciam como um "X" atrás dos pés): malha em repouso acima de y = -1 cm
	var abaixo := []
	for t in cfg["trajes"]:
		var m := (load(cfg["trajes"][t]) as PackedScene).instantiate()
		for mi: MeshInstance3D in m.find_children("*", "MeshInstance3D", true, false):
			var aabb := mi.mesh.get_aabb()
			if aabb.position.y < -0.01:
				abaixo.append("%s (%.2f m)" % [t, aabb.position.y])
		m.free()
	_checar(abaixo.is_empty(), "nenhum traje tem geometria abaixo do chão %s" % str(abaixo))
	# baú: a tampa começa na altura do corpo (antes a tampa abaulada flutuava)
	var bau := (load("res://assets/baus_coletaveis/bau_ventania_01.glb") as PackedScene).instantiate() as Node3D
	var tampa := bau.find_child("tampa", true, false) as MeshInstance3D
	var ok_tampa := false
	var info := "sem nó 'tampa'"
	if tampa:
		var a := tampa.transform * tampa.mesh.get_aabb()
		ok_tampa = absf(a.position.y - 0.5) < 0.04 and a.end.y < 0.85
		info = "base %.2f m, topo %.2f m" % [a.position.y, a.end.y]
	_checar(ok_tampa, "tampa do baú assentada no corpo (%s)" % info)
	bau.free()

	# 2. estados de locomoção pela velocidade
	var v := PawnVisual.new()
	root.add_child(v)
	await process_frame
	var estados := {}
	for vel in [0.0, 1.6, 4.5, 6.5]:
		v.update_state(Vector3(0, 0, -vel), Protocol.F_ON_FLOOR, 0.0)
		for i in 6:
			await process_frame
		estados[vel] = v.current_animation()
	_checar(estados[0.0] == "idle" and estados[1.6] == "caminhar" and estados[4.5] == "andar" and estados[6.5] == "correr",
			"parado/caminhada/corrida/sprint pela velocidade: %s" % str(estados))

	# 3. reação de tiro: peito mexe, pernas não, e volta. Comparado com um gêmeo que
	# não atira (mesma fase do idle), para a respiração do idle não contar
	v.queue_free()
	var a := PawnVisual.new()
	var b := PawnVisual.new()
	root.add_child(a)
	root.add_child(b)
	await process_frame
	for p in [a, b]:
		p.update_state(Vector3.ZERO, Protocol.F_ON_FLOOR, 0.0)
		p.set_held(ItemDB.index_of("rajada"))
	for i in 30:
		await process_frame
	var ska := a.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var skb := b.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var chest := ska.find_bone("Chest")
	var coxa := ska.find_bone("LeftUpperLeg")
	var dif := func(osso: int) -> float: return ska.get_bone_pose_rotation(osso).angle_to(skb.get_bone_pose_rotation(osso))
	var inicial: float = dif.call(chest)
	a.fire()
	var maior := 0.0
	var coxa_maior := 0.0
	for i in 5:
		await process_frame
		maior = maxf(maior, dif.call(chest))
		coxa_maior = maxf(coxa_maior, dif.call(coxa))
	for i in 20:
		await process_frame
	var depois: float = dif.call(chest)
	_checar(inicial < deg_to_rad(0.5), "gêmeos começam iguais (%.2f°)" % rad_to_deg(inicial))
	_checar(maior > deg_to_rad(2.0), "o tiro dá coice no peito (%.1f°)" % rad_to_deg(maior))
	_checar(coxa_maior < deg_to_rad(1.0), "a reação não mexe nas pernas (%.2f°)" % rad_to_deg(coxa_maior))
	_checar(depois < deg_to_rad(1.0), "o peito volta depois do coice (%.2f°)" % rad_to_deg(depois))
	a.queue_free()
	b.queue_free()

	# 3b. giro no lugar: parado, olhando para os lados até o limite, os pés não saem
	# do lugar e o peito acompanha a mira; passando do limite, as pernas alcançam
	var g := PawnVisual.new()
	root.add_child(g)
	await process_frame
	g.update_state(Vector3.ZERO, Protocol.F_ON_FLOOR, 0.0)
	for i in 20:
		await process_frame
	var skg := g.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var pe := skg.find_bone("LeftFoot")
	var peito := skg.find_bone("Chest")
	var pe0 := (skg.global_transform * skg.get_bone_global_pose(pe)).origin
	var desliza := 0.0
	var cabeca := skg.find_bone("Head")
	var quadril := skg.find_bone("Hips")
	var cap := {}
	# a pose final (depois dos modificadores de mira) só existe dentro da atualização do esqueleto
	var ler := func():
		cap["pe"] = (skg.global_transform * skg.get_bone_global_pose(pe)).origin
		var c: Vector3 = (skg.global_transform.basis * skg.get_bone_global_pose(cabeca).basis).z
		var q: Vector3 = (skg.global_transform.basis * skg.get_bone_global_pose(quadril).basis).z
		cap["cab"] = atan2(-c.x, -c.z)
		cap["quad"] = atan2(-q.x, -q.z)
	skg.skeleton_updated.connect(ler)
	for i in 60:
		var yaw := sin(i * 0.2) * deg_to_rad(40.0)
		g.update_state(Vector3.ZERO, Protocol.F_ON_FLOOR, yaw)
		await process_frame
		if cap.has("pe"):
			desliza = maxf(desliza, ((cap["pe"] as Vector3) - pe0).length())
	# extremos da mira (+35° e -35°), segurando: a cabeça vira, o quadril não
	var med := {}
	for lado in [1, -1]:
		for i in 12:
			g.update_state(Vector3.ZERO, Protocol.F_ON_FLOOR, deg_to_rad(35.0) * lado)
			await process_frame
		med[lado] = [cap["cab"], cap["quad"]]
	skg.skeleton_updated.disconnect(ler)
	var vira_cab := rad_to_deg(absf(wrapf(med[1][0] - med[-1][0], -PI, PI)))
	var vira_quad := rad_to_deg(absf(wrapf(med[1][1] - med[-1][1], -PI, PI)))
	_checar(desliza < 0.05, "olhando para os lados (±40°) os pés ficam plantados (moveram %.3f m)" % desliza)
	_checar(vira_cab > 50.0 and vira_quad < 5.0, "mira de +35° a -35°: cabeça vira %.0f°, quadril (pernas) %.0f°" % [vira_cab, vira_quad])
	g.update_state(Vector3.ZERO, Protocol.F_ON_FLOOR, deg_to_rad(120.0))
	var t_alc := 0.0
	while absf(wrapf(float(g.get("_yaw_pernas")) - deg_to_rad(120.0), -PI, PI)) > deg_to_rad(5.0) and t_alc < 2.0:
		g.update_state(Vector3.ZERO, Protocol.F_ON_FLOOR, deg_to_rad(120.0))
		await process_frame
		t_alc += 1.0 / 30.0
	_checar(t_alc < 1.0, "virando 120°, as pernas alcançam o tronco em %.2f s" % t_alc)
	g.queue_free()

	# 4. eliminação: toca, o vento leva e a cena some sozinha
	var e := EliminacaoVisual.spawn(root, "", Transform3D(Basis(), Vector3(3, 0, 0)))
	var ap_e := e.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	await process_frame
	_checar(ap_e.current_animation == "eliminado", "a eliminação toca o clipe 'eliminado' (%s)" % ap_e.current_animation)
	var t := 0.0
	while is_instance_valid(e) and t < 6.0:
		await process_frame
		t += 1.0 / 30.0
	_checar(not is_instance_valid(e), "a cena de eliminação se remove sozinha (%.1f s)" % t)
	print("ANIMACOES %s" % ("OK" if falhas == 0 else "FALHOU (%d)" % falhas))
	quit(falhas)
