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
