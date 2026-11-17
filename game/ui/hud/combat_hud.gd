class_name CombatHud
extends Control
## HUD de combate: vida/escudo, barra de equipamentos (picareta + 5 espaços), barra de ação
## (recarga/uso), aviso de interação, feed de eliminações, tela de eliminado e
## marcador de acerto. Só mostra o que o servidor informa (status).

signal slot_tapped(i: int)          # 0..4 ou Inventory.PICKAXE

const VERDE := Color("5fd35a")
const AZUL := Color("3fa2ff")
const FUNDO := Color(0.06, 0.31, 0.34, 0.75)

var _vida: ProgressBar
var _escudo: ProgressBar
var _vida_txt: Label
var _slots: Array[ItemSlot] = []
var _picareta: ItemSlot
var _mensagem: Label
var _mensagem_t := 0.0
var _nome_item: Label
var _balao: Control
var _balao_tecla := ""
var _balao_texto := ""
var _balao_prog := -1.0
var _balao_cor := Color.WHITE
var _municao: Label
var _acao: ProgressBar
var _acao_txt: Label
var _aviso: Label
var _feed: VBoxContainer
var _vit: VBoxContainer
var _barra_itens: HBoxContainer
var _toque := false
var _eliminado: Label
var _marcador: Control
var _marcador_t := 0.0
var _marcador_cabeca := false
var _dano_t := 0.0
var _vinheta: ColorRect
var _status := {}
var _acao_fim := 0.0
var _acao_total := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_vinheta = ColorRect.new()
	_vinheta.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vinheta.color = Color(0.85, 0.1, 0.1, 0.0)
	_vinheta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_vinheta)

	# vida e escudo (canto inferior esquerdo)
	var vit := VBoxContainer.new()
	vit.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 16)
	vit.grow_vertical = Control.GROW_DIRECTION_BEGIN
	vit.add_theme_constant_override("separation", 4)
	vit.custom_minimum_size.x = 260
	vit.position.y -= 40
	add_child(vit)
	_vit = vit
	vit.add_theme_constant_override("separation", 9)
	_escudo = _barra(AZUL, 20, true)
	vit.add_child(_escudo)
	_vida = _barra(VERDE, 26, true)
	vit.add_child(_vida)
	_vida_txt = Label.new()
	_vida_txt.theme_type_variation = "Pequeno"
	_contorno(_vida_txt)
	vit.add_child(_vida_txt)

	# inventário (centro inferior)
	var barra := HBoxContainer.new()
	_barra_itens = barra
	barra.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 40)
	barra.grow_horizontal = Control.GROW_DIRECTION_BOTH
	barra.grow_vertical = Control.GROW_DIRECTION_BEGIN
	barra.add_theme_constant_override("separation", 6)
	add_child(barra)
	barra.add_theme_constant_override("separation", 10)
	# 1º espaço, à extrema esquerda: a picareta (permanente, fora dos 5 espaços)
	_picareta = ItemSlot.new()
	_picareta.indice = Inventory.PICKAXE
	_picareta.tapped.connect(func(): slot_tapped.emit(Inventory.PICKAXE))
	barra.add_child(_picareta)
	var sep := Control.new()
	sep.custom_minimum_size.x = 6
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	barra.add_child(sep)
	for i in Inventory.SLOTS:
		var b := ItemSlot.new()
		b.indice = i
		b.tapped.connect(func(): slot_tapped.emit(i))
		barra.add_child(b)
		_slots.append(b)
	_nome_item = Label.new()
	_nome_item.theme_type_variation = "Subtitulo"
	_contorno(_nome_item)
	_nome_item.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 140)
	_nome_item.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_nome_item.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_nome_item.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_nome_item)
	_balao = Control.new()
	_balao.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_balao.draw.connect(_desenhar_balao)
	_balao.visible = false
	add_child(_balao)
	_municao = Label.new()
	_municao.theme_type_variation = "Subtitulo"
	_contorno(_municao)
	_municao.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 172)
	_municao.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_municao.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(_municao)

	# barra de ação (acima da mira)
	var acao := VBoxContainer.new()
	acao.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	acao.position += Vector2(-110, 60)
	acao.custom_minimum_size.x = 220
	add_child(acao)
	_acao_txt = Label.new()
	_acao_txt.theme_type_variation = "Pequeno"
	_acao_txt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_contorno(_acao_txt)
	acao.add_child(_acao_txt)
	_acao = _barra(Color("ffc93c"), 10)
	acao.add_child(_acao)
	acao.visible = false
	_acao.set_meta("caixa", acao)

	_aviso = Label.new()
	_aviso.theme_type_variation = "Subtitulo"
	_contorno(_aviso)
	_aviso.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_aviso.position += Vector2(40, 30)
	add_child(_aviso)

	# mensagens do inventário (cheio, não pode largar a picareta…)
	_mensagem = Label.new()
	_mensagem.theme_type_variation = "Subtitulo"
	_contorno(_mensagem)
	_mensagem.add_theme_color_override("font_color", Color("ffd27a"))
	_mensagem.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 206)
	_mensagem.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_mensagem.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_mensagem.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mensagem.visible = false
	add_child(_mensagem)

	_feed = VBoxContainer.new()
	_feed.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 16)
	_feed.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_feed.position.y += 80
	_feed.alignment = BoxContainer.ALIGNMENT_END
	add_child(_feed)

	_eliminado = Label.new()
	_eliminado.theme_type_variation = "Titulo"
	_eliminado.add_theme_font_size_override("font_size", 44)
	_eliminado.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_eliminado.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_eliminado.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_eliminado.grow_vertical = Control.GROW_DIRECTION_BOTH
	_eliminado.visible = false
	add_child(_eliminado)

	_marcador = Control.new()
	_marcador.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_marcador.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marcador.draw.connect(_desenhar_marcador)
	add_child(_marcador)
	update_status({"hp": 100, "shield": 0, "selected": 0, "action": 0, "action_left_ms": 0, "action_total_ms": 0,
			"slots": [], "ammo": []})


## Barra no estilo do redesign: trilho escuro com contorno grosso, preenchimento
## com brilho no topo e o número dentro (vida/escudo).
func _barra(cor: Color, altura: int, com_numero := false) -> ProgressBar:
	var p := ProgressBar.new()
	p.custom_minimum_size = Vector2(260, altura)
	p.max_value = 100
	p.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = cor
	fill.set_corner_radius_all(8)
	fill.border_color = cor.lightened(0.35)
	fill.border_width_top = 3 if altura >= 18 else 0
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(VentaniaTheme.NOITE, 0.8)
	bg.set_corner_radius_all(10)
	bg.border_color = VentaniaTheme.TINTA
	bg.set_border_width_all(3 if altura >= 18 else 2)
	bg.expand_margin_left = 3
	bg.expand_margin_right = 3
	bg.expand_margin_top = 3
	bg.expand_margin_bottom = 3
	p.add_theme_stylebox_override("fill", fill)
	p.add_theme_stylebox_override("background", bg)
	if com_numero:
		var n := Label.new()
		n.name = "Numero"
		n.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		n.offset_left = 10
		n.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		n.add_theme_font_override("font", VentaniaTheme.FONTE_FORTE)
		n.add_theme_font_size_override("font_size", altura - 4)
		_contorno(n)
		n.add_theme_constant_override("outline_size", 6)
		p.add_child(n)
	return p


func _contorno(l: Label) -> void:
	l.add_theme_color_override("font_outline_color", Color("24252c"))
	l.add_theme_constant_override("outline_size", 8)


func update_status(st: Dictionary) -> void:
	_status = st
	_vida.value = st["hp"]
	_escudo.value = st["shield"]
	_vida_txt.text = ""
	(_vida.get_node("Numero") as Label).text = "%d" % st["hp"]
	(_escudo.get_node("Numero") as Label).text = "%d" % st["shield"]
	var tipos := ItemDB.ammo_types()
	for i in _slots.size():
		var sl: Dictionary = st["slots"][i] if i < st["slots"].size() else {"item": 0, "rarity": 0, "mag": 0, "count": 0}
		var id := ItemDB.id_of(sl["item"])
		var qtd := ""
		if ItemDB.is_weapon(id):
			qtd = str(sl["mag"])
		elif not id.is_empty():
			qtd = "x%d" % sl["count"]
		_slots[i].set_item(id, sl["rarity"], qtd, i == st["selected"])
	_picareta.set_item(Inventory.PICKAXE_ID, 0, "", st["selected"] == Protocol.SELECTED_PICKAXE)
	var atual: Dictionary = {"item": ItemDB.index_of(Inventory.PICKAXE_ID), "rarity": 0, "mag": 0, "count": 1}
	if st["selected"] < st["slots"].size():
		atual = st["slots"][st["selected"]]
	var aid := ItemDB.id_of(atual["item"])
	if aid.is_empty():
		_nome_item.text = ""
	else:
		_nome_item.text = ItemDB.display_name(aid)
		var cor := ItemDB.rarity_color(atual["rarity"]) if ItemDB.is_weapon(aid) else Color.WHITE
		_nome_item.add_theme_color_override("font_color", cor.lightened(0.25))
	if ItemDB.is_weapon(aid) and st["ammo"].size() == tipos.size():
		var reserva: int = st["ammo"][tipos.find(ItemDB.weapon(aid)["municao"])]
		_municao.text = "%d / %d" % [atual["mag"], reserva]
	else:
		_municao.text = ""
	var caixa: Control = _acao.get_meta("caixa")
	caixa.visible = st["action"] != 0 and st["action_total_ms"] > 0
	if caixa.visible:
		_acao_total = st["action_total_ms"] / 1000.0
		_acao_fim = Time.get_ticks_msec() / 1000.0 + st["action_left_ms"] / 1000.0
		_acao_txt.text = "Recarregando…" if st["action"] == 1 else "Usando %s…" % ItemDB.display_name(aid)


func current_item() -> String:
	if _status.is_empty() or _status["slots"].is_empty():
		return ""
	if _status["selected"] == Protocol.SELECTED_PICKAXE:
		return Inventory.PICKAXE_ID
	return ItemDB.id_of(_status["slots"][_status["selected"]]["item"])


## Aviso curto acima da barra (ex.: inventário cheio).
func message(texto: String, segundos := 2.5) -> void:
	_mensagem.text = texto
	_mensagem.visible = not texto.is_empty()
	_mensagem_t = segundos


## Rótulo da tecla da picareta (F / ▶ / toque) no 1º espaço.
func set_pickaxe_key(rotulo: String) -> void:
	_picareta.rotulo = rotulo
	_picareta.queue_redraw()


func set_prompt(texto: String) -> void:
	_aviso.text = texto


## Balão de interação ancorado no objeto (posição de tela). tecla vazia = esconder.
## progresso: -1 = sem anel; 0..1 = segurar.
func set_world_prompt(pos_tela: Vector2, tecla: String, texto: String, progresso := -1.0, cor := Color.WHITE) -> void:
	_balao.visible = not tecla.is_empty()
	if not _balao.visible:
		return
	_balao.position = pos_tela
	_balao_tecla = tecla
	_balao_texto = texto
	_balao_prog = progresso
	_balao_cor = cor
	_balao.queue_redraw()


func _desenhar_balao() -> void:
	var fonte := get_theme_default_font()
	var tam_t := 20
	var w_texto := fonte.get_string_size(_balao_texto, HORIZONTAL_ALIGNMENT_LEFT, -1, tam_t).x
	var w_tecla := maxf(34.0, fonte.get_string_size(_balao_tecla, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x + 18)
	var larg := w_tecla + w_texto + 30
	var r := Rect2(Vector2(-larg / 2, -26), Vector2(larg, 48))
	var fundo := StyleBoxFlat.new()
	fundo.bg_color = Color(VentaniaTheme.NOITE, 0.94)
	fundo.set_corner_radius_all(14)
	fundo.set_border_width_all(3)
	fundo.border_color = _balao_cor          # cor da raridade do item
	fundo.shadow_color = Color(VentaniaTheme.TINTA, 0.8)
	fundo.shadow_offset = Vector2(0, 4)
	fundo.shadow_size = 1
	_balao.draw_style_box(fundo, r)
	# tecla (com anel de progresso ao segurar)
	var c := r.position + Vector2(10 + w_tecla / 2, 24)
	var tecla := StyleBoxFlat.new()
	tecla.bg_color = Color("f4f1ea")
	tecla.set_corner_radius_all(8)
	_balao.draw_style_box(tecla, Rect2(c - Vector2(w_tecla / 2, 16), Vector2(w_tecla, 32)))
	var ws := fonte.get_string_size(_balao_tecla, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	_balao.draw_string(fonte, c + Vector2(-ws / 2, 7), _balao_tecla, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("24252c"))
	if _balao_prog >= 0.0:
		_balao.draw_arc(c, w_tecla / 2 + 7, -PI / 2, -PI / 2 + TAU * _balao_prog, 32, Color("ffc93c"), 4.0, true)
	_balao.draw_string(fonte, Vector2(c.x + w_tecla / 2 + 12, c.y + 7), _balao_texto, HORIZONTAL_ALIGNMENT_LEFT, -1, tam_t, Color.WHITE)


func hit_marker(cabeca: bool) -> void:
	_marcador_t = 0.18
	_marcador_cabeca = cabeca
	_marcador.queue_redraw()


func damage_flash() -> void:
	_dano_t = 0.35


## Arranjo do HUD para PC (false) ou toque (true). Ver HudLayout.
func set_touch_layout(toque: bool) -> void:
	_toque = toque
	var m := HudLayout.MARGEM
	var slot := ItemSlot.TAM.y
	if toque:
		# centro de baixo: barra de itens, vida/escudo logo acima, munição acima de tudo
		HudLayout.pin(_barra_itens, 0.5, 1.0, 0, -m, 0, -1)
		_vit.custom_minimum_size.x = 300
		HudLayout.pin(_vit, 0.5, 1.0, 0, -m - slot - 22, 0, -1)
		HudLayout.pin(_municao, 0.5, 1.0, 0, -m - slot - 22 - 130, 0, -1)
		HudLayout.pin(_nome_item, 0.5, 1.0, 0, -m - slot - 22 - 160, 0, -1)
		HudLayout.pin(_feed, 0.0, 0.0, m, m + HudLayout.MAPA_TOQUE + 96, 1, 1)
		_feed.alignment = BoxContainer.ALIGNMENT_BEGIN
	else:
		# PC: vida embaixo à esquerda; itens embaixo à direita; feed à esquerda
		_vit.custom_minimum_size.x = 280
		HudLayout.pin(_vit, 0.0, 1.0, m, -m, 1, -1)
		HudLayout.pin(_barra_itens, 1.0, 1.0, -m - 92, -m, -1, -1)
		var centro_barra := -m - 92 - _barra_itens.get_combined_minimum_size().x / 2.0
		HudLayout.pin(_municao, 1.0, 1.0, centro_barra, -m - slot - 18, 0, -1)
		HudLayout.pin(_nome_item, 1.0, 1.0, centro_barra, -m - slot - 50, 0, -1)
		HudLayout.pin(_feed, 0.0, 0.3, m, 0, 1, 1)
		_feed.alignment = BoxContainer.ALIGNMENT_BEGIN
	_vida_txt.visible = false


func kill_feed(texto: String) -> void:
	var l := Label.new()
	l.theme_type_variation = "Pequeno"
	l.text = texto
	_contorno(l)
	var sb := VentaniaTheme._caixa(Color(VentaniaTheme.TINTA, 0.5), 10, Color.TRANSPARENT, 0, 0)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	l.add_theme_stylebox_override("normal", sb)
	l.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_feed.add_child(l)
	if _feed.get_child_count() > 5:
		_feed.get_child(0).queue_free()
	get_tree().create_timer(6.0).timeout.connect(func():
		if is_instance_valid(l):
			l.queue_free())


func show_eliminated(texto: String) -> void:
	_eliminado.text = texto
	_eliminado.visible = not texto.is_empty()


func _desenhar_marcador() -> void:
	if _marcador_t <= 0.0:
		return
	var c := Color("ffd23c") if _marcador_cabeca else Color.WHITE
	for s in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		_marcador.draw_line(s * 8.0, s * 16.0, Color("24252c"), 6.0)
		_marcador.draw_line(s * 8.0, s * 16.0, c, 3.0)


func _process(delta: float) -> void:
	if _marcador_t > 0.0:
		_marcador_t -= delta
		if _marcador_t <= 0.0:
			_marcador.queue_redraw()
	if _mensagem_t > 0.0:
		_mensagem_t -= delta
		_mensagem.modulate.a = clampf(_mensagem_t / 0.4, 0.0, 1.0)
		if _mensagem_t <= 0.0:
			_mensagem.visible = false
	_dano_t = maxf(0.0, _dano_t - delta)
	_vinheta.color.a = _dano_t * 0.6
	var caixa: Control = _acao.get_meta("caixa")
	if caixa.visible and _acao_total > 0.0:
		var resta := _acao_fim - Time.get_ticks_msec() / 1000.0
		_acao.value = clampf(100.0 * (1.0 - resta / _acao_total), 0.0, 100.0)
		if resta <= -0.3:
			caixa.visible = false
