class_name TelaResultado
extends Control
## Fim de partida para quem joga (Battle Royale): vitória ou colocação, o personagem
## usado, as estatísticas que o servidor registra e botões claros.
## - PC: o mouse fica livre; Enter/Espaço ativam o botão em foco; setas e controle
##   navegam; Esc continua sendo atalho para "Voltar ao lobby" (mas não é o único jeito).
## - Celular: botões grandes (altura do tema de toque), sem depender de teclado.
## O resultado vem do servidor (S_RESULT): todos os clientes recebem o mesmo vencedor.
## Quem é eliminado recebe o resultado na hora (vencedor ainda 0) e de novo no fim.

signal voltar_ao_lobby
signal jogar_de_novo
signal assistir

var _painel: PanelContainer
var _titulo: Label
var _sub: Label
var _grade: GridContainer
var _xp: Label
var _vitrine_box: Control
var _vitrine: VitrineCosmetico
var _traje_mostrado := ""
var _b_assistir: Button
var _b_menu: Button
var _b_denovo: Button
var _confete: CPUParticles2D
var _ja_comemorou := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var fundo := ColorRect.new()
	fundo.color = Color(0.03, 0.04, 0.09, 0.78)
	fundo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fundo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fundo)
	_confete = CPUParticles2D.new()
	_confete.emitting = false
	_confete.one_shot = true
	_confete.amount = 140
	_confete.lifetime = 3.2
	_confete.explosiveness = 0.85
	_confete.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_confete.direction = Vector2(0, 1)
	_confete.spread = 25.0
	_confete.gravity = Vector2(0, 260)
	_confete.initial_velocity_min = 60.0
	_confete.initial_velocity_max = 220.0
	_confete.angular_velocity_min = -360.0
	_confete.angular_velocity_max = 360.0
	_confete.scale_amount_min = 5.0
	_confete.scale_amount_max = 9.0
	var cores := Gradient.new()
	cores.offsets = PackedFloat32Array([0.0, 0.33, 0.66, 1.0])
	cores.colors = PackedColorArray([VentaniaTheme.AMARELO, Color("4fa8ff"), Color("ff6f91"), Color("5ee08a")])
	_confete.color_initial_ramp = cores
	add_child(_confete)

	_painel = PanelContainer.new()
	_painel.theme_type_variation = "Cartao"
	_painel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_painel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_painel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(_painel)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 22)
	_painel.add_child(h)
	_vitrine_box = Control.new()
	_vitrine_box.custom_minimum_size = Vector2(260, 340)
	h.add_child(_vitrine_box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.custom_minimum_size.x = 380
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(v)
	_titulo = Label.new()
	_titulo.theme_type_variation = "Titulo"
	_titulo.add_theme_font_size_override("font_size", 54)
	v.add_child(_titulo)
	_sub = Label.new()
	_sub.theme_type_variation = "Subtitulo"
	_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_sub)
	_grade = GridContainer.new()
	_grade.columns = 2
	_grade.add_theme_constant_override("h_separation", 26)
	_grade.add_theme_constant_override("v_separation", 4)
	v.add_child(_grade)
	_xp = Label.new()
	_xp.theme_type_variation = "Pequeno"
	_xp.add_theme_color_override("font_color", VentaniaTheme.AMARELO)
	_xp.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_xp.visible = false
	v.add_child(_xp)
	var botoes := HBoxContainer.new()
	botoes.add_theme_constant_override("separation", 10)
	v.add_child(botoes)
	_b_denovo = _botao("JOGAR DE NOVO", "BotaoPrimario", botoes)
	_b_denovo.pressed.connect(func(): jogar_de_novo.emit())
	_b_menu = _botao("VOLTAR AO LOBBY", "", botoes)
	_b_menu.pressed.connect(func(): voltar_ao_lobby.emit())
	_b_assistir = _botao("ASSISTIR", "BotaoFantasma", botoes)
	_b_assistir.pressed.connect(func(): assistir.emit())


func _botao(texto: String, variacao: String, pai: Control) -> Button:
	var b := Button.new()
	b.text = texto
	b.theme_type_variation = variacao
	b.custom_minimum_size = Vector2(150, maxf(56.0, float(get_tree().root.theme.get_meta("altura_alvo", 52)) + 6.0) if get_tree().root.theme else 56.0)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.focus_mode = Control.FOCUS_ALL
	pai.add_child(b)
	return b


## r: {colocacao, total, eliminacoes, tempo_s, vencedor, dano, baus, curas, coleta, construcoes}
## nome_vencedor: "" se ainda não há vencedor. pode_assistir: a partida continua.
func mostrar(r: Dictionary, meu_nome: String, nome_vencedor: String, eu_venci: bool, traje: String, pode_assistir: bool, pode_jogar_de_novo: bool) -> void:
	visible = true
	if eu_venci:
		_titulo.text = "VITÓRIA!"
		_titulo.add_theme_color_override("font_color", VentaniaTheme.AMARELO)
		_sub.text = "%s é o último de pé entre %d jogadores." % [meu_nome, int(r["total"])]
	else:
		_titulo.text = "#%d de %d" % [int(r["colocacao"]), int(r["total"])]
		_titulo.add_theme_color_override("font_color", Color.WHITE)
		_sub.text = meu_nome + (("  ·  Vencedor: %s" % nome_vencedor) if not nome_vencedor.is_empty() else "  ·  A partida continua")
	for c in _grade.get_children():
		c.queue_free()
	var t := int(r["tempo_s"])
	var linhas := [["Eliminações", str(int(r["eliminacoes"]))], ["Tempo vivo", "%d:%02d" % [t / 60, t % 60]]]
	for k in [["dano", "Dano causado"], ["baus", "Baús abertos"], ["curas", "Curas usadas"], ["coleta", "Materiais coletados"], ["construcoes", "Construções"]]:
		if r.has(k[0]):
			linhas.append([k[1], str(int(r[k[0]]))])
	for l in linhas:
		var a := Label.new()
		a.text = l[0]
		a.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
		_grade.add_child(a)
		var b := Label.new()
		b.text = l[1]
		b.add_theme_font_override("font", VentaniaTheme.FONTE_FORTE)
		b.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_grade.add_child(b)
	_b_assistir.visible = pode_assistir
	_b_denovo.visible = pode_jogar_de_novo
	_trocar_vitrine(traje, eu_venci)
	if eu_venci and not _ja_comemorou:
		_ja_comemorou = true
		_confete.position = Vector2(size.x / 2.0, -20)
		_confete.emission_rect_extents = Vector2(size.x / 2.0, 10)
		_confete.restart()
	(_b_denovo if pode_jogar_de_novo else _b_menu).grab_focus.call_deferred()


func _trocar_vitrine(traje: String, venceu: bool) -> void:
	var chave := "%s|%s" % [traje, venceu]
	if chave == _traje_mostrado or traje.is_empty() or DisplayServer.get_name() == "headless":
		return
	_traje_mostrado = chave
	if _vitrine:
		_vitrine.queue_free()
	_vitrine = VitrineCosmetico.criar(traje, "traje", "lendario" if venceu else "raro")
	_vitrine.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vitrine_box.add_child(_vitrine)
	if venceu:
		_vitrine.animar("acenar")


func set_progress(texto: String) -> void:
	_xp.text = texto
	_xp.visible = not texto.is_empty()


func esconder() -> void:
	visible = false
	_ja_comemorou = false
	_xp.visible = false


func _unhandled_input(e: InputEvent) -> void:
	if not visible:
		return
	if e.is_action_pressed("ui_cancel") or e.is_action_pressed("pause"):
		voltar_ao_lobby.emit()
		get_viewport().set_input_as_handled()
