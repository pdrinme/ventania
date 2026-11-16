class_name ItemSlot
extends Control
## Um espaço do inventário: miniatura do item sobre fundo em degradê da raridade,
## número do espaço, munição/quantidade e destaque quando selecionado.
## Mítico: degradê animado entre duas cores.

signal tapped

const RAIO := 12.0
const TAM := Vector2(84, 84)

var indice := 0
var item := ""
var raridade := 0
var texto_qtd := ""
var selecionado := false
var _icone: Texture2D
var _t := 0.0
var _escala := 1.0
static var _cache_icones := {}


func _ready() -> void:
	custom_minimum_size = TAM
	mouse_filter = Control.MOUSE_FILTER_STOP
	pivot_offset = TAM / 2.0
	gui_input.connect(func(e):
		if (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT) or (e is InputEventScreenTouch and e.pressed):
			tapped.emit())


static func icone_de(id: String) -> Texture2D:
	if id.is_empty():
		return null
	if not _cache_icones.has(id):
		var c := "res://assets/ui/icones/%s.png" % id
		_cache_icones[id] = load(c) if ResourceLoader.exists(c) else null
	return _cache_icones[id]


func set_item(id: String, rar: int, qtd: String, sel: bool) -> void:
	if id != item:
		_icone = icone_de(id)
	item = id
	raridade = rar
	texto_qtd = qtd
	selecionado = sel
	queue_redraw()


func _cores() -> Array:
	var r := ItemDB.rarity(raridade)
	var c1 := Color(r["cor"])
	if r.has("cor2"):
		# mítico: alterna suavemente entre as duas cores
		var k := 0.5 + 0.5 * sin(_t * 2.2)
		c1 = c1.lerp(Color(r["cor2"]), k)
	return [c1.lightened(0.25), c1.darkened(0.35)]


func _process(delta: float) -> void:
	_escala = move_toward(_escala, 1.1 if selecionado else 1.0, delta * 2.5)
	scale = Vector2.ONE * _escala
	if not item.is_empty() and ItemDB.rarity(raridade).has("cor2"):
		_t += delta
		queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	if item.is_empty():
		_caixa(rect, Color(0.04, 0.2, 0.23, 0.55), Color(0.04, 0.2, 0.23, 0.55))
	else:
		var cores := _cores() if ItemDB.is_weapon(item) else [Color("8a9bab"), Color("4b5866")]
		_caixa(rect, cores[0], cores[1])
		# brilho suave no topo
		draw_rect(Rect2(4, 4, size.x - 8, size.y * 0.35), Color(1, 1, 1, 0.10))
		if _icone:
			var m := 6.0
			draw_texture_rect(_icone, Rect2(m, m + 2, size.x - m * 2, size.y - m * 2 - 10), false)
	var contorno := Color.WHITE if selecionado else Color(1, 1, 1, 0.25)
	_contorno(rect, contorno, 4.0 if selecionado else 2.0)
	var fonte := get_theme_default_font()
	_texto(fonte, Vector2(7, 17), str(indice + 1), 14, Color(1, 1, 1, 0.85))
	if not texto_qtd.is_empty():
		var w := fonte.get_string_size(texto_qtd, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
		_texto(fonte, Vector2(size.x - w - 7, size.y - 7), texto_qtd, 17, Color.WHITE)


func _caixa(r: Rect2, topo: Color, base: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(int(RAIO))
	sb.bg_color = base
	draw_style_box(sb, r)
	var sb2 := StyleBoxFlat.new()
	sb2.set_corner_radius_all(int(RAIO))
	sb2.corner_radius_bottom_left = 0
	sb2.corner_radius_bottom_right = 0
	sb2.bg_color = topo
	draw_style_box(sb2, Rect2(r.position, Vector2(r.size.x, r.size.y * 0.55)))
	# transição suave entre as duas metades
	for i in 8:
		var k := i / 8.0
		draw_rect(Rect2(0, r.size.y * (0.45 + 0.1 * k), r.size.x, r.size.y * 0.0125 + 1), topo.lerp(base, k))


func _contorno(r: Rect2, cor: Color, largura: float) -> void:
	var sb := StyleBoxFlat.new()
	sb.draw_center = false
	sb.set_corner_radius_all(int(RAIO))
	sb.set_border_width_all(int(largura))
	sb.border_color = cor
	draw_style_box(sb, r)


func _texto(fonte: Font, pos: Vector2, t: String, tam: int, cor: Color) -> void:
	draw_string_outline(fonte, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, tam, 6, Color("24252c"))
	draw_string(fonte, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, tam, cor)
