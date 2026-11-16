class_name CombatHud
extends Control
## HUD de combate: vida/escudo, 5 espaços de inventário, barra de ação
## (recarga/uso), aviso de interação, feed de eliminações, tela de eliminado e
## marcador de acerto. Só mostra o que o servidor informa (status).

signal slot_tapped(i: int)

const VERDE := Color("5fd35a")
const AZUL := Color("3fa2ff")
const FUNDO := Color(0.06, 0.31, 0.34, 0.75)

var _vida: ProgressBar
var _escudo: ProgressBar
var _vida_txt: Label
var _slots: Array[Button] = []
var _municao: Label
var _acao: ProgressBar
var _acao_txt: Label
var _aviso: Label
var _feed: VBoxContainer
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
	_escudo = _barra(AZUL, 18)
	vit.add_child(_escudo)
	_vida = _barra(VERDE, 22)
	vit.add_child(_vida)
	_vida_txt = Label.new()
	_vida_txt.theme_type_variation = "Pequeno"
	_contorno(_vida_txt)
	vit.add_child(_vida_txt)

	# inventário (centro inferior)
	var barra := HBoxContainer.new()
	barra.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 40)
	barra.grow_horizontal = Control.GROW_DIRECTION_BOTH
	barra.grow_vertical = Control.GROW_DIRECTION_BEGIN
	barra.add_theme_constant_override("separation", 6)
	add_child(barra)
	for i in Inventory.SLOTS:
		var b := Button.new()
		b.custom_minimum_size = Vector2(88, 64)
		b.focus_mode = Control.FOCUS_NONE
		b.clip_text = true
		b.add_theme_font_size_override("font_size", 15)
		b.pressed.connect(func(): slot_tapped.emit(i))
		barra.add_child(b)
		_slots.append(b)
	_municao = Label.new()
	_municao.theme_type_variation = "Subtitulo"
	_contorno(_municao)
	_municao.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 112)
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


func _barra(cor: Color, altura: int) -> ProgressBar:
	var p := ProgressBar.new()
	p.custom_minimum_size = Vector2(240, altura)
	p.max_value = 100
	p.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = cor
	fill.set_corner_radius_all(6)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.45)
	bg.set_corner_radius_all(6)
	p.add_theme_stylebox_override("fill", fill)
	p.add_theme_stylebox_override("background", bg)
	return p


func _contorno(l: Label) -> void:
	l.add_theme_color_override("font_outline_color", Color("24252c"))
	l.add_theme_constant_override("outline_size", 8)


func update_status(st: Dictionary) -> void:
	_status = st
	_vida.value = st["hp"]
	_escudo.value = st["shield"]
	_vida_txt.text = "Vida %d · Escudo %d" % [st["hp"], st["shield"]]
	var tipos := ItemDB.ammo_types()
	for i in _slots.size():
		var b := _slots[i]
		var s: Dictionary = st["slots"][i] if i < st["slots"].size() else {"item": 0, "rarity": 0, "mag": 0, "count": 0}
		var id := ItemDB.id_of(s["item"])
		var estilo := StyleBoxFlat.new()
		estilo.set_corner_radius_all(10)
		estilo.bg_color = FUNDO
		estilo.set_border_width_all(4 if i == st["selected"] else 2)
		if id.is_empty():
			b.text = str(i + 1)
			estilo.border_color = Color(1, 1, 1, 0.25)
		else:
			var nome: String = ItemDB.def(id)["nome"]
			b.text = "%d %s\n%s" % [i + 1, nome, ("%d" % s["mag"]) if ItemDB.is_weapon(id) else "x%d" % s["count"]]
			estilo.border_color = ItemDB.rarity_color(s["rarity"]) if ItemDB.is_weapon(id) else Color("e8e8e8")
		if i == st["selected"]:
			estilo.bg_color = Color(0.13, 0.72, 0.66, 0.9)
		for nome_estilo in ["normal", "hover", "pressed"]:
			b.add_theme_stylebox_override(nome_estilo, estilo)
	var atual: Dictionary = st["slots"][st["selected"]] if st["selected"] < st["slots"].size() else {"item": 0}
	var aid := ItemDB.id_of(atual["item"])
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
		_acao_txt.text = "Recarregando…" if st["action"] == 1 else "Usando %s…" % ItemDB.def(aid).get("nome", "")


func current_item() -> String:
	if _status.is_empty() or _status["slots"].is_empty():
		return ""
	return ItemDB.id_of(_status["slots"][_status["selected"]]["item"])


func set_prompt(texto: String) -> void:
	_aviso.text = texto


func hit_marker(cabeca: bool) -> void:
	_marcador_t = 0.18
	_marcador_cabeca = cabeca
	_marcador.queue_redraw()


func damage_flash() -> void:
	_dano_t = 0.35


func kill_feed(texto: String) -> void:
	var l := Label.new()
	l.theme_type_variation = "Pequeno"
	l.text = texto
	_contorno(l)
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
	_dano_t = maxf(0.0, _dano_t - delta)
	_vinheta.color.a = _dano_t * 0.6
	var caixa: Control = _acao.get_meta("caixa")
	if caixa.visible and _acao_total > 0.0:
		var resta := _acao_fim - Time.get_ticks_msec() / 1000.0
		_acao.value = clampf(100.0 * (1.0 - resta / _acao_total), 0.0, 100.0)
		if resta <= -0.3:
			caixa.visible = false
