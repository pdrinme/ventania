extends Control
## Lobby (Etapa 8, com o redesign da interface). Personagem em destaque no
## centro e o grupo ao lado (até 4), modo de jogo e JOGAR no canto, amigos à
## direita, conta e opções no topo. Sem conta (ou sem meta-servidor), os modos
## offline continuam funcionando.

const MODOS := [
	{"id": "br_online", "titulo": "Battle Royale", "sub": "Ilha Ventania · até 16 jogadores com bots", "online": true, "meta": "br"},
	{"id": "privada", "titulo": "Sala privada", "sub": "Só com código · você decide quando começa", "online": true, "meta": "br"},
	{"id": "treino_online", "titulo": "Campo de treino online", "sub": "Treino livre com o grupo", "online": true, "meta": "treino"},
	{"id": "br_local", "titulo": "Battle Royale solo", "sub": "Offline · você contra 15 bots", "online": false},
	{"id": "local", "titulo": "Campo de treino", "sub": "Offline · bonecos e baús", "online": false},
	{"id": "direto", "titulo": "Servidor por endereço", "sub": "IP:porta em Configurações → Rede", "online": false},
]
const POS_GRUPO := [Vector3(0, 0, 0), Vector3(-1.75, 0, 0.55), Vector3(1.75, 0, 0.55), Vector3(-3.3, 0, 1.2)]

static var _modo_id := ""

var _alvo := 52
var _cam: Camera3D
var _vp3d: SubViewport
var _bonecos: Array[Node3D] = []
var _trajes_slot: Array[String] = ["", "", "", ""]
var _placas: Array[Control] = []
var _vagas: Array[Button] = []
var _status_txt: Label
var _status_bola: ColorRect
var _conta_btn: Button
var _amigos_btn: Button
var _amigos_badge: Label
var _modo_titulo: Label
var _modo_sub: Label
var _jogar: Button
var _busca: PanelContainer
var _busca_txt: Label
var _sobreposicao: Control      # modal aberto (login, modos, sala privada)
var _gaveta: PanelContainer     # amigos
var _gaveta_lista: VBoxContainer
var _avisos: VBoxContainer
var _prog_chip: Button          # nível, XP e Faíscas (abre o perfil)
var _prog_nivel: Label
var _prog_barra: ProgressBar
var _prog_faiscas: Label
var _missoes_btn: Button
var _passe_btn: Button
var _loja_btn: Button
const CORES_RARIDADE := {"comum": Color("9aa3b5"), "incomum": Color("5ee08a"), "raro": Color("4fa8ff"),
		"epico": Color("b56bff"), "lendario": Color("ffb43c"), "mitico": Color("ff7ad9")}


func _ready() -> void:
	_alvo = get_tree().root.theme.get_meta("altura_alvo", 52)
	add_child(VentaniaTheme.background())
	_mundo_3d()
	_montar_topo()
	_montar_canto()
	_montar_rodape()
	_avisos = VBoxContainer.new()
	_avisos.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_avisos.position.y = 92
	_avisos.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_avisos.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_avisos)

	Meta.status_changed.connect(func(_s, _i, _e): _atualizar())
	Meta.account_changed.connect(func(_a): _atualizar())
	Meta.party_changed.connect(func(_p): _atualizar())
	Meta.friends_changed.connect(func(_f):
		_atualizar()
		_preencher_amigos())
	Meta.invite_received.connect(_on_convite)
	Meta.friend_request.connect(func(de): _aviso("%s quer ser seu amigo." % de.get("username", "?"), "Ver", _abrir_amigos, 6.0, "", Callable(), "notificacao"))
	Meta.match_found.connect(_on_partida)
	Meta.profile_changed.connect(func(_p): _atualizar())
	Meta.notice.connect(func(t): _aviso(t))
	if _modo_id.is_empty():
		_modo_id = "br_online" if Meta.logged_in() else "br_local"
	_atualizar()
	_jogar.grab_focus.call_deferred()
	if not SceneManager.message.is_empty():
		_aviso(SceneManager.message)
		SceneManager.message = ""
	if Meta.state == "desconhecido":
		Meta.refresh()


func _process(_dt: float) -> void:
	# placas de nome e vagas acompanham os personagens (projeção 3D -> tela)
	if _cam == null:
		return
	var escala := size / Vector2(_vp3d.size) if _vp3d.size.x > 0 else Vector2.ONE
	for i in POS_GRUPO.size():
		var p := _cam.unproject_position(POS_GRUPO[i] + Vector3(0, 2.15, 0)) * escala
		_placas[i].position = p - Vector2(_placas[i].size.x / 2.0, _placas[i].size.y)
		var pv := _cam.unproject_position(POS_GRUPO[i] + Vector3(0, 1.0, 0)) * escala
		_vagas[i].position = pv - _vagas[i].size / 2.0
	if _busca.visible:
		_busca.modulate.a = 0.72 + 0.28 * sin(Time.get_ticks_msec() / 1000.0 * 4.0)    # pulsa enquanto procura
	if _busca.visible and Meta.party.get("state", "") == "fila":
		_busca_txt.text = "PROCURANDO PARTIDA  %s" % _relogio(Time.get_ticks_msec() / 1000.0 - _busca_ini)


var _busca_ini := 0.0


# ---------------------------------------------------------------- montagem

func _montar_topo() -> void:
	var topo := HBoxContainer.new()
	topo.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	topo.offset_left = 32
	topo.offset_right = -32
	topo.offset_top = 20
	topo.add_theme_constant_override("separation", 10)
	add_child(topo)
	var logo := Label.new()
	logo.theme_type_variation = "Titulo"
	logo.text = "VENTANIA"
	logo.add_theme_font_size_override("font_size", 46 if Settings.is_mobile else 40)
	logo.add_theme_constant_override("outline_size", 12)
	topo.add_child(logo)
	var vazio := Control.new()
	vazio.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	topo.add_child(vazio)
	_montar_progresso(topo)
	_loja_btn = _botao_icone("loja", "Loja", "BotaoFantasma")
	_loja_btn.pressed.connect(_abrir_loja)
	topo.add_child(_loja_btn)
	_passe_btn = _botao_icone("passe", "Passe", "BotaoFantasma")
	_passe_btn.pressed.connect(_abrir_passe)
	topo.add_child(_passe_btn)
	_missoes_btn = _botao_icone("missoes", "Missões", "BotaoFantasma")
	_missoes_btn.pressed.connect(_abrir_missoes)
	topo.add_child(_missoes_btn)
	_conta_btn = _botao_icone("pessoa", "Entrar", "BotaoFantasma")
	_conta_btn.pressed.connect(_on_conta)
	topo.add_child(_conta_btn)
	_amigos_btn = _botao_icone("amigos", "", "BotaoFantasma")
	_amigos_btn.tooltip_text = "Amigos"
	_amigos_btn.pressed.connect(_abrir_amigos)
	topo.add_child(_amigos_btn)
	_amigos_badge = Label.new()
	_amigos_badge.add_theme_color_override("font_color", VentaniaTheme.TINTA)
	var bs := VentaniaTheme._caixa(VentaniaTheme.CORAL, 12, VentaniaTheme.TINTA, 2, 0)
	bs.content_margin_left = 7
	bs.content_margin_right = 7
	bs.content_margin_top = 0
	bs.content_margin_bottom = 0
	_amigos_badge.add_theme_stylebox_override("normal", bs)
	_amigos_badge.add_theme_font_override("font", VentaniaTheme.FONTE_FORTE)
	_amigos_badge.add_theme_font_size_override("font_size", 14)
	_amigos_badge.position = Vector2(-6, -8)
	_amigos_btn.add_child(_amigos_badge)
	var engrenagem := _botao_icone("engrenagem", "", "BotaoFantasma")
	engrenagem.tooltip_text = "Opções"
	engrenagem.pressed.connect(func(): _menu_opcoes(engrenagem))
	topo.add_child(engrenagem)


func _montar_canto() -> void:
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	col.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	col.grow_vertical = Control.GROW_DIRECTION_BEGIN
	col.offset_right = -40
	col.offset_bottom = -36
	col.alignment = BoxContainer.ALIGNMENT_END
	col.add_theme_constant_override("separation", 16)
	add_child(col)
	_busca = PanelContainer.new()
	_busca.theme_type_variation = "Chip"
	_busca_txt = Label.new()
	_busca_txt.add_theme_font_override("font", VentaniaTheme.FONTE_FORTE)
	_busca_txt.add_theme_color_override("font_color", VentaniaTheme.AMARELO)
	_busca.add_child(_busca_txt)
	_busca.size_flags_horizontal = Control.SIZE_SHRINK_END
	col.add_child(_busca)
	# cartão do modo (clicável)
	var cartao := Button.new()
	cartao.theme_type_variation = "BotaoFantasma"
	cartao.custom_minimum_size = Vector2(380 if not Settings.is_mobile else 440, 0)
	cartao.pressed.connect(_abrir_modos)
	cartao.focus_entered.connect(func(): Audio.play_ui("foco"))
	var dentro := VBoxContainer.new()
	dentro.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dentro.offset_left = 18
	dentro.offset_top = 10
	dentro.offset_right = -18
	dentro.offset_bottom = -10
	dentro.add_theme_constant_override("separation", 0)
	dentro.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cartao.add_child(dentro)
	var rot := Label.new()
	rot.theme_type_variation = "Rotulo"
	rot.text = "MODO  ·  TOQUE PARA TROCAR"
	dentro.add_child(rot)
	_modo_titulo = Label.new()
	_modo_titulo.theme_type_variation = "Subtitulo"
	dentro.add_child(_modo_titulo)
	_modo_sub = Label.new()
	_modo_sub.theme_type_variation = "Pequeno"
	dentro.add_child(_modo_sub)
	cartao.custom_minimum_size.y = 104 if not Settings.is_mobile else 124
	col.add_child(cartao)
	_jogar = Button.new()
	_jogar.theme_type_variation = "BotaoPrimario"
	_jogar.text = "JOGAR"
	_jogar.custom_minimum_size = Vector2(cartao.custom_minimum_size.x, 92 if not Settings.is_mobile else 108)
	_jogar.pressed.connect(func():
		Audio.play_ui("clique")
		_on_jogar())
	_jogar.focus_entered.connect(func(): Audio.play_ui("foco"))
	col.add_child(_jogar)
	# placas e vagas do grupo
	for i in POS_GRUPO.size():
		var placa := PanelContainer.new()
		placa.theme_type_variation = "Chip"
		placa.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var linha := HBoxContainer.new()
		linha.add_theme_constant_override("separation", 6)
		placa.add_child(linha)
		var coroa := IconeUI.criar("coroa", 18, VentaniaTheme.AMARELO)
		coroa.name = "Coroa"
		linha.add_child(coroa)
		var nome := Label.new()
		nome.name = "Nome"
		nome.add_theme_font_override("font", VentaniaTheme.FONTE_FORTE)
		linha.add_child(nome)
		add_child(placa)
		_placas.append(placa)
		var vaga := Button.new()
		vaga.theme_type_variation = "BotaoFantasma"
		vaga.custom_minimum_size = Vector2(76, 76)
		vaga.tooltip_text = "Convidar amigo"
		var mais := IconeUI.criar("mais", 30)
		mais.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_KEEP_SIZE)
		vaga.add_child(mais)
		vaga.pressed.connect(_abrir_amigos)
		add_child(vaga)
		_vagas.append(vaga)


func _montar_rodape() -> void:
	var chip := PanelContainer.new()
	chip.theme_type_variation = "Chip"
	chip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	chip.grow_vertical = Control.GROW_DIRECTION_BEGIN
	chip.offset_left = 32
	chip.offset_bottom = -30
	add_child(chip)
	var linha := HBoxContainer.new()
	linha.add_theme_constant_override("separation", 10)
	chip.add_child(linha)
	_status_bola = ColorRect.new()
	_status_bola.custom_minimum_size = Vector2(12, 12)
	_status_bola.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	linha.add_child(_status_bola)
	_status_txt = Label.new()
	_status_txt.theme_type_variation = "Pequeno"
	linha.add_child(_status_txt)
	var tentar := Button.new()
	tentar.theme_type_variation = "BotaoFantasma"
	tentar.text = "Tentar de novo"
	tentar.name = "Tentar"
	tentar.add_theme_font_size_override("font_size", 15)
	tentar.pressed.connect(func(): Meta.refresh())
	linha.add_child(tentar)


func _botao_icone(icone: String, texto: String, variacao: String) -> Button:
	# tela estreita ou celular: os botões do topo ficam só com o ícone (texto na dica)
	if not texto.is_empty() and variacao == "BotaoFantasma" and _compacto() and icone in ["loja", "passe", "missoes"]:
		var bi := _botao_icone(icone, "", variacao)
		bi.tooltip_text = texto
		return bi
	var b := Button.new()
	b.theme_type_variation = variacao
	b.text = texto
	b.custom_minimum_size = Vector2(_alvo, _alvo)
	if not texto.is_empty():
		b.text = "      " + texto
	var i := IconeUI.criar(icone, 24, VentaniaTheme.BRANCO if variacao == "BotaoFantasma" else VentaniaTheme.TINTA)
	i.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT if not texto.is_empty() else Control.PRESET_CENTER, Control.PRESET_MODE_KEEP_SIZE)
	if not texto.is_empty():
		i.offset_left = 18
		i.offset_right = 42
	b.add_child(i)
	b.focus_entered.connect(func(): Audio.play_ui("foco"))
	return b


# ---------------------------------------------------------------- estado

func _modo() -> Dictionary:
	for m in MODOS:
		if m["id"] == _modo_id:
			return m
	return MODOS[3]


func _online() -> bool:
	return Meta.state == "online" and Meta.logged_in()


func _atualizar() -> void:
	if not is_inside_tree():
		return
	# servidor e conta
	match Meta.state:
		"online":
			_status_txt.text = "Servidor online" + ("" if Meta.logged_in() else " · entre para jogar online")
			_status_bola.color = VentaniaTheme.VERDE
		"verificando":
			_status_txt.text = "Conectando ao servidor…"
			_status_bola.color = VentaniaTheme.AMARELO
		"incompatible":
			_status_txt.text = "Servidor incompatível: " + Meta.last_error
			_status_bola.color = VentaniaTheme.CORAL
		_:
			_status_txt.text = "Offline · os modos offline funcionam"
			_status_bola.color = VentaniaTheme.CINZA
	_status_txt.text += "   v%s" % Version.GAME
	_status_bola.get_parent().get_node("Tentar").visible = Meta.state in ["offline", "incompatible"]
	if not _conta_btn.text.is_empty():
		_conta_btn.text = "      " + (Meta.account["username"] if Meta.logged_in() else "Entrar")
	_conta_btn.tooltip_text = Meta.account["username"] if Meta.logged_in() else "Entrar"
	var pf := Meta.profile
	_prog_chip.visible = _online() and not pf.is_empty()
	_missoes_btn.visible = _online()
	_passe_btn.visible = _online()
	_loja_btn.visible = _online()
	if not pf.is_empty():
		_prog_nivel.text = "NV %d" % int(pf["level"])
		_prog_barra.max_value = maxf(1.0, float(pf["xp_next"]))
		_prog_barra.value = float(pf["xp_in_level"])
		_prog_faiscas.text = _milhar(int(pf["sparks"]))
		_prog_chip.tooltip_text = "%d / %d XP para o nível %d" % [pf["xp_in_level"], pf["xp_next"], int(pf["level"]) + 1]
	_amigos_btn.disabled = not _online()
	var pedidos: int = Meta.friends.get("incoming", []).size()
	_amigos_badge.text = str(pedidos)
	_amigos_badge.visible = pedidos > 0 and _online()
	# modo
	var m := _modo()
	if m["online"] and not _online():
		_modo_id = "br_local"
		m = _modo()
	_modo_titulo.text = m["titulo"]
	_modo_sub.text = m["sub"]
	# grupo
	var membros: Array = Meta.party.get("members", []) if _online() else []
	var eu := int(Meta.account.get("id", 0))
	var ordem: Array = membros.filter(func(x): return int(x["id"]) == eu) + membros.filter(func(x): return int(x["id"]) != eu)
	for i in POS_GRUPO.size():
		var tem := i < ordem.size() or i == 0
		_bonecos[i].visible = tem
		_placas[i].visible = tem
		var nome := "Você" if ordem.is_empty() else str(ordem[i]["username"]) if i < ordem.size() else ""
		(_placas[i].find_child("Nome", true, false) as Label).text = nome
		_placas[i].find_child("Coroa", true, false).visible = i < ordem.size() and bool(ordem[i].get("leader", false)) and ordem.size() > 1
		_vagas[i].visible = not tem and _online() and i > 0 and i < 4
		if tem:
			var traje := ""
			if i < ordem.size():
				traje = str(ordem[i].get("traje", ""))
			elif i == 0 and Meta.logged_in():
				traje = str(Meta.profile.get("equipped", {}).get("traje", ""))
			_vestir(i, traje)
	# botão jogar e busca
	var estado: String = Meta.party.get("state", "lobby") if _online() else "lobby"
	_busca.visible = estado == "fila"
	_jogar.disabled = false
	_jogar.theme_type_variation = "BotaoPrimario"
	if estado == "fila":
		if _busca_ini == 0.0:
			_busca_ini = Time.get_ticks_msec() / 1000.0 - float(Meta.party.get("queue_s", 0))
		_jogar.text = "CANCELAR"
		_jogar.theme_type_variation = "Button"
		_jogar.disabled = not Meta.is_leader()
	else:
		_busca_ini = 0.0
		_jogar.text = "JOGAR"
		if m["online"] and not Meta.is_leader() and membros.size() > 1:
			_jogar.text = "O LÍDER COMEÇA"
			_jogar.disabled = true


func _compacto() -> bool:
	return Settings.is_mobile or get_viewport_rect().size.x < 1200


static func _milhar(n: int) -> String:
	var t := str(absi(n))
	var out := ""
	while t.length() > 3:
		out = "." + t.right(3) + out
		t = t.left(t.length() - 3)
	return ("-" if n < 0 else "") + t + out


static func _relogio(s: float) -> String:
	return "%d:%02d" % [int(s) / 60, int(s) % 60]


# ---------------------------------------------------------------- ações

func _on_jogar() -> void:
	var m := _modo()
	if Meta.party.get("state", "") == "fila" and _online():
		Meta.cancel_queue()
		return
	match m["id"]:
		"br_local", "local":
			SceneManager.go("game", {"modo": m["id"]})
		"direto":
			_entrar_servidor()
		"privada":
			_abrir_privada()
		_:
			if not _online():
				_abrir_login()
				return
			if Meta.party.get("mode", "") != m["meta"]:
				var r := await Meta.set_mode(m["meta"])
				if not r["ok"]:
					return
			Meta.queue()


func _on_partida(m: Dictionary) -> void:
	_aviso("Partida encontrada! Entrando…", "", Callable(), 4.0, "", Callable(), "partida")
	SceneManager.go("game", {"modo": "remoto", "host": m["host"], "porta": int(m["port"]),
			"ticket": m["ticket"], "private_code": m.get("private_code", ""),
			"dono_privada": m.get("private_code", "") != "" and Meta.is_leader()})


## Conecta no servidor de partida configurado (Configurações → Rede).
func _entrar_servidor() -> void:
	var alvo: String = Settings.get_value("network", "game_server")
	var partes := alvo.rsplit(":", true, 1)
	var host := partes[0].strip_edges()
	var porta := Protocol.DEFAULT_PORT
	if partes.size() == 2 and partes[1].is_valid_int():
		porta = int(partes[1])
	if host.is_empty():
		_aviso("Configure o endereço em Configurações → Rede.")
		return
	SceneManager.go("game", {"modo": "remoto", "host": host, "porta": porta})


func _on_conta() -> void:
	if not Meta.logged_in():
		_abrir_login()
		return
	var pm := PopupMenu.new()
	pm.add_item("Sair da conta", 0)
	pm.id_pressed.connect(func(_id): Meta.logout())
	add_child(pm)
	pm.popup(Rect2i(Vector2i(_conta_btn.global_position + Vector2(0, _conta_btn.size.y + 6)), Vector2i(220, 0)))


func _menu_opcoes(ancora: Control) -> void:
	var pm := PopupMenu.new()
	pm.add_item("Configurações", 0)
	pm.add_item("Vitrine e teste de desempenho", 1)
	if not Settings.is_mobile:
		pm.add_separator()
		pm.add_item("Sair do jogo", 2)
	pm.id_pressed.connect(_on_opcao)
	add_child(pm)
	pm.popup(Rect2i(Vector2i(ancora.global_position + Vector2(ancora.size.x - 320, ancora.size.y + 6)), Vector2i(320, 0)))


func _on_opcao(id: int) -> void:
	Audio.play_ui("clique")
	match id:
		0:
			SceneManager.go("settings")
		1:
			SceneManager.go("diagnostics")
		2:
			get_tree().quit()


# ---------------------------------------------------------------- modais

func _modal(titulo: String, largura := 560.0) -> VBoxContainer:
	_fechar_modal()
	var escuro := ColorRect.new()
	escuro.color = Color(0, 0, 0, 0.55)
	escuro.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(escuro)
	_sobreposicao = escuro
	var cartao := PanelContainer.new()
	cartao.theme_type_variation = "Cartao"
	cartao.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	cartao.grow_horizontal = Control.GROW_DIRECTION_BOTH
	cartao.grow_vertical = Control.GROW_DIRECTION_BOTH
	cartao.custom_minimum_size.x = minf(largura, size.x - 32)
	escuro.add_child(cartao)
	# entra com um "pop" curto (escala + transparência)
	escuro.modulate.a = 0.0
	cartao.scale = Vector2(0.94, 0.94)
	(func():
		await get_tree().process_frame
		if not is_instance_valid(cartao):
			return
		cartao.pivot_offset = cartao.size / 2.0
		var tw := cartao.create_tween().set_parallel()
		tw.tween_property(escuro, "modulate:a", 1.0, 0.14)
		tw.tween_property(cartao, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)).call()
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	cartao.add_child(col)
	var cab := HBoxContainer.new()
	col.add_child(cab)
	var t := Label.new()
	t.theme_type_variation = "Subtitulo"
	t.text = titulo
	t.add_theme_color_override("font_color", VentaniaTheme.AMARELO)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cab.add_child(t)
	var x := _botao_icone("fechar", "", "BotaoFantasma")
	x.pressed.connect(_fechar_modal)
	cab.add_child(x)
	return col


func _fechar_modal() -> void:
	if _sobreposicao:
		_sobreposicao.queue_free()
		_sobreposicao = null
		_jogar.grab_focus.call_deferred()


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_cancel"):
		if _sobreposicao:
			_fechar_modal()
			accept_event()
		elif _gaveta and _gaveta.visible:
			_gaveta.visible = false
			accept_event()


func _abrir_modos() -> void:
	var col := _modal("Escolha o modo", 760)
	var grade := GridContainer.new()
	grade.columns = 2
	grade.add_theme_constant_override("h_separation", 14)
	grade.add_theme_constant_override("v_separation", 14)
	col.add_child(grade)
	var primeiro: Button = null
	for m in MODOS:
		var b := Button.new()
		b.theme_type_variation = "BotaoPrimario" if m["id"] == _modo_id else "Button"
		b.custom_minimum_size = Vector2(340, 96)
		b.add_theme_font_size_override("font_size", 22)
		b.text = m["titulo"]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		var sub := Label.new()
		sub.text = m["sub"]
		sub.add_theme_color_override("font_color", Color(VentaniaTheme.TINTA, 0.7))
		sub.add_theme_font_size_override("font_size", 14)
		sub.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		sub.offset_left = 26
		sub.offset_bottom = -12
		sub.offset_top = -32
		sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(sub)
		var bloqueado: bool = m["online"] and not _online()
		if bloqueado:
			b.disabled = true
			sub.text = "Entre na sua conta (servidor online)"
			sub.add_theme_color_override("font_color", Color(VentaniaTheme.BRANCO, 0.5))
		var id: String = m["id"]
		b.pressed.connect(func():
			Audio.play_ui("clique")
			_modo_id = id
			_fechar_modal()
			_atualizar())
		grade.add_child(b)
		if primeiro == null or m["id"] == _modo_id:
			primeiro = b if not b.disabled else primeiro
	if not _online():
		var entrar := Button.new()
		entrar.text = "Entrar para jogar online"
		entrar.pressed.connect(_abrir_login)
		col.add_child(entrar)
	if primeiro:
		primeiro.grab_focus.call_deferred()


func _abrir_login(criar := false) -> void:
	if Meta.state != "online":
		_servidor_offline()
		return
	var col := _modal("Criar conta" if criar else "Entrar", 480)
	var sub := Label.new()
	sub.theme_type_variation = "Pequeno"
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.text = "Só um nome e uma senha. Sem e-mail, sem dados pessoais." if criar else "Use o nome e a senha da sua conta Ventania."
	col.add_child(sub)
	var nome := LineEdit.new()
	nome.placeholder_text = "Nome (3 a 16 letras, números ou _)"
	nome.max_length = 16
	nome.custom_minimum_size.y = _alvo
	col.add_child(nome)
	var senha := LineEdit.new()
	senha.placeholder_text = "Senha (6 ou mais caracteres)"
	senha.secret = true
	senha.custom_minimum_size.y = _alvo
	col.add_child(senha)
	var erro := Label.new()
	erro.add_theme_color_override("font_color", VentaniaTheme.CORAL)
	erro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	erro.visible = false
	col.add_child(erro)
	var ok := Button.new()
	ok.theme_type_variation = "BotaoPrimario"
	ok.add_theme_font_size_override("font_size", 26)
	ok.text = "CRIAR CONTA" if criar else "ENTRAR"
	ok.custom_minimum_size.y = _alvo + 12
	col.add_child(ok)
	var trocar := Button.new()
	trocar.theme_type_variation = "BotaoFantasma"
	trocar.text = "Já tenho conta: entrar" if criar else "Não tenho conta: criar uma"
	trocar.pressed.connect(func(): _abrir_login(not criar))
	col.add_child(trocar)
	var enviar := func():
		ok.disabled = true
		erro.visible = false
		var r: Dictionary
		if criar:
			r = await Meta.register(nome.text, senha.text)
		else:
			r = await Meta.login(nome.text, senha.text)
		if not is_instance_valid(ok):
			return
		ok.disabled = false
		if r["ok"]:
			_fechar_modal()
			_modo_id = "br_online"
			_atualizar()
			_aviso("Olá, %s!" % Meta.account.get("username", ""))
		else:
			erro.text = r["error"]
			erro.visible = true
	ok.pressed.connect(enviar)
	senha.text_submitted.connect(func(_t): enviar.call())
	nome.text_submitted.connect(func(_t): senha.grab_focus())
	nome.grab_focus.call_deferred()


## Explica o que fazer quando o meta-servidor não responde (em vez de só um aviso).
func _servidor_offline() -> void:
	var col := _modal("Servidor offline", 540)
	var t := Label.new()
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.text = "Não foi possível falar com o servidor do Ventania em:\n%s\n\n%s\n\nSem servidor, o Battle Royale solo, o campo de treino e o servidor por endereço continuam funcionando." % [
			Meta.base_url, Meta.last_error if not Meta.last_error.is_empty() else "Confira se quem hospeda está com o servidor ligado e se o endereço está certo."]
	col.add_child(t)
	var linha := HBoxContainer.new()
	col.add_child(linha)
	var tentar := Button.new()
	tentar.theme_type_variation = "BotaoPrimario"
	tentar.add_theme_font_size_override("font_size", 20)
	tentar.text = "TENTAR DE NOVO"
	tentar.pressed.connect(func():
		_fechar_modal()
		await Meta.refresh()
		if Meta.state == "online":
			_abrir_login()
		else:
			_aviso("Ainda offline: %s" % Meta.last_error))
	linha.add_child(tentar)
	var cfg := Button.new()
	cfg.text = "Mudar endereço"
	cfg.pressed.connect(func(): SceneManager.go("settings"))
	linha.add_child(cfg)
	tentar.grab_focus.call_deferred()


func _abrir_privada() -> void:
	if not _online():
		_abrir_login()
		return
	var col := _modal("Sala privada", 520)
	var txt := Label.new()
	txt.theme_type_variation = "Pequeno"
	txt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	txt.text = "Crie uma sala e passe o código para os amigos. A partida começa quando você mandar; os bots completam as vagas."
	col.add_child(txt)
	var criar := Button.new()
	criar.theme_type_variation = "BotaoPrimario"
	criar.add_theme_font_size_override("font_size", 24)
	criar.text = "CRIAR SALA"
	criar.custom_minimum_size.y = _alvo + 8
	criar.disabled = not Meta.is_leader()
	criar.pressed.connect(func():
		criar.disabled = true
		var r := await Meta.private_create()
		if is_instance_valid(criar):
			criar.disabled = false
		if r["ok"]:
			_fechar_modal())
	col.add_child(criar)
	var rot := Label.new()
	rot.theme_type_variation = "Rotulo"
	rot.text = "OU ENTRE COM UM CÓDIGO"
	col.add_child(rot)
	var linha := HBoxContainer.new()
	col.add_child(linha)
	var codigo := LineEdit.new()
	codigo.placeholder_text = "ABCDE"
	codigo.max_length = 5
	codigo.custom_minimum_size = Vector2(0, _alvo)
	codigo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	codigo.add_theme_font_override("font", VentaniaTheme.FONTE_FORTE)
	codigo.add_theme_font_size_override("font_size", 28)
	linha.add_child(codigo)
	var entrar := Button.new()
	entrar.text = "ENTRAR"
	entrar.custom_minimum_size.y = _alvo
	var ir := func():
		var r := await Meta.private_join(codigo.text)
		if r["ok"]:
			_fechar_modal()
	entrar.pressed.connect(ir)
	codigo.text_submitted.connect(func(_t): ir.call())
	linha.add_child(entrar)
	if not Meta.is_leader():
		var aviso := Label.new()
		aviso.theme_type_variation = "Pequeno"
		aviso.text = "Só o líder do grupo cria ou entra em salas."
		col.add_child(aviso)
	(criar if not criar.disabled else codigo).grab_focus.call_deferred()


# ---------------------------------------------------------------- progressão (Etapa 9)

func _montar_progresso(topo: HBoxContainer) -> void:
	_prog_chip = Button.new()
	_prog_chip.theme_type_variation = "BotaoFantasma"
	_prog_chip.custom_minimum_size = Vector2(262, _alvo)
	_prog_chip.pressed.connect(_abrir_perfil)
	_prog_chip.focus_entered.connect(func(): Audio.play_ui("foco"))
	var h := HBoxContainer.new()
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 12
	h.offset_right = -14
	h.add_theme_constant_override("separation", 10)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prog_chip.add_child(h)
	_prog_nivel = Label.new()
	_prog_nivel.add_theme_font_override("font", VentaniaTheme.FONTE_FORTE)
	_prog_nivel.add_theme_color_override("font_color", VentaniaTheme.TINTA)
	var sb := VentaniaTheme._caixa(VentaniaTheme.AMARELO, 10, VentaniaTheme.TINTA, 2, 0)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	_prog_nivel.add_theme_stylebox_override("normal", sb)
	_prog_nivel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(_prog_nivel)
	_prog_barra = ProgressBar.new()
	_prog_barra.show_percentage = false
	_prog_barra.custom_minimum_size = Vector2(70, 12)
	_prog_barra.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_prog_barra.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_prog_barra.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(_prog_barra)
	var fa := IconeUI.criar("faisca", 22, VentaniaTheme.AMARELO)
	fa.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(fa)
	_prog_faiscas = Label.new()
	_prog_faiscas.add_theme_font_override("font", VentaniaTheme.FONTE_FORTE)
	h.add_child(_prog_faiscas)
	topo.add_child(_prog_chip)


func _abrir_missoes() -> void:
	var col := _modal("Missões", 720)
	var carregando := Label.new()
	carregando.theme_type_variation = "Pequeno"
	carregando.text = "Carregando…"
	col.add_child(carregando)
	var r := await Meta.get_quests()
	if not is_instance_valid(carregando):
		return
	carregando.queue_free()
	if not r["ok"]:
		_aviso(r["error"])
		return
	for grupo in [["diaria", "DIÁRIAS"], ["semanal", "SEMANAIS"]]:
		var g: Dictionary = r["data"][grupo[0]]
		var cab := Label.new()
		cab.theme_type_variation = "Rotulo"
		var h := int(g["ends_in_s"]) / 3600
		cab.text = "%s  ·  TROCAM EM %s" % [grupo[1], ("%d h" % h) if h < 48 else ("%d dias" % (h / 24))]
		col.add_child(cab)
		for q: Dictionary in g["quests"]:
			col.add_child(_linha_missao(q))


func _linha_missao(q: Dictionary) -> Control:
	var p := PanelContainer.new()
	p.theme_type_variation = "Chip"
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	p.add_child(h)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	var t := Label.new()
	t.text = q["titulo"]
	t.add_theme_font_override("font", VentaniaTheme.FONTE_FORTE)
	if q["concluida"]:
		t.add_theme_color_override("font_color", VentaniaTheme.VERDE)
	v.add_child(t)
	var barra := ProgressBar.new()
	barra.show_percentage = false
	barra.max_value = float(q["meta"])
	barra.value = float(q["progresso"])
	barra.custom_minimum_size = Vector2(0, 10)
	v.add_child(barra)
	var n := Label.new()
	n.theme_type_variation = "Pequeno"
	n.text = "Concluída!" if q["concluida"] else "%s / %s" % [_milhar(int(q["progresso"])), _milhar(int(q["meta"]))]
	h.add_child(n)
	var rec := Label.new()
	rec.add_theme_font_override("font", VentaniaTheme.FONTE_FORTE)
	rec.add_theme_color_override("font_color", VentaniaTheme.AMARELO)
	rec.text = "+%d XP  ·  +%d Faíscas" % [q["xp"], q["faiscas"]]
	h.add_child(rec)
	return p


# ---------------------------------------------------------------- loja (Etapa 11)

func _abrir_loja() -> void:
	var col := _modal("Loja", 1100)
	var carregando := Label.new()
	carregando.theme_type_variation = "Pequeno"
	carregando.text = "Carregando…"
	col.add_child(carregando)
	var r := await Meta.get_shop()
	if not is_instance_valid(carregando):
		return
	carregando.queue_free()
	if not r["ok"]:
		_aviso(r["error"])
		return
	var saldo := HBoxContainer.new()
	saldo.add_theme_constant_override("separation", 8)
	col.add_child(saldo)
	var fa := IconeUI.criar("faisca", 26, VentaniaTheme.AMARELO)
	fa.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	saldo.add_child(fa)
	var sl := Label.new()
	sl.theme_type_variation = "Subtitulo"
	sl.text = "%s Faíscas" % _milhar(int(r["data"]["faiscas"]))
	saldo.add_child(sl)
	var dica := Label.new()
	dica.theme_type_variation = "Pequeno"
	dica.text = "   Faíscas vêm do passe, das missões e dos níveis. Sem dinheiro real."
	dica.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	saldo.add_child(dica)
	for sec: Dictionary in r["data"]["secoes"]:
		var cab := Label.new()
		cab.theme_type_variation = "Rotulo"
		var h := int(sec["troca_em_s"]) / 3600
		cab.text = "%s  ·  TROCA EM %s" % [str(sec["nome"]).to_upper(), ("%d h %02d min" % [h, (int(sec["troca_em_s"]) % 3600) / 60]) if h < 48 else ("%d dias" % (h / 24))]
		col.add_child(cab)
		var linha := HBoxContainer.new()
		linha.add_theme_constant_override("separation", 12)
		col.add_child(linha)
		for it: Dictionary in sec["itens"]:
			linha.add_child(_cartao_loja(it, sec["id"] == "destaques"))


func _cartao_loja(it: Dictionary, destaque: bool) -> Control:
	var cor: Color = CORES_RARIDADE.get(it["raridade"], VentaniaTheme.CINZA)
	var b := Button.new()
	b.custom_minimum_size = Vector2(250 if destaque else 190, 210 if destaque else 190)
	var sb := VentaniaTheme._caixa(cor.darkened(0.5), 18, VentaniaTheme.TINTA, 3, 5)
	b.add_theme_stylebox_override("normal", sb)
	var sb_h := VentaniaTheme._caixa(cor.darkened(0.35), 18, VentaniaTheme.AMARELO, 3, 6)
	b.add_theme_stylebox_override("hover", sb_h)
	b.add_theme_stylebox_override("focus", sb_h)
	b.add_theme_stylebox_override("pressed", sb)
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 10
	v.offset_right = -10
	v.offset_top = 10
	v.offset_bottom = -10
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	var icone := IconeUI.criar("pessoa", 64 if destaque else 52, cor.lightened(0.25))
	icone.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(icone)
	var nome := Label.new()
	nome.text = str(it["nome"])
	nome.add_theme_font_override("font", VentaniaTheme.FONTE_FORTE)
	nome.add_theme_font_size_override("font_size", 20 if destaque else 17)
	nome.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nome.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(nome)
	var rar := Label.new()
	rar.text = "TRAJE · %s" % _raridade(it["raridade"])
	rar.add_theme_font_size_override("font_size", 12)
	rar.add_theme_color_override("font_color", cor.lightened(0.3))
	rar.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(rar)
	var preco := Label.new()
	preco.add_theme_font_override("font", VentaniaTheme.FONTE_FORTE)
	preco.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if it["tem"]:
		preco.text = "JÁ É SEU"
		preco.add_theme_color_override("font_color", VentaniaTheme.VERDE)
	else:
		preco.text = "%s Faíscas" % _milhar(int(it["preco"]))
		preco.add_theme_color_override("font_color", VentaniaTheme.AMARELO)
	v.add_child(preco)
	b.pressed.connect(func():
		Audio.play_ui("clique")
		_previa_item(it))
	return b


static func _raridade(r: String) -> String:
	return {"comum": "COMUM", "incomum": "INCOMUM", "raro": "RARO", "epico": "ÉPICO", "lendario": "LENDÁRIO", "mitico": "MÍTICO"}.get(r, r.to_upper())


## Pré-visualização: o traje em 3D, girando, com descrição e compra.
func _previa_item(it: Dictionary) -> void:
	var col := _modal(str(it["nome"]), 760)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 18)
	col.add_child(h)
	var vpc := SubViewportContainer.new()
	vpc.custom_minimum_size = Vector2(300, 360)
	vpc.stretch = true
	h.add_child(vpc)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_2X
	vpc.add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("c8d2ff")
	env.ambient_light_energy = 0.55
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var sol := DirectionalLight3D.new()
	sol.rotation_degrees = Vector3(-35, -30, 0)
	vp.add_child(sol)
	var giro := Node3D.new()
	vp.add_child(giro)
	var m := (load(Cosmeticos.outfit_scene(it["id"])) as PackedScene).instantiate() as Node3D
	giro.add_child(m)
	var aps := m.find_children("*", "AnimationPlayer", true, false)
	if not aps.is_empty():
		(aps[0] as AnimationPlayer).play("idle")
	var cam := Camera3D.new()
	cam.fov = 30
	vp.add_child(cam)
	cam.look_at_from_position(Vector3(0, 1.2, 4.6), Vector3(0, 0.95, 0))
	var tw := giro.create_tween().set_loops()
	tw.tween_property(giro, "rotation:y", TAU, 6.0).from(0.0)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(info)
	var rar := Label.new()
	rar.theme_type_variation = "Rotulo"
	rar.text = "TRAJE · %s" % _raridade(it["raridade"])
	rar.add_theme_color_override("font_color", CORES_RARIDADE.get(it["raridade"], VentaniaTheme.CINZA).lightened(0.3))
	info.add_child(rar)
	var desc := Label.new()
	desc.text = str(it.get("descricao", ""))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(desc)
	var nota := Label.new()
	nota.theme_type_variation = "Pequeno"
	nota.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nota.text = "Só aparência: o mesmo tamanho e a mesma hitbox de qualquer traje."
	info.add_child(nota)
	var erro := Label.new()
	erro.add_theme_color_override("font_color", VentaniaTheme.CORAL)
	erro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	erro.visible = false
	info.add_child(erro)
	var comprar := Button.new()
	comprar.theme_type_variation = "BotaoPrimario"
	comprar.add_theme_font_size_override("font_size", 24)
	comprar.custom_minimum_size.y = _alvo + 10
	info.add_child(comprar)
	if it["tem"]:
		comprar.text = "EQUIPAR"
		comprar.pressed.connect(func():
			await Meta.equip("traje", it["id"])
			_fechar_modal()
			_aviso("%s equipado!" % it["nome"]))
	else:
		comprar.text = "COMPRAR · %s" % _milhar(int(it["preco"]))
		var confirmando := [false]
		var chave := "%d-%d-%s" % [Time.get_unix_time_from_system() * 1000, randi(), it["id"]]
		comprar.pressed.connect(func():
			if not confirmando[0]:
				confirmando[0] = true
				comprar.text = "CONFIRMAR: %s FAÍSCAS" % _milhar(int(it["preco"]))
				return
			comprar.disabled = true
			erro.visible = false
			var r := await Meta.buy(it["id"], int(it["preco"]), chave)
			if not is_instance_valid(comprar):
				return
			if r["ok"]:
				Audio.play_ui("compra")
				comprar.disabled = false
				comprar.text = "EQUIPAR AGORA"
				it["tem"] = true
				for c in comprar.pressed.get_connections():
					comprar.pressed.disconnect(c["callable"])
				comprar.pressed.connect(func():
					await Meta.equip("traje", it["id"])
					_fechar_modal()
					_aviso("%s equipado!" % it["nome"]))
				_aviso("Comprado: %s!" % it["nome"])
			else:
				comprar.disabled = false
				confirmando[0] = false
				comprar.text = "COMPRAR · %s" % _milhar(int(it["preco"]))
				erro.text = r["error"]
				erro.visible = true)
	comprar.grab_focus.call_deferred()


# ---------------------------------------------------------------- passe (Etapa 10)

func _abrir_passe() -> void:
	var col := _modal("Passe de batalha", 1100)
	var carregando := Label.new()
	carregando.theme_type_variation = "Pequeno"
	carregando.text = "Carregando…"
	col.add_child(carregando)
	var r := await Meta.get_season()
	if not is_instance_valid(carregando):
		return
	carregando.queue_free()
	if not r["ok"]:
		_aviso(r["error"])
		return
	var pa: Dictionary = r["data"]
	if not pa.get("ativa", false):
		var nada := Label.new()
		nada.text = "Nenhuma temporada ativa agora. Os itens que você ganhou continuam seus."
		col.add_child(nada)
		return
	# cabeçalho: temporada, nível atual e barra
	var cab := HBoxContainer.new()
	cab.add_theme_constant_override("separation", 18)
	col.add_child(cab)
	var nivel := Label.new()
	nivel.text = str(int(pa["nivel"]))
	nivel.theme_type_variation = "Destaque"
	nivel.add_theme_font_size_override("font_size", 54)
	nivel.add_theme_color_override("font_color", VentaniaTheme.AMARELO)
	cab.add_child(nivel)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 4)
	cab.add_child(info)
	var nome := Label.new()
	nome.theme_type_variation = "Subtitulo"
	nome.text = str(pa["nome"])
	info.add_child(nome)
	var barra := ProgressBar.new()
	barra.show_percentage = false
	barra.custom_minimum_size = Vector2(0, 16)
	barra.max_value = float(pa["xp_por_nivel"])
	barra.value = float(pa["xp_no_nivel"])
	info.add_child(barra)
	var sub := Label.new()
	sub.theme_type_variation = "Pequeno"
	var dias := int(pa["termina_em_s"]) / 86400
	sub.text = ("NÍVEL MÁXIMO!" if int(pa["nivel"]) >= int(pa["maximo"]) else "%s / %s XP para o nível %d" % [
			_milhar(int(pa["xp_no_nivel"])), _milhar(int(pa["xp_por_nivel"])), int(pa["nivel"]) + 1]) + \
			"  ·  100%% gratuito  ·  termina em %s" % ("%d dias" % dias if dias >= 1 else "menos de 1 dia")
	info.add_child(sub)
	# trilha de níveis (rolagem horizontal), começando perto do nível atual
	var rol := ScrollContainer.new()
	rol.custom_minimum_size = Vector2(0, 200)
	rol.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(rol)
	var trilha := HBoxContainer.new()
	trilha.add_theme_constant_override("separation", 10)
	rol.add_child(trilha)
	var atual: Control = null
	for n: Dictionary in pa["niveis"]:
		var cartao := _cartao_nivel(n, int(pa["nivel"]))
		trilha.add_child(cartao)
		if int(n["nivel"]) == int(pa["nivel"]):
			atual = cartao
	if atual:
		var alvo := atual
		(func():
			await get_tree().process_frame
			if is_instance_valid(rol) and is_instance_valid(alvo):
				rol.scroll_horizontal = maxi(0, int(alvo.position.x - 260))).call()
	# desafios da temporada
	var rot := Label.new()
	rot.theme_type_variation = "Rotulo"
	rot.text = "DESAFIOS DA TEMPORADA"
	col.add_child(rot)
	var lista := ScrollContainer.new()
	lista.custom_minimum_size = Vector2(0, 210)
	lista.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(lista)
	var grade := VBoxContainer.new()
	grade.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grade.add_theme_constant_override("separation", 8)
	lista.add_child(grade)
	for q: Dictionary in pa["desafios"]:
		var l := _linha_missao(q)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grade.add_child(l)


## Cartão de um nível do passe: número, recompensa (Faíscas ou item com a cor da raridade) e estado.
func _cartao_nivel(n: Dictionary, nivel_atual: int) -> Control:
	var obtido: bool = n["obtido"]
	var e_atual: bool = int(n["nivel"]) == nivel_atual
	var cor: Color = CORES_RARIDADE.get(n.get("raridade", ""), VentaniaTheme.AMARELO) if n["item"] != "" else VentaniaTheme.NOITE_CLARA
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(128, 186)
	var sb := VentaniaTheme._caixa(cor.darkened(0.45) if n["item"] != "" else Color(VentaniaTheme.NOITE_CLARA, 0.9), 16,
			VentaniaTheme.AMARELO if e_atual else VentaniaTheme.TINTA, 4 if e_atual else 3, 4)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	p.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	p.add_child(v)
	var num := Label.new()
	num.text = "NÍVEL %d" % int(n["nivel"])
	num.theme_type_variation = "Rotulo"
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(num)
	if n["item"] != "":
		var icone := IconeUI.criar("pessoa", 54, cor.lightened(0.2))
		icone.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(icone)
		var nome := Label.new()
		nome.text = str(n["nome"])
		nome.add_theme_font_override("font", VentaniaTheme.FONTE_FORTE)
		nome.add_theme_font_size_override("font_size", 15)
		nome.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nome.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(nome)
		var rar := Label.new()
		rar.text = "TRAJE · %s" % str(n["raridade"]).to_upper().replace("EPICO", "ÉPICO").replace("LENDARIO", "LENDÁRIO")
		rar.add_theme_font_size_override("font_size", 12)
		rar.add_theme_color_override("font_color", cor.lightened(0.3))
		rar.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(rar)
	else:
		var icone := IconeUI.criar("faisca", 46, VentaniaTheme.AMARELO)
		icone.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(icone)
		var q := Label.new()
		q.text = "%d Faíscas" % int(n["faiscas"])
		q.add_theme_font_override("font", VentaniaTheme.FONTE_FORTE)
		q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(q)
	var estado := Label.new()
	estado.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	estado.add_theme_font_size_override("font_size", 13)
	estado.text = "OBTIDO" if obtido else ("ATUAL" if e_atual else "")
	estado.add_theme_color_override("font_color", VentaniaTheme.VERDE if obtido else VentaniaTheme.AMARELO)
	v.add_child(estado)
	if not obtido:
		p.modulate = Color(1, 1, 1, 0.75)
	return p


func _abrir_perfil() -> void:
	var pf := Meta.profile
	if pf.is_empty():
		return
	var col := _modal("%s  ·  Nível %d" % [Meta.account.get("username", ""), int(pf["level"])], 760)
	var resumo := Label.new()
	resumo.theme_type_variation = "Pequeno"
	var plural := func(n: int, um: String, varios: String) -> String: return "%d %s" % [n, um if n == 1 else varios]
	resumo.text = "%s / %s XP para o nível %d  ·  %s  ·  %s  ·  %s  ·  %s Faíscas" % [
			_milhar(int(pf["xp_in_level"])), _milhar(int(pf["xp_next"])), int(pf["level"]) + 1,
			plural.call(int(pf["matches"]), "partida", "partidas"), plural.call(int(pf["wins"]), "vitória", "vitórias"),
			plural.call(int(pf["kills"]), "eliminação", "eliminações"), _milhar(int(pf["sparks"]))]
	resumo.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(resumo)
	var abas := TabContainer.new()
	abas.custom_minimum_size = Vector2(0, 380)
	col.add_child(abas)
	# coleção (inventário persistente) + equipar
	var colecao := _rolagem(abas, "Coleção")
	var por_cat := {}
	for u: Dictionary in pf["unlocks"]:
		por_cat.get_or_add(u.get("categoria", "outros"), []).append(u)
	var nomes_cat := {"traje": "TRAJES", "picareta": "FERRAMENTAS DE COLETA", "planador": "PLANADORES", "emote": "EMOTES", "mochila": "MOCHILAS", "acessorio": "ACESSÓRIOS"}
	for cat in nomes_cat:
		if not por_cat.has(cat):
			continue
		var rot := Label.new()
		rot.theme_type_variation = "Rotulo"
		rot.text = nomes_cat[cat]
		colecao.add_child(rot)
		for u: Dictionary in por_cat[cat]:
			var l := HBoxContainer.new()
			var info := Label.new()
			info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			info.text = "%s  ·  %s" % [u.get("nome", u["item"]), str(u.get("raridade", "")).capitalize()]
			l.add_child(info)
			var equipado: bool = pf["equipped"].get(cat, "") == u["item"]
			var b := Button.new()
			b.add_theme_font_size_override("font_size", 15)
			b.text = "Equipado" if equipado else "Equipar"
			b.disabled = equipado
			var slot: String = cat
			var item: String = u["item"]
			b.pressed.connect(func():
				await Meta.equip(slot, item)
				_fechar_modal()
				_abrir_perfil())
			l.add_child(b)
			colecao.add_child(l)
	var aviso := Label.new()
	aviso.theme_type_variation = "Pequeno"
	aviso.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	aviso.text = "Novos trajes, ferramentas, planadores e emotes chegam com o passe e a loja."
	colecao.add_child(aviso)
	# histórico de desbloqueios
	var hist := _rolagem(abas, "Desbloqueios")
	var lista: Array = pf["unlocks"].duplicate()
	lista.reverse()
	for u: Dictionary in lista:
		var origem := _origem(str(u["source"]))
		_linha_texto(hist, "%s  ·  %s" % [u.get("nome", u["item"]), origem], Time.get_datetime_string_from_unix_time(int(u["at"])).replace("T", " ").left(16))
	# Faíscas (ledger)
	var faiscas := _rolagem(abas, "Faíscas")
	var partidas := _rolagem(abas, "Partidas")
	var r := await Meta.get_ledger()
	if r["ok"] and is_instance_valid(faiscas):
		if r["data"]["entries"].is_empty():
			_linha_texto(faiscas, "Nenhuma movimentação ainda. Suba de nível e conclua missões!", "")
		for e: Dictionary in r["data"]["entries"]:
			_linha_texto(faiscas, "%s%d  ·  %s" % ["+" if int(e["delta"]) > 0 else "", int(e["delta"]), e["reason"]], "saldo %s" % _milhar(int(e["balance_after"])))
	var hp := await Meta.get_history()
	if hp["ok"] and is_instance_valid(partidas):
		if hp["data"]["matches"].is_empty():
			_linha_texto(partidas, "Nenhuma partida de Battle Royale com conta ainda.", "")
		for m: Dictionary in hp["data"]["matches"]:
			_linha_texto(partidas, "#%d de %d  ·  %d eliminações  ·  %d:%02d vivo" % [int(m["placement"]), int(m["total"]), int(m["kills"]),
					int(m["time_alive_s"]) / 60, int(m["time_alive_s"]) % 60], "+%d XP" % int(m["xp"]))


static func _origem(src: String) -> String:
	if src == "inicial":
		return "item inicial"
	if src == "presente":
		return "presente"
	if src == "loja":
		return "comprado na loja"
	if src.begins_with("nivel:"):
		return "nível %s da conta" % src.trim_prefix("nivel:")
	if src.begins_with("passe:"):
		var p := src.split(":")
		return "passe (%s), nível %s" % [p[1].to_upper(), p[2] if p.size() > 2 else "?"]
	return src


func _rolagem(abas: TabContainer, titulo: String) -> VBoxContainer:
	var s := ScrollContainer.new()
	s.name = titulo
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	abas.add_child(s)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 8)
	s.add_child(v)
	return v


func _linha_texto(pai: Control, texto: String, direita: String) -> void:
	var l := HBoxContainer.new()
	var a := Label.new()
	a.text = texto
	a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	a.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_child(a)
	if not direita.is_empty():
		var b := Label.new()
		b.theme_type_variation = "Pequeno"
		b.text = direita
		l.add_child(b)
	pai.add_child(l)


# ---------------------------------------------------------------- amigos

func _abrir_amigos() -> void:
	if not _online():
		_abrir_login()
		return
	if _gaveta == null:
		_gaveta = PanelContainer.new()
		_gaveta.theme_type_variation = "Cartao"
		_gaveta.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
		_gaveta.offset_left = -(400 if not Settings.is_mobile else 460)
		_gaveta.offset_right = -24
		_gaveta.offset_top = 90
		_gaveta.offset_bottom = -24
		add_child(_gaveta)
		var col := VBoxContainer.new()
		_gaveta.add_child(col)
		var cab := HBoxContainer.new()
		col.add_child(cab)
		var t := Label.new()
		t.theme_type_variation = "Subtitulo"
		t.text = "Amigos"
		t.add_theme_color_override("font_color", VentaniaTheme.AMARELO)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cab.add_child(t)
		var x := _botao_icone("fechar", "", "BotaoFantasma")
		x.pressed.connect(func(): _gaveta.visible = false)
		cab.add_child(x)
		var add := HBoxContainer.new()
		col.add_child(add)
		var campo := LineEdit.new()
		campo.placeholder_text = "Adicionar pelo nome"
		campo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		campo.custom_minimum_size.y = _alvo
		add.add_child(campo)
		var mais := _botao_icone("mais", "", "Button")
		var enviar := func():
			if not campo.text.strip_edges().is_empty():
				var r := await Meta.friend_add(campo.text.strip_edges())
				if r["ok"]:
					campo.text = ""
		mais.pressed.connect(enviar)
		campo.text_submitted.connect(func(_t): enviar.call())
		add.add_child(mais)
		var rolagem := ScrollContainer.new()
		rolagem.size_flags_vertical = Control.SIZE_EXPAND_FILL
		rolagem.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		col.add_child(rolagem)
		_gaveta_lista = VBoxContainer.new()
		_gaveta_lista.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_gaveta_lista.add_theme_constant_override("separation", 8)
		rolagem.add_child(_gaveta_lista)
	else:
		_gaveta.visible = not _gaveta.visible
	_preencher_amigos()
	Meta.refresh_friends()


func _preencher_amigos() -> void:
	if _gaveta_lista == null:
		return
	for c in _gaveta_lista.get_children():
		c.queue_free()
	var f := Meta.friends
	if not f.get("incoming", []).is_empty():
		_secao("PEDIDOS DE AMIZADE")
		for a in f["incoming"]:
			var l := _linha_amigo(a["username"], "quer ser seu amigo", VentaniaTheme.AMARELO)
			var id := int(a["id"])
			l.add_child(_mini("ok", func(): Meta.friend_respond(id, true), "Aceitar"))
			l.add_child(_mini("fechar", func(): Meta.friend_respond(id, false), "Recusar"))
	_secao("AMIGOS (%d)" % f.get("friends", []).size())
	if f.get("friends", []).is_empty():
		var v := Label.new()
		v.theme_type_variation = "Pequeno"
		v.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.text = "Ninguém ainda. Adicione amigos pelo nome da conta deles."
		_gaveta_lista.add_child(v)
	var membros: Array = Meta.party.get("members", []).map(func(m): return int(m["id"]))
	for a in f.get("friends", []):
		var st: String = a.get("status", "offline")
		var txt: String = {"lobby": "no lobby", "fila": "procurando partida", "partida": "em partida", "offline": "offline"}.get(st, st)
		var cor: Color = {"lobby": VentaniaTheme.VERDE, "fila": VentaniaTheme.AMARELO, "partida": VentaniaTheme.CORAL}.get(st, VentaniaTheme.CINZA)
		var l := _linha_amigo(a["username"], txt, cor)
		var id := int(a["id"])
		if id in membros:
			var no := Label.new()
			no.theme_type_variation = "Rotulo"
			no.text = "NO GRUPO"
			l.add_child(no)
		elif st == "lobby":
			var b := Button.new()
			b.text = "Convidar"
			b.add_theme_font_size_override("font_size", 16)
			b.pressed.connect(func(): Meta.invite(id))
			l.add_child(b)
	if not f.get("outgoing", []).is_empty():
		_secao("ENVIADOS")
		for a in f["outgoing"]:
			_linha_amigo(a["username"], "aguardando resposta", VentaniaTheme.CINZA)
	if Meta.party.get("members", []).size() > 1:
		_secao("GRUPO")
		var sair := Button.new()
		sair.theme_type_variation = "BotaoFantasma"
		sair.text = "Sair do grupo"
		sair.pressed.connect(func(): Meta.party_leave())
		_gaveta_lista.add_child(sair)


func _secao(t: String) -> void:
	var l := Label.new()
	l.theme_type_variation = "Rotulo"
	l.text = t
	_gaveta_lista.add_child(l)


func _linha_amigo(nome: String, estado: String, cor: Color) -> HBoxContainer:
	var l := HBoxContainer.new()
	l.add_theme_constant_override("separation", 10)
	var bola := ColorRect.new()
	bola.color = cor
	bola.custom_minimum_size = Vector2(10, 10)
	bola.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.add_child(bola)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", -4)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_child(col)
	var n := Label.new()
	n.text = nome
	n.add_theme_font_override("font", VentaniaTheme.FONTE_FORTE)
	col.add_child(n)
	var e := Label.new()
	e.theme_type_variation = "Pequeno"
	e.text = estado
	col.add_child(e)
	_gaveta_lista.add_child(l)
	return l


func _mini(icone: String, acao: Callable, dica: String) -> Button:
	var b := _botao_icone(icone, "", "BotaoFantasma")
	b.custom_minimum_size = Vector2(44, 44)
	b.tooltip_text = dica
	b.pressed.connect(acao)
	return b


# ---------------------------------------------------------------- avisos

func _on_convite(c: Dictionary) -> void:
	var de: String = c.get("from", {}).get("username", "?")
	var cid: String = c.get("id", "")
	_aviso("%s convidou você para o grupo." % de, "Aceitar", func(): Meta.invite_respond(cid, true), 12.0,
			"Recusar", func(): Meta.invite_respond(cid, false), "notificacao")


func _aviso(texto: String, acao_txt := "", acao := Callable(), segundos := 4.0, acao2_txt := "", acao2 := Callable(), som := "foco") -> void:
	var p := PanelContainer.new()
	p.theme_type_variation = "CartaoClaro"
	var l := HBoxContainer.new()
	p.add_child(l)
	var t := Label.new()
	t.text = texto
	t.add_theme_color_override("font_color", VentaniaTheme.TINTA)
	t.add_theme_font_override("font", VentaniaTheme.FONTE_FORTE)
	l.add_child(t)
	for par in [[acao_txt, acao, "BotaoPrimario"], [acao2_txt, acao2, "Button"]]:
		if not par[0].is_empty():
			var b := Button.new()
			b.theme_type_variation = par[2]
			b.add_theme_font_size_override("font_size", 16)
			b.text = par[0]
			var f: Callable = par[1]
			b.pressed.connect(func():
				Audio.play_ui("clique")
				f.call()
				p.queue_free())
			l.add_child(b)
	_avisos.add_child(p)
	Audio.play_ui(som)
	# entra deslizando de cima
	p.modulate.a = 0.0
	var tw := p.create_tween().set_parallel()
	tw.tween_property(p, "modulate:a", 1.0, 0.18)
	tw.tween_property(p, "position:y", p.position.y, 0.22).from(p.position.y - 24).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	get_tree().create_timer(segundos).timeout.connect(func():
		if is_instance_valid(p):
			p.queue_free())


# ---------------------------------------------------------------- 3D

## Troca o modelo do slot do grupo pelo traje (mesmo esqueleto e animações).
func _vestir(i: int, traje: String) -> void:
	var base := _bonecos[i]
	if base.has_node("Modelo") and _trajes_slot[i] == traje:
		return
	_trajes_slot[i] = traje
	if base.has_node("Modelo"):
		var velho := base.get_node("Modelo")
		base.remove_child(velho)
		velho.queue_free()
	var rec := (load(Cosmeticos.outfit_scene(traje)) as PackedScene).instantiate() as Node3D
	rec.name = "Modelo"
	rec.rotation_degrees.y = -12.0 + (8.0 if i % 2 == 1 else -8.0) * float(i > 0)
	base.add_child(rec)
	var aps := rec.find_children("*", "AnimationPlayer", true, false)
	if not aps.is_empty():
		var ap := aps[0] as AnimationPlayer
		ap.play("idle")
		ap.seek(i * 0.37, true)


func _mundo_3d() -> void:
	var vp_cont := SubViewportContainer.new()
	vp_cont.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vp_cont.stretch = true
	vp_cont.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vp_cont)
	_vp3d = SubViewport.new()
	_vp3d.own_world_3d = true
	_vp3d.transparent_bg = true
	_vp3d.msaa_3d = get_tree().root.msaa_3d
	_vp3d.scaling_3d_scale = get_tree().root.scaling_3d_scale
	vp_cont.add_child(_vp3d)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("b9c6ff")
	env.ambient_light_energy = 0.45
	var we := WorldEnvironment.new()
	we.environment = env
	_vp3d.add_child(we)
	var sol := DirectionalLight3D.new()
	sol.rotation_degrees = Vector3(-35, -25, 0)
	sol.light_energy = 1.0
	sol.light_color = Color("fff3dc")
	sol.add_to_group("sol")
	_vp3d.add_child(sol)
	var contra := DirectionalLight3D.new()       # luz de recorte (borda azulada)
	contra.rotation_degrees = Vector3(-20, 150, 0)
	contra.light_energy = 0.6
	contra.light_color = Color("7fe3ff")
	_vp3d.add_child(contra)
	for i in POS_GRUPO.size():
		var base := Node3D.new()
		base.position = POS_GRUPO[i]
		_vp3d.add_child(base)
		var disco := MeshInstance3D.new()
		var cil := CylinderMesh.new()
		cil.top_radius = 0.75 if i == 0 else 0.6
		cil.bottom_radius = cil.top_radius + 0.06
		cil.height = 0.14
		cil.radial_segments = 32
		var mat := StandardMaterial3D.new()
		mat.albedo_color = VentaniaTheme.AMARELO if i == 0 else Color("4b5a8a")
		mat.emission_enabled = true
		mat.emission = mat.albedo_color * 0.25
		cil.material = mat
		disco.mesh = cil
		disco.position.y = -0.07
		base.add_child(disco)
		_bonecos.append(base)
		_vestir(i, "")
	_cam = Camera3D.new()
	_cam.fov = 34
	_vp3d.add_child(_cam)
	_cam.look_at_from_position(Vector3(0.9, 1.75, 7.6), Vector3(0.55, 1.05, 0), Vector3.UP)
