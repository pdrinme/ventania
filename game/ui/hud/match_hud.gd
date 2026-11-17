class_name MatchHud
extends Control
## HUD da partida Battle Royale: estado no topo (espera, contagem, vivos, fase e
## tempo da Tormenta), aviso e tela roxa dentro da Tormenta, minimapa (canto
## superior direito), mapa completo (M), modo espectador e tela de resultado.

signal back_to_menu
signal spectate_next
signal play_again
signal watch

const TAM_MINI := 176.0

var mapa: Mapa
var tormenta: StormVisual
var onibus: OnibusBatalha           # rota no minimapa/mapa durante a fase do ônibus
var _entrada: Label
var _faixa: Label
var _faixa_t := 0.0
var jogador: Node3D                 # para posição/direção no mapa
var yaw := 0.0
var _textura: ImageTexture
var _estado := {}
var _estado_t := 0.0
var _topo: Label
var _sub: Label
var _aviso: Label
var _roxo: ColorRect
var _mini: Control
var _grande: Control
var _espectador: Label
var resultado: TelaResultado
var _nomes := {}
var _info_col: VBoxContainer
var _regiao: Label
var _regiao_id := ""
var _pois: Array = []               # cache de mapa.points_of_interest()
var eliminacoes := 0                 # minhas eliminações nesta partida (só exibição)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_roxo = ColorRect.new()
	_roxo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_roxo.color = Color(0.45, 0.15, 0.85, 0.0)
	_roxo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_roxo)

	# informações da partida: abaixo do minimapa (ver set_touch_layout)
	var topo := VBoxContainer.new()
	topo.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 10)
	topo.grow_horizontal = Control.GROW_DIRECTION_BOTH
	topo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	topo.add_theme_constant_override("separation", 6)
	add_child(topo)
	_info_col = topo
	_topo = _chip(_rotulo("Subtitulo"))
	_topo.add_theme_font_size_override("font_size", 20)
	topo.add_child(_topo)
	_sub = _chip(_rotulo("Pequeno"))
	topo.add_child(_sub)
	# região atual (nome do POI onde o jogador está), com a cor da região
	_regiao = _chip(_rotulo("Pequeno"))
	_regiao.add_theme_font_override("font", VentaniaTheme.FONTE_FORTE)
	_regiao.visible = false
	topo.add_child(_regiao)

	_aviso = _rotulo("Subtitulo")
	_aviso.add_theme_color_override("font_color", Color("e2b8ff"))
	_aviso.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_aviso.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_aviso.position.y -= 90
	_aviso.visible = false
	add_child(_aviso)

	_mini = Control.new()
	_mini.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 14)
	_mini.custom_minimum_size = Vector2(TAM_MINI, TAM_MINI)
	_mini.size = Vector2(TAM_MINI, TAM_MINI)
	_mini.position = Vector2(-TAM_MINI - 14, 40)
	_mini.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mini.clip_contents = true
	_mini.draw.connect(func(): _desenhar(_mini, false))
	add_child(_mini)

	_grande = Control.new()
	_grande.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_grande.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grande.draw.connect(func(): _desenhar(_grande, true))
	_grande.visible = false
	add_child(_grande)

	_entrada = _rotulo("Subtitulo")
	_entrada.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 96)
	_entrada.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_entrada.add_theme_color_override("font_color", Color("ffd27a"))
	add_child(_entrada)
	_faixa = _rotulo("Subtitulo")
	_faixa.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_faixa.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_faixa.position.y -= 150
	_faixa.add_theme_font_size_override("font_size", 30)
	_faixa.visible = false
	add_child(_faixa)

	_espectador = _rotulo("Subtitulo")
	_espectador.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 150)
	_espectador.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_espectador.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_espectador.visible = false
	add_child(_espectador)

	resultado = TelaResultado.new()
	add_child(resultado)
	resultado.voltar_ao_lobby.connect(func(): back_to_menu.emit())
	resultado.jogar_de_novo.connect(func(): play_again.emit())
	resultado.assistir.connect(func():
		resultado.esconder()
		watch.emit())


func _chip(l: Label) -> Label:
	var sb := VentaniaTheme._caixa(Color(VentaniaTheme.NOITE, 0.78), 12, VentaniaTheme.TINTA, 2, 0)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	l.add_theme_stylebox_override("normal", sb)
	return l


## PC: minimapa no canto superior direito, informações embaixo dele (à direita).
## Toque: minimapa no canto superior esquerdo, informações embaixo (à esquerda).
func set_touch_layout(toque: bool) -> void:
	var m := HudLayout.MARGEM
	var lado := HudLayout.MAPA_TOQUE if toque else HudLayout.MAPA_PC
	_mini.custom_minimum_size = Vector2(lado, lado)
	_mini.size = Vector2(lado, lado)
	if toque:
		HudLayout.pin(_mini, 0.0, 0.0, m, m, 1, 1)
		HudLayout.pin(_info_col, 0.0, 0.0, m, m + lado + 8, 1, 1)
	else:
		HudLayout.pin(_mini, 1.0, 0.0, -m, m, -1, 1)
		HudLayout.pin(_info_col, 1.0, 0.0, -m, m + lado + 8, -1, 1)
	_info_col.alignment = BoxContainer.ALIGNMENT_BEGIN
	for l: Label in [_topo, _sub, _regiao]:
		l.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN if toque else Control.SIZE_SHRINK_END


func _rotulo(variacao: String) -> Label:
	var l := Label.new()
	l.theme_type_variation = variacao
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_outline_color", Color("24252c"))
	l.add_theme_constant_override("outline_size", 8)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func setup(m: Mapa, t: StormVisual) -> void:
	mapa = m
	tormenta = t
	_textura = _gerar_textura(m)
	_pois = m.points_of_interest()
	_mini.visible = m.map_name() == IlhaVentania.NOME


func set_names(n: Dictionary) -> void:
	_nomes = n


## Imagem do mapa (gerada uma vez): água, praia, grama/morros, estradas e as
## construções do mapa vistas de cima. As regiões (cores e contornos) são
## desenhadas por cima, como polígonos, para ficarem nítidas em qualquer zoom.
static func _gerar_textura(m: Mapa) -> ImageTexture:
	var tam := 300
	var img := Image.create(tam, tam, false, Image.FORMAT_RGB8)
	var lim := m.limit()
	var com_estradas := m.has_method("road_distance")
	for y in tam:
		for x in tam:
			var wx := -lim + (x + 0.5) / tam * lim * 2.0
			var wz := -lim + (y + 0.5) / tam * lim * 2.0
			var h := m.ground_height(wx, wz)
			var c := Color("3fb6d9")
			if h > 0.6:
				c = Color("6cc24a").darkened(clampf((h - 6.0) / 30.0, -0.2, 0.3))
				if com_estradas and m.road_distance(wx, wz) < 3.2:
					c = Color("d9d2bd")
			elif h > -0.6:
				c = Color("e8d49a")
			img.set_pixel(x, y, c)
	# construções: telhados/pisos do mapa em tom claro, com borda escura
	var px := tam / (lim * 2.0)
	var feitos := {}
	for d: Dictionary in m.building_pieces():
		if d["tipo"] != Grade.PISO and d["tipo"] != Grade.TETO:
			continue
		var cell: Vector3i = d["cell"]
		var k := Vector2i(cell.x, cell.z)
		if feitos.has(k):
			continue
		feitos[k] = true
		var x0 := roundi((cell.x * 4.0 + lim) * px)
		var y0 := roundi((cell.z * 4.0 + lim) * px)
		var lado := maxi(2, roundi(4.0 * px))
		img.fill_rect(Rect2i(x0, y0, lado, lado), Color("8a7f74"))
		if lado > 2:
			img.fill_rect(Rect2i(x0, y0, lado - 1, lado - 1), Color("efe6d6"))
	return ImageTexture.create_from_image(img)


func set_match(m: Dictionary) -> void:
	_estado = m
	_estado_t = Time.get_ticks_msec() / 1000.0


func show_result(r: Dictionary, meu_nome: String, nome_vencedor: String, eu_venci: bool, traje: String, pode_assistir: bool, pode_jogar_de_novo: bool) -> void:
	resultado.mostrar(r, meu_nome, nome_vencedor, eu_venci, traje, pode_assistir, pode_jogar_de_novo)


## Etapa 9: XP desta partida, calculado e concedido pelo meta-servidor.
func show_progress(p: Dictionary) -> void:
	var linhas := []
	for x: Dictionary in p.get("xp", []):
		linhas.append("%s  +%d" % [x["motivo"], int(x["xp"])])
	var topo := "+%d XP" % int(p.get("xp_total", 0))
	if int(p.get("nivel", 0)) > int(p.get("nivel_antes", 0)):
		topo += "  ·  NÍVEL %d!" % int(p["nivel"])
	if int(p.get("faiscas", 0)) > 0:
		topo += "  ·  +%d Faíscas" % int(p["faiscas"])
	var passe: Variant = p.get("passe")
	if passe is Dictionary and int(passe.get("nivel", 0)) > int(passe.get("nivel_antes", 0)):
		topo += "  ·  PASSE NÍVEL %d" % int(passe["nivel"])
	for d: Dictionary in p.get("desbloqueados", []):
		linhas.append("Desbloqueado: %s" % d.get("nome", "?"))
	resultado.set_progress(topo + "\n" + "\n".join(linhas))
	var subiu: bool = int(p.get("nivel", 0)) > int(p.get("nivel_antes", 0)) or (passe is Dictionary and int(passe.get("nivel", 0)) > int(passe.get("nivel_antes", 0)))
	Audio.play_ui("nivel" if subiu else ("recompensa" if not p.get("desbloqueados", []).is_empty() else "confirmar"))


func hide_result() -> void:
	resultado.esconder()


func result_visible() -> bool:
	return resultado.visible


## Aviso da entrada na partida (no ônibus, em queda, planando). Vazio = esconder.
func set_entry(texto: String) -> void:
	_entrada.text = texto


## Faixa grande e temporária no meio da tela (fases da Tormenta).
func banner(texto: String, cor := Color.WHITE, segundos := 4.0) -> void:
	_faixa.text = texto
	_faixa.add_theme_color_override("font_color", cor)
	_faixa.visible = true
	_faixa_t = segundos


## Região onde o jogador (ou quem ele assiste) está: chip abaixo do minimapa e, ao
## entrar numa região nova durante a partida, o nome dela em destaque.
func _atualizar_regiao() -> void:
	if mapa == null or jogador == null or not _mini.visible:
		_regiao.visible = false
		return
	var r := mapa.region_at(jogador.global_position.x, jogador.global_position.z)
	var id: String = r.get("id", "")
	if id != _regiao_id:
		_regiao_id = id
		if not id.is_empty():
			_regiao.text = r["nome"]
			_regiao.add_theme_color_override("font_color", (r["cor"] as Color).lightened(0.35))
			var e := int(_estado.get("estado", 0))
			if e == Protocol.MATCH_JOGO and jogador is Node3D and jogador.global_position.y - mapa.ground_height(jogador.global_position.x, jogador.global_position.z) < 6.0:
				banner(r["nome"], (r["cor"] as Color).lightened(0.3), 2.5)
	_regiao.visible = not _regiao_id.is_empty()


func set_spectating(nome: String) -> void:
	_espectador.visible = not nome.is_empty()
	_espectador.text = "Assistindo %s  ·  Atirar: próximo  ·  Esc: menu" % nome if not nome.is_empty() else ""


func toggle_map(v: bool) -> void:
	_grande.visible = v and _mini.visible
	_grande.queue_redraw()


func map_open() -> bool:
	return _grande.visible


static func _tempo(s: float) -> String:
	var t := maxi(0, ceili(s))
	return "%d:%02d" % [t / 60, t % 60]


func _process(_delta: float) -> void:
	var resta := 0.0
	if not _estado.is_empty():
		resta = _estado["resta_ms"] / 1000.0 - (Time.get_ticks_msec() / 1000.0 - _estado_t)
	match int(_estado.get("estado", Protocol.MATCH_TREINO)):
		Protocol.MATCH_ESPERA:
			_topo.text = "Procurando jogadores (%d)" % _estado["vivos"]
			_sub.text = "Sem mais ninguém, os bots completam a partida em %s" % _tempo(resta) if resta > 0.0 else "Esperando os jogadores entrarem…"
		Protocol.MATCH_CONTAGEM:
			_topo.text = "A partida começa em %d" % ceili(maxf(0.0, resta))
			_sub.text = "Você vai aparecer num ponto do mapa, só com a picareta."
		Protocol.MATCH_ONIBUS:
			_topo.text = "Ônibus de Batalha · %d %s" % [_estado["total"], "jogador" if _estado["total"] == 1 else "jogadores"]
			_sub.text = "Salte sobre a ilha · a Tormenta se forma quando o ônibus partir (%s)" % _tempo(resta)
		Protocol.MATCH_JOGO:
			_topo.text = "%d %s  ·  %d %s" % [_estado["vivos"], "vivo" if _estado["vivos"] == 1 else "vivos",
					eliminacoes, "eliminação" if eliminacoes == 1 else "eliminações"]
			if tormenta and tormenta.active():
				var d: Dictionary = tormenta.dados
				if d["terminou"]:
					_sub.text = "Tormenta: zona final"
				else:
					_sub.text = "Fase %d/%d · %s %s" % [d["fase"] + 1, d["fases"], "Tormenta fechando:" if d["fechando"] else "Tormenta fecha em", _tempo(tormenta.seconds_left())]
		Protocol.MATCH_FIM:
			var nome: String = _nomes.get(_estado["vencedor"], "")
			_topo.text = ("Vitória de %s!" % nome) if not nome.is_empty() else "Fim de partida"
			_sub.text = "Nova partida em %s" % _tempo(resta)
		_:
			_topo.text = ""
			_sub.text = ""
	var fora := jogador != null and tormenta != null and jogador.visible and tormenta.is_outside(jogador.global_position) \
			and int(_estado.get("estado", 0)) == Protocol.MATCH_JOGO
	_aviso.visible = fora
	if fora:
		_aviso.text = "Você está na Tormenta! (−%d/s)" % int(tormenta.dados.get("dano", 0))
	_roxo.color.a = move_toward(_roxo.color.a, 0.22 if fora else 0.0, get_process_delta_time() * 0.8)
	if _faixa_t > 0.0:
		_faixa_t -= get_process_delta_time()
		_faixa.modulate.a = clampf(_faixa_t / 0.6, 0.0, 1.0)
		_faixa.visible = _faixa_t > 0.0
	_topo.visible = not _topo.text.is_empty()
	_sub.visible = not _sub.text.is_empty()
	_atualizar_regiao()
	if _mini.visible:
		_mini.queue_redraw()
	if _grande.visible:
		_grande.queue_redraw()


## Nomes dos POIs. Mapa inteiro: todos, em etiqueta com a cor da região (afasta
## etiquetas que se encostariam). Minimapa: fonte menor, só os que cabem inteiros,
## sem cobrir a seta do jogador nem outra etiqueta; a região em que o jogador está
## tem prioridade (e também aparece no chip abaixo do minimapa).
func _nomes_regioes(c: Control, inteiro: bool, area: Rect2, para_tela: Callable) -> void:
	var f := VentaniaTheme.FONTE_FORTE if VentaniaTheme.FONTE_FORTE else get_theme_default_font()
	var tam := int(clampf(area.size.x / 34.0, 14.0, 22.0)) if inteiro else int(clampf(area.size.x / 15.0, 11.0, 14.0))
	var ocupados: Array[Rect2] = []
	if not inteiro:
		ocupados.append(Rect2(area.get_center() - Vector2(12, 12), Vector2(24, 24)))   # seta do jogador
	var ordem := _pois.duplicate()
	ordem.sort_custom(func(a, b): return a["id"] == _regiao_id and b["id"] != _regiao_id)
	for poi in ordem:
		var nome: String = poi["nome"]
		var centro: Vector2 = para_tela.call(Vector2(poi["pos"].x, poi["pos"].z))
		var w := f.get_string_size(nome, HORIZONTAL_ALIGNMENT_LEFT, -1, tam).x
		var caixa := Rect2(centro - Vector2(w / 2.0 + 8.0, tam * 0.75), Vector2(w + 16.0, tam * 1.45))
		if inteiro:
			# afasta para baixo se encostar em outra etiqueta
			for i in 4:
				var bate := false
				for o in ocupados:
					if o.grow(3).intersects(caixa):
						bate = true
				if not bate:
					break
				caixa.position.y += caixa.size.y + 4.0
		else:
			# tenta no centro do POI, logo acima e logo abaixo (desvia da seta do jogador)
			var achou := false
			for dy in [0.0, -caixa.size.y - 6.0, caixa.size.y + 6.0]:
				var tenta := Rect2(caixa.position + Vector2(0, dy), caixa.size)
				if not area.grow(-2).encloses(tenta):
					continue
				var bate := false
				for o in ocupados:
					if o.intersects(tenta):
						bate = true
				if not bate:
					caixa = tenta
					achou = true
					break
			if not achou:
				continue
		ocupados.append(caixa)
		var cor: Color = poi["cor"]
		var base := caixa.position + Vector2(8.0, tam * 1.07)
		if inteiro:
			c.draw_rect(caixa, Color(VentaniaTheme.TINTA, 0.78))
			c.draw_rect(Rect2(caixa.position, Vector2(4, caixa.size.y)), cor)
			c.draw_string(f, base + Vector2(2, 0), nome, HORIZONTAL_ALIGNMENT_LEFT, -1, tam, Color.WHITE)
		else:
			c.draw_string_outline(f, base, nome, HORIZONTAL_ALIGNMENT_LEFT, -1, tam, 4, VentaniaTheme.TINTA)
			c.draw_string(f, base, nome, HORIZONTAL_ALIGNMENT_LEFT, -1, tam, cor.lightened(0.45))


## Desenha o mapa (minimapa centrado no jogador ou mapa inteiro), zonas e jogador.
func _desenhar(c: Control, inteiro: bool) -> void:
	if mapa == null or _textura == null:
		return
	var lim := mapa.limit()
	var area: Rect2
	var escala: float                # px por metro
	var origem: Vector2              # mundo (x, z) no canto superior esquerdo
	if inteiro:
		var lado := minf(c.size.x, c.size.y) * 0.86
		area = Rect2((c.size - Vector2(lado, lado)) / 2.0, Vector2(lado, lado))
		escala = lado / (lim * 2.0)
		origem = Vector2(-lim, -lim)
		c.draw_rect(Rect2(Vector2.ZERO, c.size), Color(0, 0, 0, 0.55))
	else:
		area = Rect2(Vector2.ZERO, c.size)
		var raio_m := 140.0
		escala = c.size.x / (raio_m * 2.0)
		var centro := Vector2(jogador.global_position.x, jogador.global_position.z) if jogador else Vector2.ZERO
		origem = centro - Vector2(raio_m, raio_m)
	var para_tela := func(w: Vector2) -> Vector2: return area.position + (w - origem) * escala
	# fundo: recorte da imagem do mapa
	var px := _textura.get_size().x / (lim * 2.0)
	var fonte := Rect2((origem + Vector2(lim, lim)) * px, area.size / escala * px)
	c.draw_texture_rect_region(_textura, area, fonte)
	# regiões: preenchimento leve e contorno na cor de cada POI (dados do mapa)
	for poi in _pois:
		var pts := PackedVector2Array()
		for q: Vector2 in poi["limite"]:
			pts.append(para_tela.call(q))
		if pts.size() < 3:
			continue
		var cor: Color = poi["cor"]
		c.draw_colored_polygon(pts, Color(cor, 0.2 if inteiro else 0.16))
		var fechado := pts.duplicate()
		fechado.append(pts[0])
		c.draw_polyline(fechado, Color(cor.darkened(0.15), 0.95), 2.5 if inteiro else 1.6, true)
	# zonas
	if tormenta and tormenta.active():
		var atual := tormenta.current()
		var prox := tormenta.next_zone()
		c.draw_arc(para_tela.call(prox[0]), float(prox[1]) * escala, 0, TAU, 64, Color.WHITE, 2.0, true)
		c.draw_arc(para_tela.call(atual[0]), float(atual[1]) * escala, 0, TAU, 96, Color("b15cff"), 3.0, true)
	# rota do Ônibus de Batalha (tracejada, com seta no sentido do voo)
	if onibus and int(_estado.get("estado", 0)) == Protocol.MATCH_ONIBUS:
		var a: Vector2 = para_tela.call(Vector2(onibus.inicio.x, onibus.inicio.z))
		var b: Vector2 = para_tela.call(Vector2(onibus.fim.x, onibus.fim.z))
		c.draw_dashed_line(a, b, Color("ffc93c"), 3.0, 10.0)
		var dir := a.direction_to(b)
		var meio := a.lerp(b, 0.5)
		c.draw_colored_polygon(PackedVector2Array([meio + dir * 10, meio - dir * 6 + Vector2(-dir.y, dir.x) * 7, meio - dir * 6 - Vector2(-dir.y, dir.x) * 7]), Color("ffc93c"))
	_nomes_regioes(c, inteiro, area, para_tela)
	# jogador: seta na direção do olhar
	if jogador:
		var p: Vector2 = para_tela.call(Vector2(jogador.global_position.x, jogador.global_position.z))
		var dir := Vector2(-sin(yaw), -cos(yaw))
		var lado := Vector2(-dir.y, dir.x)
		c.draw_colored_polygon(PackedVector2Array([p + dir * 9, p - dir * 5 + lado * 6, p - dir * 5 - lado * 6]), Color("ffc93c"))
	if inteiro:
		c.draw_rect(area, Color(1, 1, 1, 0.6), false, 2.0)
	else:
		# moldura no estilo do HUD: contorno grosso escuro com filete claro
		c.draw_rect(area.grow(-2), VentaniaTheme.TINTA, false, 4.0)
		c.draw_rect(area.grow(-5), Color(1, 1, 1, 0.35), false, 1.5)
