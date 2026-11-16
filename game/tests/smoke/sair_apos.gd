class_name SairApos
extends Node
## Diagnóstico: abre cada cena por 2 s e fecha o jogo (para isolar falhas no
## encerramento). Uso: ./ventania --headless -- --sair-apos=menu,game,menu


func run(tree: SceneTree, cenas: PackedStringArray) -> void:
	name = "SairApos"
	tree.root.add_child.call_deferred(self)
	await tree.process_frame
	for cena in cenas:
		var modo := OS.get_environment("VENTANIA_MODO")
		await SceneManager.go(cena, {"modo": modo if not modo.is_empty() else "local", "host": "127.0.0.1", "porta": 9})
		await tree.create_timer(2.0).timeout
	print("SAIR_APOS_OK")
	tree.quit(0)
