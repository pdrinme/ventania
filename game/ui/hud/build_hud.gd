class_name BuildHud
extends Control
## Materiais (sempre visíveis, canto inferior direito) e, no modo construção, a
## barra de peças (Parede, Piso, Rampa, Teto), o material escolhido e as teclas.
## Na edição, a ajuda da edição.

var modo: BuildMode
var _rotulo_mats: Label
var _barra: Control
var _ajuda: Label

const ICONES := ["▮", "▬", "◢", "▲"]
const CORES := [Color("c98a4b"), Color("a7a196"), Color("8fa3b4")]


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rotulo_mats = Label.new()
	_rotulo_mats.theme_type_variation = "Subtitulo"
	_rotulo_mats.add_theme_color_override("font_outline_color", Color("24252c"))
	_rotulo_mats.add_theme_constant_override("outline_size", 8)
	_rotulo_mats.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 16)
	_rotulo_mats.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_rotulo_mats.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_rotulo_mats.position.y -= 40
	add_child(_rotulo_mats)
	_barra = Control.new()
	_barra.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_barra.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_barra.draw.connect(_desenhar)
	add_child(_barra)
	_ajuda = Label.new()
	_ajuda.theme_type_variation = "Pequeno"
	_ajuda.add_theme_color_override("font_outline_color", Color("24252c"))
	_ajuda.add_theme_constant_override("outline_size", 6)
	_ajuda.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ajuda.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 250)
	_ajuda.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_ajuda.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(_ajuda)


func _process(_delta: float) -> void:
	if modo == null:
		return
	var m: Array = modo.materials()
	_rotulo_mats.text = "Madeira %d   Pedra %d   Metal %d" % [m[0] if m.size() > 0 else 0, m[1] if m.size() > 1 else 0, m[2] if m.size() > 2 else 0]
	_barra.visible = modo.ativo and modo.editando < 0
	if modo.editando >= 0:
		_ajuda.text = "EDITANDO — Atirar: liga/desliga o ladrilho · Editar: confirmar · Recarregar: restaurar · Esc: cancelar"
	elif modo.ativo:
		_ajuda.text = "CONSTRUÇÃO — 1-4/roda: peça · Recarregar: material · Atirar: colocar (segure para sequência) · Editar: mire numa peça sua"
	else:
		_ajuda.text = ""
	_barra.queue_redraw()


func _desenhar() -> void:
	var fonte := get_theme_default_font()
	var tam := 74.0
	var esp := 10.0
	var total := 4 * tam + 3 * esp
	var y := -tam - 150.0
	for i in 4:
		var r := Rect2(-total / 2.0 + i * (tam + esp), y, tam, tam)
		var sel := modo.escolha == i
		var sb := StyleBoxFlat.new()
		sb.bg_color = CORES[modo.material].darkened(0.35 if sel else 0.6)
		sb.set_corner_radius_all(12)
		sb.set_border_width_all(4 if sel else 2)
		sb.border_color = Color.WHITE if sel else Color(1, 1, 1, 0.3)
		_barra.draw_style_box(sb, r)
		var icone: String = ICONES[i]
		var w := fonte.get_string_size(icone, HORIZONTAL_ALIGNMENT_LEFT, -1, 34).x
		_barra.draw_string(fonte, r.position + Vector2((tam - w) / 2.0, 46), icone, HORIZONTAL_ALIGNMENT_LEFT, -1, 34, Color.WHITE)
		var nome: String = Grade.config()["pecas"][Grade.TIPOS[i]]["nome"]
		var wn := fonte.get_string_size(nome, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		_barra.draw_string(fonte, r.position + Vector2((tam - wn) / 2.0, tam - 8), nome, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
		_barra.draw_string(fonte, r.position + Vector2(6, 16), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.8))
	var mat := "Material: %s (custa %d)" % [Grade.MATERIAIS[modo.material].capitalize(), int(Grade.config()["custo"])]
	var wm := fonte.get_string_size(mat, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	_barra.draw_string_outline(fonte, Vector2(-wm / 2.0, y - 10), mat, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 6, Color("24252c"))
	_barra.draw_string(fonte, Vector2(-wm / 2.0, y - 10), mat, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, CORES[modo.material].lightened(0.3))
