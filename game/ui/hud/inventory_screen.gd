class_name InventoryScreen
extends Control
## Tela de inventário (abre e fecha durante a partida). Mostra a picareta (fixa),
## os 5 espaços, munição, materiais e itens próximos, com detalhes do item em foco.
## Não altera nada sozinha: cada ação vira um pedido (`request`) que o servidor
## valida; o resultado chega por `show_result` e o estado novo por `update_status`.
##
## Funciona com mouse (clique e arrastar e soltar), teclado/controle (foco +
## confirmar; os botões cobrem tudo) e toque (toques nos espaços e botões).
## Fluxo de "Mover": escolha um espaço, aperte Mover e depois o destino.

signal request(op: Dictionary)
signal close_requested

const TAM_ESPACO := Vector2(96, 96)
const COR_PAINEL := Color(0.05, 0.22, 0.25, 0.94)

var _status := {}
var _espacos: Array[ItemSlot] = []
var _picareta: ItemSlot
var _foco := {"tipo": "espaco", "i": 0}
var _ultimo_espaco := 0              # espaço convencional mais recente em foco (para "Trocar")
var _movendo := -1                   # origem de "Mover" (-1 = não está movendo)
var _qtd := 1
var _proximos: Array = []            # [{"id","item","rarity","count","ammo","pos"}]
var _ids_proximos := []
var _pendente := false

var _det_icone: TextureRect
var _det_nome: Label
var _det_sub: Label
var _det_info: Label
var _det_qtd: Label
var _btn_equipar: Button
var _btn_mover: Button
var _btn_dividir: Button
var _btn_largar: Button
var _linha_qtd: HBoxContainer
var _qtd_txt: Label
var _qtd_slider: HSlider
var _aviso: Label
var _lista_municao: VBoxContainer
var _lista_materiais: VBoxContainer
var _lista_proximos: VBoxContainer
var _sem_proximos: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var fundo := ColorRect.new()
	fundo.color = Color(0.02, 0.08, 0.1, 0.55)
	fundo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(fundo)

	var margem := MarginContainer.new()
	margem.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for lado in ["left", "right", "top", "bottom"]:
		margem.add_theme_constant_override("margin_" + lado, 28)
	add_child(margem)
	var painel := PanelContainer.new()
	painel.add_theme_stylebox_override("panel", _caixa(COR_PAINEL, 18))
	margem.add_child(painel)
	var raiz := VBoxContainer.new()
	raiz.add_theme_constant_override("separation", 12)
	painel.add_child(raiz)

	# cabeçalho
	var topo := HBoxContainer.new()
	raiz.add_child(topo)
	var titulo := Label.new()
	titulo.text = "Inventário"
	titulo.theme_type_variation = "Titulo"
	titulo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	topo.add_child(titulo)
	var fechar := Button.new()
	fechar.text = "Fechar"
	fechar.pressed.connect(func(): close_requested.emit())
	topo.add_child(fechar)

	var corpo := HBoxContainer.new()
	corpo.size_flags_vertical = Control.SIZE_EXPAND_FILL
	corpo.add_theme_constant_override("separation", 22)
	raiz.add_child(corpo)

	# ---- coluna esquerda: equipamentos, reservas, itens próximos ----
	var rolar := ScrollContainer.new()
	rolar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rolar.size_flags_stretch_ratio = 1.6
	rolar.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	corpo.add_child(rolar)
	var esq := VBoxContainer.new()
	esq.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	esq.add_theme_constant_override("separation", 10)
	rolar.add_child(esq)
	esq.add_child(_titulo_secao("Equipamentos"))
	var barra := HBoxContainer.new()
	barra.add_theme_constant_override("separation", 10)
	esq.add_child(barra)
	_picareta = _novo_espaco(Inventory.PICKAXE)
	barra.add_child(_picareta)
	var sep := Control.new()
	sep.custom_minimum_size.x = 8
	barra.add_child(sep)
	for i in Inventory.SLOTS:
		var e := _novo_espaco(i)
		barra.add_child(e)
		_espacos.append(e)

	var reservas := HBoxContainer.new()
	reservas.add_theme_constant_override("separation", 24)
	esq.add_child(reservas)
	var col_m := VBoxContainer.new()
	col_m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reservas.add_child(col_m)
	col_m.add_child(_titulo_secao("Munição"))
	_lista_municao = VBoxContainer.new()
	col_m.add_child(_lista_municao)
	for i in ItemDB.ammo_types().size():
		_lista_municao.add_child(_linha_reserva("municao", i))
	var col_mat := VBoxContainer.new()
	col_mat.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reservas.add_child(col_mat)
	col_mat.add_child(_titulo_secao("Materiais"))
	_lista_materiais = VBoxContainer.new()
	col_mat.add_child(_lista_materiais)
	for i in ItemDB.material_types().size():
		_lista_materiais.add_child(_linha_reserva("material", i))
	var nota := Label.new()
	nota.theme_type_variation = "Pequeno"
	nota.text = "Coletados com a picareta (Etapa 5)."
	nota.modulate.a = 0.7
	col_mat.add_child(nota)

	esq.add_child(_titulo_secao("Itens próximos"))
	_lista_proximos = VBoxContainer.new()
	_lista_proximos.add_theme_constant_override("separation", 6)
	esq.add_child(_lista_proximos)
	_sem_proximos = Label.new()
	_sem_proximos.theme_type_variation = "Pequeno"
	_sem_proximos.text = "Nenhum item ao alcance."
	_sem_proximos.modulate.a = 0.7
	esq.add_child(_sem_proximos)

	# ---- coluna direita: detalhes e ações do item em foco ----
	var det := PanelContainer.new()
	det.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	det.add_theme_stylebox_override("panel", _caixa(Color(0.03, 0.15, 0.18, 0.9), 14))
	corpo.add_child(det)
	var dv := VBoxContainer.new()
	dv.add_theme_constant_override("separation", 8)
	det.add_child(dv)
	_det_icone = TextureRect.new()
	_det_icone.custom_minimum_size = Vector2(150, 150)
	_det_icone.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_det_icone.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	dv.add_child(_det_icone)
	_det_nome = Label.new()
	_det_nome.theme_type_variation = "Subtitulo"
	_det_nome.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dv.add_child(_det_nome)
	_det_sub = Label.new()
	_det_sub.theme_type_variation = "Pequeno"
	dv.add_child(_det_sub)
	_det_info = Label.new()
	_det_info.theme_type_variation = "Pequeno"
	_det_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dv.add_child(_det_info)
	_det_qtd = Label.new()
	dv.add_child(_det_qtd)

	_linha_qtd = HBoxContainer.new()
	dv.add_child(_linha_qtd)
	var menos := Button.new()
	menos.text = " − "
	menos.pressed.connect(func(): _set_qtd(_qtd - 1))
	_linha_qtd.add_child(menos)
	_qtd_slider = HSlider.new()
	_qtd_slider.min_value = 1
	_qtd_slider.step = 1
	_qtd_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_qtd_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_qtd_slider.value_changed.connect(func(v): _set_qtd(int(v)))
	_linha_qtd.add_child(_qtd_slider)
	var mais := Button.new()
	mais.text = " + "
	mais.pressed.connect(func(): _set_qtd(_qtd + 1))
	_linha_qtd.add_child(mais)
	_qtd_txt = Label.new()
	_qtd_txt.custom_minimum_size.x = 56
	_qtd_txt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_linha_qtd.add_child(_qtd_txt)

	var acoes := GridContainer.new()
	acoes.columns = 2
	acoes.add_theme_constant_override("h_separation", 8)
	acoes.add_theme_constant_override("v_separation", 8)
	dv.add_child(acoes)
	_btn_equipar = _botao(acoes, "Equipar", _equipar)
	_btn_mover = _botao(acoes, "Mover", _mover)
	_btn_dividir = _botao(acoes, "Dividir", _dividir)
	_btn_largar = _botao(acoes, "Largar", _largar)
	_aviso = Label.new()
	_aviso.theme_type_variation = "Pequeno"
	_aviso.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_aviso.add_theme_color_override("font_color", Color("ffd27a"))
	dv.add_child(_aviso)
	var ajuda := Label.new()
	ajuda.theme_type_variation = "Pequeno"
	ajuda.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ajuda.modulate.a = 0.65
	ajuda.text = "Arraste um item para outro espaço ou use Mover. A picareta é permanente."
	dv.add_child(ajuda)
	visible = false


func _caixa(cor: Color, raio: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = cor
	sb.set_corner_radius_all(raio)
	sb.set_content_margin_all(16)
	sb.set_border_width_all(2)
	sb.border_color = Color(1, 1, 1, 0.12)
	return sb


func _titulo_secao(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.theme_type_variation = "Subtitulo"
	return l


func _botao(pai: Control, texto: String, acao: Callable) -> Button:
	var b := Button.new()
	b.text = texto
	b.custom_minimum_size = Vector2(150, 48)
	b.pressed.connect(acao)
	pai.add_child(b)
	return b


func _novo_espaco(i: int) -> ItemSlot:
	var e := ItemSlot.new()
	e.indice = i
	e.tamanho = TAM_ESPACO
	e.focus_mode = Control.FOCUS_ALL
	e.arrastavel = i != Inventory.PICKAXE
	e.tapped.connect(func(): _tocar_espaco(i))
	e.focus_entered.connect(func(): _focar({"tipo": "picareta"} if i == Inventory.PICKAXE else {"tipo": "espaco", "i": i}))
	e.dropped_on.connect(func(origem): _pedir({"op": Protocol.OP_SWAP, "a": origem, "b": i}))
	return e


func _linha_reserva(tipo: String, idx: int) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var icone := TextureRect.new()
	icone.custom_minimum_size = Vector2(36, 36)
	icone.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icone.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icone.texture = ItemSlot.icone_de("municao") if tipo == "municao" else null
	h.add_child(icone)
	var nome := Label.new()
	nome.name = "Nome"
	nome.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(nome)
	var b := Button.new()
	b.name = "Botao"
	b.text = "Ver"
	b.focus_entered.connect(func(): _focar({"tipo": tipo, "t": idx}))
	b.pressed.connect(func(): _focar({"tipo": tipo, "t": idx}))
	h.add_child(b)
	return h


# ---------- estado ----------

func is_open() -> bool:
	return visible


func open() -> void:
	visible = true
	_movendo = -1
	_aviso.text = ""
	_atualizar()
	(_picareta if _foco["tipo"] == "picareta" else _espacos[_foco.get("i", 0) if _foco["tipo"] == "espaco" else 0]).grab_focus()


func close() -> void:
	visible = false
	_movendo = -1


func update_status(st: Dictionary) -> void:
	_status = st
	_pendente = false
	if visible:
		_atualizar()


## Itens no chão ao alcance (o jogo atualiza enquanto a tela está aberta).
func set_nearby(lista: Array) -> void:
	var ids := lista.map(func(l): return [l["id"], l["count"]])
	if ids == _ids_proximos:
		return
	_ids_proximos = ids
	_proximos = lista
	if visible:
		_montar_proximos()
		if _foco["tipo"] == "loot" and not _proximos.any(func(l): return l["id"] == _foco["id"]):
			_focar({"tipo": "espaco", "i": _ultimo_espaco})


## Resultado do servidor para um pedido (Inventory.Err).
func show_result(code: int) -> void:
	_pendente = false
	_aviso.text = Inventory.MENSAGENS.get(code, "")


func _slot(i: int) -> Dictionary:
	var lista: Array = _status.get("slots", [])
	return lista[i] if i >= 0 and i < lista.size() else {"item": 0, "rarity": 0, "mag": 0, "count": 0}


func _atualizar() -> void:
	if _status.is_empty():
		return
	var sel: int = _status["selected"]
	_picareta.set_item(Inventory.PICKAXE_ID, 0, "", sel == Protocol.SELECTED_PICKAXE)
	for i in Inventory.SLOTS:
		var sl := _slot(i)
		var id := ItemDB.id_of(sl["item"])
		var qtd := ""
		if ItemDB.is_weapon(id):
			qtd = str(sl["mag"])
		elif not id.is_empty():
			qtd = "x%d" % sl["count"]
		_espacos[i].set_item(id, sl["rarity"], qtd, i == sel)
		_espacos[i].marcado = i == _movendo
	var tipos := ItemDB.ammo_types()
	for i in tipos.size():
		var n: int = _status["ammo"][i] if i < _status["ammo"].size() else 0
		var linha := _lista_municao.get_child(i)
		(linha.get_node("Nome") as Label).text = "%s  %d / %d" % [ItemDB.ammo(tipos[i])["nome"], n, ItemDB.stack_limit(tipos[i])]
	var mats := ItemDB.material_types()
	for i in mats.size():
		var lista_m: Array = _status.get("materials", [])
		var n: int = lista_m[i] if i < lista_m.size() else 0
		var linha := _lista_materiais.get_child(i)
		(linha.get_node("Nome") as Label).text = "%s  %d / %d" % [ItemDB.material(mats[i])["nome"], n, ItemDB.stack_limit(mats[i])]
	_montar_proximos()
	_detalhes()


func _montar_proximos() -> void:
	for c in _lista_proximos.get_children():
		c.queue_free()
	_sem_proximos.visible = _proximos.is_empty()
	for l in _proximos:
		var id := ItemDB.id_of(l["item"])
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 10)
		var fundo := ColorRect.new()
		fundo.custom_minimum_size = Vector2(52, 52)
		fundo.color = ItemDB.rarity_color(l["rarity"]).darkened(0.25) if ItemDB.is_weapon(id) else Color("5d6b79")
		h.add_child(fundo)
		var ic := TextureRect.new()
		ic.texture = ItemSlot.icone_de(id)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		fundo.add_child(ic)
		var nome := Label.new()
		nome.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nome.text = ItemDB.display_name(id, l["rarity"] if ItemDB.is_weapon(id) else -1) + ("" if l["count"] <= 1 else "  x%d" % l["count"])
		nome.add_theme_color_override("font_color", ItemDB.rarity_color(l["rarity"]).lightened(0.3) if ItemDB.is_weapon(id) else Color.WHITE)
		h.add_child(nome)
		var b := Button.new()
		b.text = _texto_pegar(l)
		b.custom_minimum_size.x = 150
		var lid: int = l["id"]
		b.focus_entered.connect(func(): _focar({"tipo": "loot", "id": lid}))
		b.pressed.connect(func(): _pegar(lid))
		h.add_child(b)
		_lista_proximos.add_child(h)


# ---------- foco e detalhes ----------

func _focar(f: Dictionary) -> void:
	_foco = f
	if f["tipo"] == "espaco":
		_ultimo_espaco = f["i"]
	_set_qtd(_qtd)
	_detalhes()


func _tocar_espaco(i: int) -> void:
	if _movendo >= 0 and i != Inventory.PICKAXE:
		if i != _movendo:
			_pedir({"op": Protocol.OP_SWAP, "a": _movendo, "b": i})
		_movendo = -1
		_atualizar()
		return
	if i == Inventory.PICKAXE:
		_picareta.grab_focus()
	else:
		_espacos[i].grab_focus()
	_focar({"tipo": "picareta"} if i == Inventory.PICKAXE else {"tipo": "espaco", "i": i})


func _detalhes() -> void:
	var t: String = _foco["tipo"]
	var id := ""
	var raridade := -1
	var qtd := 0
	var limite := 1
	var info := ""
	match t:
		"picareta":
			id = Inventory.PICKAXE_ID
			info = "Equipamento permanente: fica sempre no primeiro espaço, não cai ao ser eliminado e não pode ser largado nem trocado.\nGolpeia o que estiver na mira (até %.1f m)." % Combat.melee_range()
		"espaco":
			var sl := _slot(_foco["i"])
			id = ItemDB.id_of(sl["item"])
			if not id.is_empty():
				raridade = sl["rarity"] if ItemDB.is_weapon(id) else -1
				qtd = sl["count"] if not ItemDB.is_weapon(id) else 1
				limite = ItemDB.stack_limit(id)
				info = _info_item(id, sl)
		"municao":
			var tipo: String = ItemDB.ammo_types()[_foco["t"]]
			qtd = _status["ammo"][_foco["t"]] if _foco["t"] < _status.get("ammo", []).size() else 0
			limite = ItemDB.stack_limit(tipo)
			_det_icone.texture = ItemSlot.icone_de("municao")
			_det_nome.text = ItemDB.ammo(tipo)["nome"]
			_det_sub.text = "Munição · reserva fora dos espaços"
			_det_info.text = "Coletada automaticamente ao passar por cima."
		"material":
			var tipo: String = ItemDB.material_types()[_foco["t"]]
			var lm: Array = _status.get("materials", [])
			qtd = lm[_foco["t"]] if _foco["t"] < lm.size() else 0
			limite = ItemDB.stack_limit(tipo)
			_det_icone.texture = null
			_det_nome.text = ItemDB.material(tipo)["nome"]
			_det_sub.text = "Material de construção"
			_det_info.text = "Coletado com a picareta e usado para construir (Etapa 5)."
		"loot":
			var l: Dictionary = {}
			for x in _proximos:
				if x["id"] == _foco["id"]:
					l = x
			if not l.is_empty():
				id = ItemDB.id_of(l["item"])
				raridade = l["rarity"] if ItemDB.is_weapon(id) else -1
				qtd = l["count"]
				limite = ItemDB.stack_limit(id)
				info = "No chão. " + _texto_pegar(l) + "."
	if t in ["picareta", "espaco", "loot"]:
		_det_icone.texture = ItemSlot.icone_de(id)
		if id.is_empty():
			_det_nome.text = "Espaço %d vazio" % (_foco["i"] + 1) if t == "espaco" else ""
			_det_sub.text = "Pegue um item do chão ou de um baú para ocupá-lo."
			_det_info.text = ""
		else:
			_det_nome.text = ItemDB.display_name(id)
			var cor := ItemDB.rarity_color(raridade) if raridade >= 0 else Color.WHITE
			_det_nome.add_theme_color_override("font_color", cor.lightened(0.3))
			var cat: String = {"armas": "Arma", "consumiveis": "Consumível", "ferramentas": "Ferramenta permanente"}.get(ItemDB.category(id), "")
			_det_sub.text = cat + (" · " + ItemDB.rarity(raridade)["nome"] if raridade >= 0 else "")
			_det_info.text = info
	if t == "municao" or t == "material" or (t != "picareta" and not id.is_empty() and not ItemDB.is_weapon(id)):
		_det_qtd.text = "Quantidade: %d / %d" % [qtd, limite]
	else:
		_det_qtd.text = ""
	# ações disponíveis
	var espaco_cheio := t == "espaco" and not id.is_empty()
	var pilha := espaco_cheio and ItemDB.is_consumable(id)
	_btn_equipar.visible = t == "picareta" or espaco_cheio
	_btn_equipar.disabled = (t == "picareta" and _status.get("selected", -1) == Protocol.SELECTED_PICKAXE) \
			or (espaco_cheio and _status.get("selected", -1) == _foco["i"])
	_btn_mover.visible = t == "espaco"
	_btn_mover.disabled = _status.is_empty()
	_btn_mover.text = "Cancelar" if _movendo >= 0 else "Mover"
	_btn_dividir.visible = pilha
	_btn_dividir.disabled = not pilha or qtd < 2
	_btn_largar.visible = t != "loot"
	_btn_largar.disabled = t == "picareta" or (t == "espaco" and id.is_empty()) or ((t == "municao" or t == "material") and qtd <= 0)
	_btn_largar.tooltip_text = Inventory.MENSAGENS[Inventory.Err.NOT_DROPPABLE] if t == "picareta" else ""
	var com_qtd := (pilha and qtd > 1) or ((t == "municao" or t == "material") and qtd > 1)
	_linha_qtd.visible = com_qtd
	if com_qtd:
		_qtd_slider.max_value = qtd
		_set_qtd(clampi(_qtd, 1, qtd))
	if t == "picareta":
		_aviso.text = Inventory.MENSAGENS[Inventory.Err.NOT_DROPPABLE] if _aviso.text.is_empty() else _aviso.text
	if _movendo >= 0:
		_aviso.text = "Escolha o espaço de destino para o item do espaço %d." % (_movendo + 1)


func _info_item(id: String, sl: Dictionary) -> String:
	if ItemDB.is_weapon(id):
		var w := ItemDB.weapon(id)
		var dano := ItemDB.damage(id, sl["rarity"])
		var proj := "" if int(w["projeteis"]) <= 1 else " x%d" % int(w["projeteis"])
		return "Dano %d%s · %.1f tiros/s\nPente %d / %d · %s\nRecarga %.1f s" % [roundi(dano), proj, float(w["cadencia"]),
				sl["mag"], int(w["pente"]), ItemDB.ammo(w["municao"])["nome"], ItemDB.reload_time(id, sl["rarity"])]
	var c := ItemDB.consumable(id)
	var efeito := "+%d de vida (até %d)" % [int(c["vida"]), int(c["limite"])] if c.has("vida") \
			else "+%d de escudo (até %d)" % [int(c["escudo"]), int(c["limite"])]
	return "%s · uso em %.1f s\nPilha de até %d." % [efeito, float(c["tempo_s"]), ItemDB.stack_limit(id)]


func _texto_pegar(l: Dictionary) -> String:
	var id := ItemDB.id_of(l["item"])
	var inv := _inv_local()
	if inv.room_for(id) > 0:
		return "Pegar"
	if _slot(_ultimo_espaco)["item"] != 0:
		return "Trocar pelo espaço %d" % (_ultimo_espaco + 1)
	return "Sem espaço"


## Cópia local (só leitura) do inventário a partir do status, para prever rótulos.
func _inv_local() -> Inventory:
	var inv := Inventory.new()
	for i in Inventory.SLOTS:
		var sl := _slot(i)
		var id := ItemDB.id_of(sl["item"])
		if not id.is_empty():
			inv.slots[i] = inv._novo(id, sl["rarity"], maxi(1, sl["count"]), sl["mag"])
	return inv


func _set_qtd(n: int) -> void:
	_qtd = maxi(1, n)
	if _linha_qtd and _linha_qtd.visible:
		_qtd = clampi(_qtd, 1, int(_qtd_slider.max_value))
		_qtd_slider.set_value_no_signal(_qtd)
	if _qtd_txt:
		_qtd_txt.text = str(_qtd)


# ---------- ações (pedidos ao servidor) ----------

func _pedir(op: Dictionary) -> void:
	_pendente = true
	_aviso.text = ""
	request.emit(op)


func _equipar() -> void:
	if _foco["tipo"] == "picareta":
		request.emit({"op": -1, "a": Inventory.PICKAXE})       # seleção vai pela entrada (InputCmd.slot)
	elif _foco["tipo"] == "espaco":
		request.emit({"op": -1, "a": _foco["i"]})


func _mover() -> void:
	if _foco["tipo"] != "espaco":
		return
	_movendo = -1 if _movendo >= 0 else _foco["i"]
	_atualizar()


func _dividir() -> void:
	if _foco["tipo"] == "espaco":
		_pedir({"op": Protocol.OP_SPLIT, "a": _foco["i"], "n": _qtd})


func _largar() -> void:
	match _foco["tipo"]:
		"picareta":
			show_result(Inventory.Err.NOT_DROPPABLE)
		"espaco":
			var sl := _slot(_foco["i"])
			var n: int = _qtd if _linha_qtd.visible else sl["count"]
			_pedir({"op": Protocol.OP_DROP, "a": _foco["i"], "n": maxi(1, n)})
		"municao":
			_pedir({"op": Protocol.OP_DROP_AMMO, "a": _foco["t"], "n": _qtd if _linha_qtd.visible else 1})
		"material":
			_pedir({"op": Protocol.OP_DROP_MATERIAL, "a": _foco["t"], "n": _qtd if _linha_qtd.visible else 1})


func _pegar(loot_id: int) -> void:
	var l: Dictionary = {}
	for x in _proximos:
		if x["id"] == loot_id:
			l = x
	if l.is_empty():
		return
	var troca := Protocol.SEM_ESPACO
	if _inv_local().room_for(ItemDB.id_of(l["item"])) <= 0:
		if _slot(_ultimo_espaco)["item"] == 0:
			show_result(Inventory.Err.FULL)
			return
		troca = _ultimo_espaco
	_pedir({"op": Protocol.OP_PICKUP, "loot": loot_id, "b": troca})


func _unhandled_input(e: InputEvent) -> void:
	if not visible:
		return
	if e.is_action_pressed("ui_cancel"):
		if _movendo >= 0:
			_movendo = -1
			_atualizar()
		else:
			close_requested.emit()
		get_viewport().set_input_as_handled()
