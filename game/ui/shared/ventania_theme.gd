class_name VentaniaTheme
extends RefCounted
## Tema da interface (redesign da Etapa 8), gerado por código.
## Linguagem visual "adesivo ao vento":
##  - contorno grosso escuro (TINTA) e sombra dura deslocada para baixo, como
##    adesivo/HQ; cantos bem arredondados;
##  - botões levemente inclinados (o vento empurrando), texto em caixa alta;
##  - amarelo só para a ação principal; branco para as secundárias; cartões
##    escuros translúcidos sobre o fundo noturno com rajadas de vento;
##  - foco sempre visível (contorno amarelo grosso) para controle e teclado;
##    alvos de toque >= 56 px no celular.
## Variações: BotaoPrimario, BotaoSecundario, BotaoFantasma, BotaoAba, Cartao,
## CartaoClaro, Chip, Titulo, Subtitulo, Pequeno, Rotulo, Destaque.

const TEAL := Color("22b8a8")
const TEAL_ESCURO := Color("167c84")
const TEAL_NOITE := Color("0f4f56")
const AMARELO := Color("ffc93c")
const CORAL := Color("ff6b5b")
const BRANCO := Color("f6f3ec")
const TINTA := Color("15161c")
const NOITE := Color("101c33")           # cartões
const NOITE_CLARA := Color("1c2d4d")
const INDIGO := Color("2b2470")
const VERDE := Color("5ee08a")           # online
const CINZA := Color("8a90a6")
const INCLINACAO := 0.12                 # skew dos botões

const FONTE := preload("res://assets/ui/fontes/fredoka_500.woff2")
const FONTE_FORTE := preload("res://assets/ui/fontes/fredoka_700.woff2")


static func build(mobile := false) -> Theme:
	var t := Theme.new()
	t.default_font = FONTE
	t.default_font_size = 26 if mobile else 21
	var alvo := 64 if mobile else 50

	# Botão padrão = secundário (branco)
	_botao(t, "Button", BRANCO, TINTA, mobile)
	t.set_type_variation("BotaoSecundario", "Button")
	t.set_type_variation("BotaoPrimario", "Button")
	_botao(t, "BotaoPrimario", AMARELO, TINTA, mobile)
	t.set_font_size("font_size", "BotaoPrimario", 40 if mobile else 34)
	t.set_type_variation("BotaoFantasma", "Button")
	var fan := _caixa(Color(1, 1, 1, 0.08), 14, Color(1, 1, 1, 0.35), 2, 0)
	t.set_stylebox("normal", "BotaoFantasma", fan)
	t.set_stylebox("hover", "BotaoFantasma", _caixa(Color(1, 1, 1, 0.16), 14, BRANCO, 2, 0))
	t.set_stylebox("pressed", "BotaoFantasma", _caixa(Color(1, 1, 1, 0.24), 14, BRANCO, 2, 0))
	t.set_stylebox("disabled", "BotaoFantasma", _caixa(Color(1, 1, 1, 0.04), 14, Color(1, 1, 1, 0.15), 2, 0))
	t.set_stylebox("focus", "BotaoFantasma", _contorno(AMARELO, 16, 4))
	for estado in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		t.set_color(estado, "BotaoFantasma", BRANCO)
	t.set_color("font_disabled_color", "BotaoFantasma", Color(1, 1, 1, 0.4))
	# aba do topo: texto sobre o fundo, sublinhado amarelo quando ativa
	t.set_type_variation("BotaoAba", "Button")
	var vazio := StyleBoxEmpty.new()
	vazio.content_margin_left = 14
	vazio.content_margin_right = 14
	t.set_stylebox("normal", "BotaoAba", vazio)
	t.set_stylebox("hover", "BotaoAba", vazio)
	t.set_stylebox("disabled", "BotaoAba", vazio)
	var ativa := StyleBoxFlat.new()
	ativa.bg_color = Color.TRANSPARENT
	ativa.border_color = AMARELO
	ativa.border_width_bottom = 5
	ativa.content_margin_left = 14
	ativa.content_margin_right = 14
	t.set_stylebox("pressed", "BotaoAba", ativa)
	t.set_stylebox("hover_pressed", "BotaoAba", ativa)
	t.set_stylebox("focus", "BotaoAba", _contorno(AMARELO, 10, 3))
	t.set_font("font", "BotaoAba", FONTE_FORTE)
	t.set_font_size("font_size", "BotaoAba", 26 if mobile else 22)
	t.set_color("font_color", "BotaoAba", Color(BRANCO, 0.6))
	t.set_color("font_hover_color", "BotaoAba", BRANCO)
	t.set_color("font_pressed_color", "BotaoAba", BRANCO)
	t.set_color("font_hover_pressed_color", "BotaoAba", BRANCO)
	t.set_color("font_focus_color", "BotaoAba", BRANCO)

	# Painéis / cartões
	var cartao := _caixa(Color(NOITE, 0.94), 20, TINTA, 3, 6)
	cartao.content_margin_left = 22
	cartao.content_margin_right = 22
	cartao.content_margin_top = 18
	cartao.content_margin_bottom = 18
	for tipo in ["PanelContainer", "Panel"]:
		t.set_stylebox("panel", tipo, cartao)
	t.set_type_variation("Cartao", "PanelContainer")
	t.set_type_variation("CartaoClaro", "PanelContainer")
	var claro := _caixa(BRANCO, 20, TINTA, 3, 6)
	claro.content_margin_left = 20
	claro.content_margin_right = 20
	claro.content_margin_top = 14
	claro.content_margin_bottom = 14
	t.set_stylebox("panel", "CartaoClaro", claro)
	t.set_type_variation("Chip", "PanelContainer")
	var chip := _caixa(Color(TINTA, 0.55), 22, Color(1, 1, 1, 0.12), 2, 0)
	chip.content_margin_left = 12
	chip.content_margin_right = 16
	chip.content_margin_top = 4
	chip.content_margin_bottom = 4
	t.set_stylebox("panel", "Chip", chip)

	# Textos
	t.set_color("font_color", "Label", BRANCO)
	t.set_color("font_outline_color", "Label", TINTA)
	t.set_constant("outline_size", "Label", 0)
	t.set_type_variation("Titulo", "Label")
	t.set_font("font", "Titulo", FONTE_FORTE)
	t.set_font_size("font_size", "Titulo", 72 if mobile else 64)
	t.set_color("font_color", "Titulo", AMARELO)
	t.set_color("font_outline_color", "Titulo", TINTA)
	t.set_constant("outline_size", "Titulo", 16)
	t.set_color("font_shadow_color", "Titulo", TINTA)
	t.set_constant("shadow_offset_y", "Titulo", 6)
	t.set_constant("shadow_offset_x", "Titulo", 0)
	t.set_type_variation("Subtitulo", "Label")
	t.set_font("font", "Subtitulo", FONTE_FORTE)
	t.set_font_size("font_size", "Subtitulo", 30 if mobile else 26)
	t.set_type_variation("Destaque", "Label")
	t.set_font("font", "Destaque", FONTE_FORTE)
	t.set_font_size("font_size", "Destaque", 40 if mobile else 34)
	t.set_color("font_outline_color", "Destaque", TINTA)
	t.set_constant("outline_size", "Destaque", 10)
	t.set_type_variation("Pequeno", "Label")
	t.set_font_size("font_size", "Pequeno", 20 if mobile else 16)
	t.set_color("font_color", "Pequeno", Color(BRANCO, 0.75))
	t.set_type_variation("Rotulo", "Label")             # sobretítulo em caixa alta
	t.set_font("font", "Rotulo", FONTE_FORTE)
	t.set_font_size("font_size", "Rotulo", 17 if mobile else 14)
	t.set_color("font_color", "Rotulo", AMARELO)

	# Campos e listas
	var campo := _caixa(Color("0a1426"), 14, Color(1, 1, 1, 0.18), 2, 0)
	campo.content_margin_left = 16
	campo.content_margin_right = 16
	for tipo in ["LineEdit", "OptionButton"]:
		t.set_stylebox("normal", tipo, campo)
		t.set_stylebox("focus", tipo, _contorno(AMARELO, 14, 3))
		t.set_color("font_color", tipo, BRANCO)
		t.set_color("font_placeholder_color", tipo, Color(BRANCO, 0.4))
	t.set_color("caret_color", "LineEdit", AMARELO)
	t.set_color("selection_color", "LineEdit", Color(AMARELO, 0.35))
	t.set_stylebox("hover", "OptionButton", _caixa(Color("13213a"), 14, Color(1, 1, 1, 0.3), 2, 0))
	t.set_stylebox("pressed", "OptionButton", campo)
	t.set_font("font", "OptionButton", FONTE)
	t.set_stylebox("panel", "PopupMenu", _caixa(NOITE, 14, TINTA, 3, 4))
	t.set_stylebox("hover", "PopupMenu", _caixa(Color(AMARELO, 0.18), 8, Color.TRANSPARENT, 0, 0))
	t.set_color("font_color", "PopupMenu", BRANCO)
	t.set_color("font_hover_color", "PopupMenu", AMARELO)
	t.set_font_size("font_size", "PopupMenu", t.default_font_size)
	t.set_stylebox("panel", "AcceptDialog", _caixa(NOITE, 20, TINTA, 3, 6))
	t.set_stylebox("embedded_border", "Window", _caixa(NOITE, 20, TINTA, 3, 6))
	t.set_color("title_color", "Window", AMARELO)
	t.set_font("title_font", "Window", FONTE_FORTE)

	# Slider
	var trilho := _caixa(Color("0a1426"), 8, Color(1, 1, 1, 0.15), 2, 0)
	trilho.content_margin_top = 6
	trilho.content_margin_bottom = 6
	t.set_stylebox("slider", "HSlider", trilho)
	t.set_stylebox("grabber_area", "HSlider", _caixa(AMARELO, 8, Color.TRANSPARENT, 0, 0))
	t.set_stylebox("grabber_area_highlight", "HSlider", _caixa(AMARELO.lightened(0.2), 8, Color.TRANSPARENT, 0, 0))
	t.set_stylebox("focus", "HSlider", _contorno(AMARELO, 10, 3))
	var bola := _bola(28 if mobile else 24)
	t.set_icon("grabber", "HSlider", bola)
	t.set_icon("grabber_highlight", "HSlider", bola)

	# Check / interruptor
	t.set_color("font_color", "CheckButton", BRANCO)
	for estado in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var e := StyleBoxEmpty.new()
		e.content_margin_left = 4
		e.content_margin_right = 4
		t.set_stylebox(estado, "CheckButton", e)
	t.set_stylebox("focus", "CheckButton", _contorno(AMARELO, 12, 3))
	t.set_icon("checked", "CheckButton", _interruptor(true, mobile))
	t.set_icon("unchecked", "CheckButton", _interruptor(false, mobile))

	# Abas (Configurações)
	t.set_stylebox("tab_selected", "TabContainer", _caixa(AMARELO, 14, TINTA, 3, 0, true))
	t.set_stylebox("tab_unselected", "TabContainer", _caixa(Color(NOITE_CLARA, 0.9), 14, TINTA, 3, 0, true))
	t.set_stylebox("tab_hovered", "TabContainer", _caixa(NOITE_CLARA.lightened(0.15), 14, TINTA, 3, 0, true))
	t.set_stylebox("tab_focus", "TabContainer", _contorno(AMARELO, 14, 3))
	t.set_stylebox("panel", "TabContainer", _caixa(Color(NOITE, 0.95), 18, TINTA, 3, 6))
	t.set_font("font", "TabContainer", FONTE_FORTE)
	t.set_color("font_selected_color", "TabContainer", TINTA)
	t.set_color("font_unselected_color", "TabContainer", Color(BRANCO, 0.8))
	t.set_color("font_hovered_color", "TabContainer", BRANCO)

	# Barra de progresso
	t.set_stylebox("background", "ProgressBar", _caixa(Color("0a1426"), 12, TINTA, 2, 0))
	t.set_stylebox("fill", "ProgressBar", _caixa(AMARELO, 12, Color.TRANSPARENT, 0, 0))

	# Rolagem
	var barra := _caixa(Color(1, 1, 1, 0.08), 6, Color.TRANSPARENT, 0, 0)
	barra.content_margin_left = 4
	barra.content_margin_right = 4
	t.set_stylebox("scroll", "VScrollBar", barra)
	t.set_stylebox("grabber", "VScrollBar", _caixa(Color(1, 1, 1, 0.35), 6, Color.TRANSPARENT, 0, 0))
	t.set_stylebox("grabber_highlight", "VScrollBar", _caixa(AMARELO, 6, Color.TRANSPARENT, 0, 0))

	t.set_constant("separation", "VBoxContainer", 12)
	t.set_constant("separation", "HBoxContainer", 12)
	t.set_meta("altura_alvo", alvo)
	return t


static func _botao(t: Theme, tipo: String, cor: Color, texto: Color, mobile: bool) -> void:
	var raio := 16
	var normal := _caixa(cor, raio, TINTA, 3, 5)
	normal.skew = Vector2(INCLINACAO, 0)
	var hover := _caixa(cor.lightened(0.12), raio, TINTA, 3, 7)
	hover.skew = normal.skew
	var press := _caixa(cor.darkened(0.12), raio, TINTA, 3, 1)
	press.skew = normal.skew
	press.content_margin_top += 3
	var desl := _caixa(Color("4a4f63"), raio, Color(TINTA, 0.6), 3, 0)
	desl.skew = normal.skew
	t.set_stylebox("normal", tipo, normal)
	t.set_stylebox("hover", tipo, hover)
	t.set_stylebox("pressed", tipo, press)
	t.set_stylebox("hover_pressed", tipo, press)
	t.set_stylebox("disabled", tipo, desl)
	var foco := _contorno(AMARELO if cor != AMARELO else BRANCO, raio + 2, 4)
	foco.skew = normal.skew
	t.set_stylebox("focus", tipo, foco)
	for estado in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		t.set_color(estado, tipo, texto)
	t.set_color("font_disabled_color", tipo, Color(BRANCO, 0.45))
	t.set_font("font", tipo, FONTE_FORTE)
	t.set_font_size("font_size", tipo, 24 if mobile else 20)
	t.set_constant("h_separation", tipo, 10)


## Fundo padrão das telas de menu (gradiente noturno com rajadas de vento).
static func background() -> ColorRect:
	var fundo := ColorRect.new()
	fundo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fundo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://ui/shared/fundo_vento.gdshader")
	fundo.material = mat
	return fundo


static func _caixa(cor: Color, raio: int, borda: Color, largura: int, sombra_y: int, topo_so := false) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = cor
	s.set_corner_radius_all(raio)
	if topo_so:
		s.corner_radius_bottom_left = 0
		s.corner_radius_bottom_right = 0
	if borda.a > 0 and largura > 0:
		s.border_color = borda
		s.set_border_width_all(largura)
		if topo_so:
			s.border_width_bottom = 0
	if sombra_y > 0:
		# sombra "dura": deslocada, quase sem desfoque
		s.shadow_color = Color(TINTA, 0.85)
		s.shadow_offset = Vector2(0, sombra_y)
		s.shadow_size = 1
	s.content_margin_left = 22
	s.content_margin_right = 22
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	s.anti_aliasing = true
	return s


static func _contorno(cor: Color, raio: int, largura: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.draw_center = false
	s.border_color = cor
	s.set_border_width_all(largura)
	s.set_corner_radius_all(raio)
	s.expand_margin_left = 4
	s.expand_margin_right = 4
	s.expand_margin_top = 4
	s.expand_margin_bottom = 4
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


## Ícone de interruptor (liga/desliga) desenhado em pixels: trilho + bolinha.
static func _interruptor(ligado: bool, mobile: bool) -> ImageTexture:
	var w := 68 if mobile else 56
	var h := 36 if mobile else 30
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var r := h / 2.0
	var trilho := VERDE if ligado else Color("3a4058")
	var cx := w - r if ligado else r
	for y in h:
		for x in w:
			var px := Vector2(x + 0.5, y + 0.5)
			# cápsula: distância ao segmento central
			var q := Vector2(clampf(px.x, r, w - r), r)
			var d := px.distance_to(q)
			var a := clampf(r - d, 0.0, 1.0)
			var cor := TINTA if d > r - 2.5 else trilho
			var db := px.distance_to(Vector2(cx, r))
			if db < r - 4:
				cor = BRANCO
				a = 1.0
			elif db < r - 2.5:
				cor = TINTA
			img.set_pixel(x, y, Color(cor, a * cor.a))
	return ImageTexture.create_from_image(img)
