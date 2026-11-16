extends SceneTree
## Roda o benchmark real da vitrine (precisa de janela: xvfb-run no Linux sem tela)
## e confirma que o limite de FPS é liberado durante o teste e restaurado depois.


func _init() -> void:
	await process_frame
	root.theme = VentaniaTheme.build(false)
	await root.get_node("SceneManager").go("diagnostics")
	var cena := current_scene
	var limite_antes := Engine.max_fps
	cena._iniciar_bench()
	await create_timer(3.0).timeout
	var liberado := Engine.max_fps == 0
	while cena._bench_ativo:
		await process_frame
	var restaurado := Engine.max_fps == limite_antes
	print(cena._ultimo_resumo)
	print("BENCH liberado=%s restaurado=%s" % [liberado, restaurado])
	quit(0 if liberado and restaurado else 1)
