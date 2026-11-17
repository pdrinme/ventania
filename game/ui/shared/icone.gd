class_name IconeUI
extends Control
## Ícones simples de interface desenhados por código (sem imagens de terceiros):
## "engrenagem", "amigos", "mais", "fechar", "ok", "coroa", "cadeado", "sair",
## "seta", "pessoa". Cor e tamanho vêm de `cor` e do tamanho do controle.

@export var nome := "mais"
@export var cor := Color("f6f3ec")
@export var espessura := 3.0


static func criar(n: String, tamanho := 24.0, c := Color("f6f3ec")) -> IconeUI:
	var i := IconeUI.new()
	i.nome = n
	i.cor = c
	i.custom_minimum_size = Vector2(tamanho, tamanho)
	i.size = i.custom_minimum_size
	i.grow_horizontal = Control.GROW_DIRECTION_BOTH
	i.grow_vertical = Control.GROW_DIRECTION_BOTH
	i.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return i


func _draw() -> void:
	var s := minf(size.x, size.y)
	var c := size / 2.0
	var e := maxf(2.0, espessura * s / 24.0)
	match nome:
		"mais":
			draw_line(c - Vector2(s * 0.35, 0), c + Vector2(s * 0.35, 0), cor, e, true)
			draw_line(c - Vector2(0, s * 0.35), c + Vector2(0, s * 0.35), cor, e, true)
		"fechar":
			var d := s * 0.28
			draw_line(c + Vector2(-d, -d), c + Vector2(d, d), cor, e, true)
			draw_line(c + Vector2(-d, d), c + Vector2(d, -d), cor, e, true)
		"ok":
			draw_polyline(PackedVector2Array([c + Vector2(-s * 0.3, 0), c + Vector2(-s * 0.08, s * 0.22), c + Vector2(s * 0.32, -s * 0.22)]), cor, e, true)
		"seta":
			draw_polyline(PackedVector2Array([c + Vector2(s * 0.1, -s * 0.28), c + Vector2(-s * 0.18, 0), c + Vector2(s * 0.1, s * 0.28)]), cor, e, true)
		"engrenagem":
			var pts := PackedVector2Array()
			for i in 48:
				var a := TAU * i / 48.0
				var r := s * (0.46 if (i / 3) % 2 == 0 else 0.34)
				pts.append(c + Vector2(cos(a), sin(a)) * r)
			draw_colored_polygon(pts, cor)
			draw_circle(c, s * 0.14, Color("15161c"))
		"pessoa":
			draw_circle(c + Vector2(0, -s * 0.16), s * 0.17, cor)
			draw_colored_polygon(_semicirculo(c + Vector2(0, s * 0.38), s * 0.3), cor)
		"amigos":
			draw_circle(c + Vector2(s * 0.16, -s * 0.18), s * 0.13, Color(cor, 0.7))
			draw_colored_polygon(_semicirculo(c + Vector2(s * 0.16, s * 0.3), s * 0.24), Color(cor, 0.7))
			draw_circle(c + Vector2(-s * 0.1, -s * 0.12), s * 0.15, cor)
			draw_colored_polygon(_semicirculo(c + Vector2(-s * 0.1, s * 0.4), s * 0.27), cor)
		"coroa":
			draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.38, s * 0.25), c + Vector2(-s * 0.4, -s * 0.2),
					c + Vector2(-s * 0.15, s * 0.02), c + Vector2(0, -s * 0.32), c + Vector2(s * 0.15, s * 0.02),
					c + Vector2(s * 0.4, -s * 0.2), c + Vector2(s * 0.38, s * 0.25)]), cor)
		"cadeado":
			draw_rect(Rect2(c + Vector2(-s * 0.3, -s * 0.02), Vector2(s * 0.6, s * 0.42)), cor)
			draw_arc(c + Vector2(0, -s * 0.05), s * 0.2, PI, TAU, 16, cor, e, true)
		"faisca":
			# estrela de 4 pontas (a moeda Faíscas)
			var pts := PackedVector2Array()
			for i in 8:
				var a := TAU * i / 8.0 - PI / 2
				var r := s * (0.46 if i % 2 == 0 else 0.16)
				pts.append(c + Vector2(cos(a), sin(a)) * r)
			draw_colored_polygon(pts, cor)
		"missoes":
			# prancheta com dois itens marcados
			draw_rect(Rect2(c + Vector2(-s * 0.32, -s * 0.38), Vector2(s * 0.64, s * 0.78)), cor, false, e)
			for k in 2:
				var y := -s * 0.14 + k * s * 0.26
				draw_polyline(PackedVector2Array([c + Vector2(-s * 0.2, y), c + Vector2(-s * 0.12, y + s * 0.08), c + Vector2(-s * 0.02, y - s * 0.06)]), cor, e * 0.8, true)
				draw_line(c + Vector2(s * 0.04, y), c + Vector2(s * 0.2, y), cor, e * 0.8, true)
		"sair":
			draw_rect(Rect2(c + Vector2(-s * 0.38, -s * 0.36), Vector2(s * 0.4, s * 0.72)), cor, false, e)
			draw_line(c + Vector2(-s * 0.05, 0), c + Vector2(s * 0.4, 0), cor, e, true)
			draw_polyline(PackedVector2Array([c + Vector2(s * 0.22, -s * 0.16), c + Vector2(s * 0.4, 0), c + Vector2(s * 0.22, s * 0.16)]), cor, e, true)


static func _semicirculo(base: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 17:
		var a := PI + PI * i / 16.0
		pts.append(base + Vector2(cos(a), sin(a)) * r)
	return pts
