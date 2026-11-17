extends SceneTree
## Capturas e teste de aceitação da loja (Etapa 13) com um meta-servidor de verdade.
## Para CADA cosmético do catálogo: tela de detalhes (visualizador 3D com o modelo
## real; trajes também em "rosto" e "costas"). Depois compra pela interface (tela de
## confirmação → CONFIRMAR) cada item da loja do dia, e equipa cada um.
## Precisa de janela (xvfb-run). A conta deve existir e ter Faíscas.
## Uso: godot --path game --rendering-driver opengl3 -s res://tests/capturar_loja.gd -- <pasta> <url_meta> <usuario> <senha>

var _falhas: Array[String] = []


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var pasta: String = a[0]
	await process_frame
	var meta = root.get_node("Meta")
	var sm = root.get_node("SceneManager")
	root.theme = VentaniaTheme.build(root.get_node("Settings").is_mobile)
	meta.base_url = a[1]
	var r = await meta.login(a[2], a[3])
	_conferir(r["ok"], "login")
	await sm.go("menu")
	await _esperar(40)
	var menu = root.get_child(root.get_child_count() - 1)
	menu._abrir_loja()
	await _esperar(60)
	_foto(pasta, "loja")
	# detalhes de todos os cosméticos com modelo
	var precos: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://").path_join("../backend/config/shop/loja.json")))["precos"]
	for it: Dictionary in _catalogo():
		if VitrineCosmetico.imagem(it["id"]) == null:
			continue
		it["tem"] = false
		it["preco"] = int(precos.get(it["raridade"], 0))
		menu._previa_item(it)
		await _esperar(30)
		_foto(pasta, "detalhe_" + it["id"])
		if it["categoria"] == "traje":
			var vit: VitrineCosmetico = menu.find_children("*", "VitrineCosmetico", true, false)[0]
			vit.enquadrar("rosto")
			await _esperar(40)
			_foto(pasta, "rosto_" + it["id"])
			vit.enquadrar("costas")
			await _esperar(50)
			_foto(pasta, "costas_" + it["id"])
	# compra de cada item da loja pela interface, com confirmação
	var lj = await meta.get_shop()
	for sec: Dictionary in lj["data"]["secoes"]:
		for it: Dictionary in sec["itens"]:
			if it["tem"]:
				continue
			var antes := int(meta.profile["sparks"])
			menu._confirmar_compra(it)
			await _esperar(20)
			_foto(pasta, "confirmar_" + it["id"])
			var ok := _botao(menu, "CONFIRMAR")
			_conferir(ok != null, "botão CONFIRMAR de " + it["id"])
			if ok == null:
				continue
			ok.pressed.emit()
			await _esperar_ate(func(): return _botao(menu, "EQUIPAR AGORA") != null, 300)
			_foto(pasta, "comprado_" + it["id"])
			_conferir(int(meta.profile["sparks"]) == antes - int(it["preco"]), "saldo após comprar " + it["id"])
			var eq := _botao(menu, "EQUIPAR AGORA")
			_conferir(eq != null, "botão EQUIPAR AGORA de " + it["id"])
			if eq:
				eq.pressed.emit()
				await _esperar_ate(func(): return meta.profile["equipped"].get(it["categoria"], "") == it["id"], 300)
				_conferir(meta.profile["equipped"].get(it["categoria"], "") == it["id"], "equipou " + it["id"])
	# comprar de novo não cobra duas vezes (a loja já marca "JÁ É SEU")
	lj = await meta.get_shop()
	for sec: Dictionary in lj["data"]["secoes"]:
		for it: Dictionary in sec["itens"]:
			_conferir(it["tem"], "item da loja marcado como seu: " + it["id"])
	menu._fechar_modal()
	await _esperar(40)
	_foto(pasta, "lobby_equipado")
	menu._abrir_loja()
	await _esperar(60)
	_foto(pasta, "loja_depois")
	menu._abrir_perfil()
	await _esperar(60)
	_foto(pasta, "colecao")
	menu._fechar_modal()
	menu._abrir_passe()
	await _esperar(60)
	_foto(pasta, "passe")
	print("LOJA_OK" if _falhas.is_empty() else "LOJA_FALHOU %s" % [_falhas])
	quit(0 if _falhas.is_empty() else 1)


func _catalogo() -> Array:
	var pasta := ProjectSettings.globalize_path("res://").path_join("../backend/config/catalog")
	var out := []
	for f in DirAccess.get_files_at(pasta):
		if f.ends_with(".json"):
			out.append_array(JSON.parse_string(FileAccess.get_file_as_string(pasta.path_join(f))).get("itens", []))
	return out


func _botao(raiz: Node, texto: String) -> Button:
	for b in raiz.find_children("*", "Button", true, false):
		if (b as Button).text == texto and b.is_visible_in_tree() and not (b as Button).disabled:
			return b
	return null


func _conferir(cond: bool, o_que: String) -> void:
	if not cond:
		_falhas.append(o_que)
		print("FALHA ", o_que)


func _esperar(n: int) -> void:
	for i in n:
		await process_frame


func _esperar_ate(f: Callable, n: int) -> void:
	for i in n:
		if f.call():
			return
		await process_frame


func _foto(pasta: String, nome: String) -> void:
	root.get_texture().get_image().save_png("%s/%s.png" % [pasta, nome])
	print("CAPTURA ", nome)
