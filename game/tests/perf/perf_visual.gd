extends SceneTree
## Custo de CPU do visual do personagem (AnimationTree + mira + IK nos dois braços).
## Uso: godot --headless --path game -s res://tests/perf/perf_visual.gd -- [N=16]


func _init() -> void:
	var n := int(OS.get_cmdline_user_args()[0]) if OS.get_cmdline_user_args().size() > 0 else 16
	Engine.max_fps = 0          # mede o custo, não a espera pelo próximo quadro
	var vis: Array[PawnVisual] = []
	for i in n:
		var v := PawnVisual.new()
		v.position = Vector3(i * 2.0, 0, 0)
		root.add_child(v)
		vis.append(v)
	await process_frame
	Engine.max_fps = 0          # (de novo: o autoload Settings reaplica o limite ao iniciar)
	var itens := ["rajada", "faisca", "trovao", "zumbido", "gaviao", "celula_p", "picareta"]
	for i in n:
		vis[i].set_held(ItemDB.index_of(itens[i % itens.size()]))
	var tempos := PackedFloat64Array()
	for f in 240:
		var ini := Time.get_ticks_usec()
		for i in n:
			var v := vis[i]
			v.update_state(Vector3(0, 0, -4.5 + (i % 3) * 2.0), Protocol.F_ON_FLOOR, 0.0)
			v.set_aim(sin(f * 0.05) * 0.4, i % 2 == 0)
			var acao := Protocol.ACT_SWING if i % 7 == 6 else (Protocol.ACT_RELOAD if i % 4 == 0 else 0)
			v.set_action(acao, fmod(f / 60.0, 1.0))
		await process_frame
		tempos.append((Time.get_ticks_usec() - ini) / 1000.0)
	var total := 0.0
	for t in tempos.slice(40):
		total += t
	var media := total / (tempos.size() - 40)
	print("PERF_VISUAL personagens=%d quadro_medio=%.2f ms (%.3f ms por personagem, inclui o quadro inteiro)" % [n, media, media / n])
	quit()
