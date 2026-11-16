class_name VentaniaTheme
extends RefCounted
## Tema da interface, gerado por código a partir da paleta do jogo.
## Botões grandes e arredondados, contorno de foco visível (navegação por
## controle/teclado), alvos de toque >= 56 px.

const TEAL := Color("22b8a8")
const TEAL_ESCURO := Color("167c84")
const TEAL_NOITE := Color("0f4f56")
const AMARELO := Color("ffc93c")
const CORAL := Color("ff6b5b")
const BRANCO := Color("f4f1ea")
const TINTA := Color("24252c")

const FONTE := preload("res://assets/ui/fontes/fredoka_500.woff2")
const FONTE_FORTE := preload("res://assets/ui/fontes/fredoka_700.woff2")


static func build(mobile := false) -> Theme:
	var t := Theme.new()
	t.default_font = FONTE
	t.default_font_size = 26 if mobile else 22
	var alvo := 64 if mobile else 52

	# Botões
	t.set_stylebox("normal", "Button", _caixa(TEAL, 16, AMARELO.darkened(0.6), 0, 3))
	t.set_stylebox("hover", "Button", _caixa(TEAL.lightened(0.12), 16, AMARELO, 0, 3))
	t.set_stylebox("pressed", "Button", _caixa(TEAL_ESCURO, 16, AMARELO, 0, 0))
	t.set_stylebox("disabled", "Button", _caixa(Color("6b6f80"), 16, Color.TRANSPARENT, 0, 0))
	t.set_stylebox("focus", "Button", _contorno(AMARELO, 18, 4))
	for estado in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		t.set_color(estado, "Button", BRANCO)
	t.set_color("font_disabled_color", "Button", Color(1, 1, 1, 0.5))
	t.set_font("font", "Button", FONTE_FORTE)
	t.set_constant("h_separation", "Button", 10)

	# Painéis
	t.set_stylebox("panel", "PanelContainer", _caixa(Color(TEAL_NOITE, 0.92), 22, Color.TRANSPARENT, 18, 0))
	t.set_stylebox("panel", "Panel", _caixa(Color(TEAL_NOITE, 0.92), 22, Color.TRANSPARENT, 18, 0))

	# Textos
	t.set_color("font_color", "Label", BRANCO)
	t.set_color("font_outline_color", "Label", TINTA)
	t.set_constant("outline_size", "Label", 0)
	t.set_type_variation("Titulo", "Label")
	t.set_font("font", "Titulo", FONTE_FORTE)
	t.set_font_size("font_size", "Titulo", 72 if mobile else 64)
	t.set_color("font_color", "Titulo", AMARELO)
	t.set_color("font_outline_color", "Titulo", TINTA)
	t.set_constant("outline_size", "Titulo", 14)
	t.set_type_variation("Subtitulo", "Label")
	t.set_font("font", "Subtitulo", FONTE_FORTE)
	t.set_font_size("font_size", "Subtitulo", 30 if mobile else 26)
	t.set_type_variation("Pequeno", "Label")
	t.set_font_size("font_size", "Pequeno", 20 if mobile else 16)
	t.set_color("font_color", "Pequeno", Color(BRANCO, 0.8))

	# Campos e listas
	var campo := _caixa(Color("0b3a40"), 12, TEAL, 10, 0)
	campo.border_width_bottom = 3
	for tipo in ["LineEdit", "OptionButton"]:
		t.set_stylebox("normal", tipo, campo)
		t.set_stylebox("focus", tipo, _contorno(AMARELO, 12, 3))
		t.set_color("font_color", tipo, BRANCO)
	t.set_stylebox("hover", "OptionButton", _caixa(Color("115058"), 12, TEAL, 10, 0))
	t.set_stylebox("pressed", "OptionButton", campo)
	t.set_stylebox("panel", "PopupMenu", _caixa(TEAL_NOITE, 12, TEAL, 8, 0))
	t.set_color("font_color", "PopupMenu", BRANCO)
	t.set_color("font_hover_color", "PopupMenu", AMARELO)
	t.set_font_size("font_size", "PopupMenu", t.default_font_size)

	# Slider
	var trilho := _caixa(Color("0b3a40"), 8, Color.TRANSPARENT, 0, 0)
	trilho.content_margin_top = 6
	trilho.content_margin_bottom = 6
	t.set_stylebox("slider", "HSlider", trilho)
	t.set_stylebox("grabber_area", "HSlider", _caixa(AMARELO, 8, Color.TRANSPARENT, 0, 0))
	t.set_stylebox("grabber_area_highlight", "HSlider", _caixa(AMARELO.lightened(0.2), 8, Color.TRANSPARENT, 0, 0))
	t.set_stylebox("focus", "HSlider", _contorno(AMARELO, 10, 3))
	var bola := _bola(28 if mobile else 22)
	t.set_icon("grabber", "HSlider", bola)
	t.set_icon("grabber_highlight", "HSlider", bola)

	# Check
	t.set_color("font_color", "CheckButton", BRANCO)
	t.set_stylebox("focus", "CheckButton", _contorno(AMARELO, 12, 3))

	# Abas
	t.set_stylebox("tab_selected", "TabContainer", _caixa(TEAL, 14, AMARELO, 14, 0, true))
	t.set_stylebox("tab_unselected", "TabContainer", _caixa(TEAL_ESCURO, 14, Color.TRANSPARENT, 14, 0, true))
	t.set_stylebox("tab_hovered", "TabContainer", _caixa(TEAL.lightened(0.1), 14, Color.TRANSPARENT, 14, 0, true))
	t.set_stylebox("tab_focus", "TabContainer", _contorno(AMARELO, 14, 3))
	t.set_stylebox("panel", "TabContainer", _caixa(Color(TEAL_NOITE, 0.95), 18, Color.TRANSPARENT, 20, 0))
	t.set_font("font", "TabContainer", FONTE_FORTE)
	t.set_color("font_selected_color", "TabContainer", BRANCO)
	t.set_color("font_unselected_color", "TabContainer", Color(BRANCO, 0.75))

	# Barra de progresso
	t.set_stylebox("background", "ProgressBar", _caixa(Color("0b3a40"), 12, Color.TRANSPARENT, 0, 0))
	t.set_stylebox("fill", "ProgressBar", _caixa(AMARELO, 12, Color.TRANSPARENT, 0, 0))

	# Tamanhos mínimos (toque)
	t.set_constant("separation", "VBoxContainer", 12)
	t.set_constant("separation", "HBoxContainer", 12)
	t.set_meta("altura_alvo", alvo)
	return t


static func _caixa(cor: Color, raio: int, borda: Color, margem: int, sombra_y: int, topo_so := false) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = cor
	s.set_corner_radius_all(raio)
	if topo_so:
		s.corner_radius_bottom_left = 0
		s.corner_radius_bottom_right = 0
	if borda.a > 0:
		s.border_color = borda
		s.border_width_bottom = 4
	if sombra_y > 0:
		s.shadow_color = Color(0, 0, 0, 0.25)
		s.shadow_offset = Vector2(0, sombra_y)
		s.shadow_size = 2
	s.content_margin_left = maxi(margem, 18)
	s.content_margin_right = maxi(margem, 18)
	s.content_margin_top = maxi(margem / 2, 8)
	s.content_margin_bottom = maxi(margem / 2, 8)
	s.anti_aliasing = true
	return s


static func _contorno(cor: Color, raio: int, largura: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.draw_center = false
	s.border_color = cor
	s.set_border_width_all(largura)
	s.set_corner_radius_all(raio)
	s.expand_margin_left = 3
	s.expand_margin_right = 3
	s.expand_margin_top = 3
	s.expand_margin_bottom = 3
	return s


static func _bola(d: int) -> ImageTexture:
	var img := Image.create(d, d, false, Image.FORMAT_RGBA8)
	var c := (d - 1) / 2.0
	for y in d:
		for x in d:
			var r := Vector2(x - c, y - c).length()
			var a := clampf(c - r + 0.5, 0.0, 1.0)
			var cor := BRANCO if r < c - 3 else TINTA
			img.set_pixel(x, y, Color(cor, a))
	return ImageTexture.create_from_image(img)
