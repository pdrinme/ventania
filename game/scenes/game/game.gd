extends Control
## Partida (cliente). Modos (SceneManager.params["modo"]):
##   "local"    — treino: sobe um GameServer neste processo, num mundo 3D separado
##                (SubViewport com own_world_3d), e conecta por ENet em 127.0.0.1.
##   "br_local" — Battle Royale na Ilha Ventania com servidor neste processo.
##   "remoto"   — conecta em params["host"]:params["porta"].
## O mapa é criado quando o servidor diz qual é (S_WELCOME).
## O jogador local é PREDITO (Movement.step com a mesma entrada enviada ao
## servidor) e RECONCILIADO a cada snapshot. Os outros são INTERPOLADOS ~150 ms atrás.

const ATRASO_INTERP_TICKS := 4.5
const PORTAS_LOCAIS := [24891, 24892, 24893, 24894]   # longe de 24800+ (servidor dedicado e salas)

var modo := "local"
var server: GameServer
var client: GameClient
var mundo: Mapa
var tormenta: StormVisual
var match_hud: MatchHud
var _partida := {}                  # último S_MATCH
var _assistindo := -1               # id do jogador assistido (espectador)
var resultado := {}                 # último S_RESULT (testes)
var onibus: OnibusBatalha           # rota do Ônibus de Batalha da partida atual
var _onibus_vis: Node3D
var _queda_antes := 0
var _tormenta_antes := {}
var pawn: Pawn
var visual: PawnVisual
var camera: PlayerCamera
var sampler: InputSampler
var hud: GameHud
var combat_hud: CombatHud
var touch: TouchControls
var fx: CombatFx
var chests: ChestsClient
var inventario: InventoryScreen
var build: BuildClient
var modo_build: BuildMode
var build_hud: BuildHud

var _seq := 0
var _pendentes: Array = []          # InputCmd ainda não confirmados pelo servidor
var _historico: Array = []          # últimas entradas enviadas (redundância)
var _remotos := {}                  # id -> {"visual": PawnVisual, "amostras": Array, "nome": String}
var _nomes := {}
var _ultimo_tick := 0
var _ultimo_tick_t := 0.0
var _info_t := 0.0
var _banda_t := 0.0
var _banda_rec := 0
var _banda_env := 0
var _correcoes := 0                 # reconciliações com erro > 5 cm (diagnóstico)
var _saindo := false
var local_port := 0                 # porta do servidor local (treino)
var _tick_render := 0.0             # tick em que os outros estão sendo desenhados (lag comp.)
var _loot := {}                     # id -> LootVisual
var _baus_abertos := {}
var _status := {}
var _morto := false
# previsão local do disparo (só efeitos; o servidor decide acertos)
var _mag_local := 0
var _fire_next_local := 0.0
var _prev_fire_local := false
var hits_confirmed := 0             # diagnóstico/testes
# ações do próprio jogador (para animação e sons)
var _acao_fim := 0.0
var _acao_total := 0.0
var _acao_antes := 0
var _item_antes := ""
var _bau_segurando := -1            # baú que está sendo aberto (segurando Interagir)
var _bau_t := 0.0
var _bau_alcance := -1              # baú cuja tampa a mão acompanha ao abrir
var _bau_alcance_t := 0.0
const SEGURAR_BAU_S := float(LootServer.ABRIR_BAU_PASSOS) / Protocol.TICK_RATE
# picareta prevista localmente (mesmo relógio de passos do servidor)
var _golpe_ini := -1                # seq do início do golpe em andamento (-1 = nenhum)
var _golpe_ant := -1
var _golpe_combo := 0
var _golpe_impactou := false
var _golpe_t0 := 0.0                # instante do início (progresso suave da animação)
var melee_confirmed := 0            # impactos confirmados pelo servidor (testes)
var melee_local := 0                # impactos previstos localmente (testes)
var _proximos_t := 0.0


func _ready() -> void:
	var p: Dictionary = SceneManager.params
	modo = p.get("modo", "local")

	camera = PlayerCamera.new()
	add_child(camera)
	sampler = InputSampler.new()
	add_child(sampler)

	var camada := CanvasLayer.new()
	add_child(camada)
	# Controles dentro de CanvasLayer não herdam o tema da janela: aplica explicitamente
	var tema := get_tree().root.theme
	touch = TouchControls.new()
	touch.theme = tema
	touch.sampler = sampler
	touch.camera = camera
	touch.pode_mirar = func() -> bool: return combat_hud != null and ItemDB.is_weapon(combat_hud.current_item())
	camada.add_child(touch)
	match_hud = MatchHud.new()
	match_hud.theme = tema
	camada.add_child(match_hud)
	match_hud.back_to_menu.connect(_sair)
	combat_hud = CombatHud.new()
	combat_hud.theme = tema
	camada.add_child(combat_hud)
	combat_hud.slot_tapped.connect(func(i): sampler.select_slot(i))
	modo_build = BuildMode.new()
	modo_build.jogo = self
	add_child(modo_build)
	touch.construcao = modo_build
	modo_build.changed.connect(touch.queue_redraw)
	build_hud = BuildHud.new()
	build_hud.theme = tema
	build_hud.modo = modo_build
	camada.add_child(build_hud)
	inventario = InventoryScreen.new()
	inventario.theme = tema
	camada.add_child(inventario)
	inventario.request.connect(_pedido_inventario)
	inventario.close_requested.connect(func(): _inventario(false))
	touch.inventory_pressed.connect(func(): _inventario(not inventario.is_open()))
	hud = GameHud.new()
	hud.theme = tema
	camada.add_child(hud)
	# tela de resultado por cima de tudo (botões clicáveis, com foco para teclado/controle)
	match_hud.resultado.reparent(camada)
	match_hud.resultado.theme = tema
	match_hud.play_again.connect(_jogar_de_novo)
	match_hud.watch.connect(_assistir)
	fx = CombatFx.new()
	add_child(fx)
	chests = ChestsClient.new()
	add_child(chests)
	tormenta = StormVisual.new()
	add_child(tormenta)
	_montar_privada(camada, p)
	hud.resume_requested.connect(func(): _pausar(false))
	hud.quit_requested.connect(_sair)
	_atualizar_toque(InputManager.device)
	InputManager.device_changed.connect(_atualizar_toque)

	client = GameClient.new()
	add_child(client)
	client.welcomed.connect(_on_welcome)
	client.simulate_from_args(OS.get_cmdline_user_args())
	Meta.progress.connect(func(pr): if match_hud: match_hud.show_progress(pr))
	client.rejected.connect(_on_recusa)
	client.disconnected.connect(_on_queda)
	client.snapshot_received.connect(_on_snapshot)
	client.player_info.connect(func(id, nome):
		_nomes[id] = nome
		match_hud.set_names(_nomes))
	client.player_outfit.connect(_on_traje)
	client.match_state.connect(_on_match)
	client.storm.connect(_on_storm)
	client.bus.connect(_on_bus)
	client.result.connect(_on_result)
	client.player_left.connect(_remover_remoto)
	client.status_received.connect(_on_status)
	client.shot_received.connect(_on_shot)
	client.hit_confirmed.connect(_on_hit)
	client.damaged.connect(func(_i):
		combat_hud.damage_flash()
		Audio.play_sfx("dano", -4.0))
	client.eliminated.connect(_on_elim)
	client.loot_spawned.connect(_on_loot)
	client.loot_removed.connect(_on_loot_gone)
	client.chest_changed.connect(_on_chest)
	client.inventory_result.connect(_on_inv_result)
	client.melee_impact.connect(_on_melee)
	client.piece.connect(func(d): if build: build.on_piece(d))
	client.piece_gone.connect(func(id, m): if build: build.on_gone(id, m))
	client.pieces_hp.connect(func(l): if build: build.on_hp(l))
	client.build_reset.connect(func(): if build: build.on_reset())

	var host: String = p.get("host", "127.0.0.1")
	var porta: int = p.get("porta", Protocol.DEFAULT_PORT)
	if modo == "local" or modo == "br_local":
		porta = _subir_servidor_local()
		if porta == 0:
			_falhar("Não foi possível iniciar o servidor local.")
			return
		host = "127.0.0.1"
	var nome: String = Settings.get_value("network", "player_name")
	client.ticket = p.get("ticket", "")      # partida do lobby: o servidor usa o nome da conta
	if Meta.logged_in():
		nome = Meta.account["username"]
	if client.connect_to(host, porta, nome) != OK:
		_falhar("Endereço inválido: %s:%d" % [host, porta])
		return
	hud.flash("Conectando…", 10.0)
	Log.info("partida", "modo %s, conectando em %s:%d" % [modo, host, porta])


func _subir_servidor_local() -> int:
	# mundo do servidor separado (física própria), sem renderização
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	vp.size = Vector2i(2, 2)
	add_child(vp)
	var br := modo == "br_local"
	var mundo_srv := Mapa.create(IlhaVentania.NOME if br else CampoTreino.NOME)
	mundo_srv.com_ambiente = false
	vp.add_child(mundo_srv)
	# BR local: começa com 1 jogador depois de uma espera curta
	var cfg := {}
	if br:
		cfg = PartidaBR.carregar_config()
		cfg["min_jogadores"] = 1
		cfg["espera_maxima_s"] = 3
		cfg["bots"] = {"preencher_ate": int(SceneManager.params.get("bots", BotCerebro.config().get("preencher_ate", 16)))}
	server = GameServer.new(mundo_srv, 0, "br" if br else "treino", cfg)
	# partida local: o servidor é deste processo; veste o traje equipado na conta (se houver)
	var eq: Dictionary = Meta.profile.get("equipped", {})
	server.cosmeticos_sem_ticket = {"traje": str(eq.get("traje", "")), "picareta": str(eq.get("picareta", "")), "planador": str(eq.get("planador", ""))}
	add_child(server)
	for porta in PORTAS_LOCAIS:
		if server.start(porta, "127.0.0.1") == OK:
			local_port = porta
			return porta
	return 0


const RECONEXAO_JANELA_S := 55.0     # servidor guarda o lugar por 60 s
const RECONEXAO_INTERVALO_S := 2.5
var _reconectando := false
var _reconexao_ini := 0.0


## Caiu a conexão: em partida de rede tenta voltar com a ficha (mesmo personagem).
func _on_queda() -> void:
	if _saindo:
		return
	if server != null or client.token == 0 or pawn == null:
		_falhar("Conexão com o servidor perdida.")
		return
	if not _reconectando:
		_reconectando = true
		_reconexao_ini = Time.get_ticks_msec() / 1000.0
		Log.warn("partida", "conexão perdida; tentando reconectar")
	_tentar_reconectar()


func _tentar_reconectar() -> void:
	if _saindo or not _reconectando:
		return
	var passou := Time.get_ticks_msec() / 1000.0 - _reconexao_ini
	if passou > RECONEXAO_JANELA_S:
		_falhar("Conexão com o servidor perdida (não foi possível reconectar).")
		return
	hud.flash("Conexão perdida — reconectando… (%d s)" % int(RECONEXAO_JANELA_S - passou), RECONEXAO_INTERVALO_S + 1.0)
	if client.reconnect() != OK:
		get_tree().create_timer(RECONEXAO_INTERVALO_S).timeout.connect(_tentar_reconectar)


func _on_recusa(motivo: String) -> void:
	if _reconectando and motivo.begins_with("O servidor não respondeu"):
		get_tree().create_timer(0.5).timeout.connect(_tentar_reconectar)
		return
	_falhar(motivo)


func _on_welcome(info: Dictionary) -> void:
	if info.get("reconectou", false) and mundo != null:
		# mesmo personagem: o mundo continua; o servidor manda tudo de novo
		_reconectando = false
		_pendentes.clear()
		_historico.clear()
		for id in _loot.keys():
			_on_loot_gone(id, false)
		if build:
			build.on_reset()
		hud.flash("Reconectado!", 2.0)
		Log.info("partida", "reconectado (id %d)" % info["id"])
		return
	mundo = Mapa.create(info["map"])
	add_child(mundo)
	move_child(mundo, 0)
	chests.setup(mundo)
	build = BuildClient.new()
	add_child(build)
	build.setup(mundo)
	build.piece_destroyed.connect(_on_peca_destruida)
	match_hud.setup(mundo, tormenta)
	pawn = Pawn.new()
	pawn.entity_id = info["id"]
	mundo.add_child(pawn)
	pawn.global_position = mundo.spawn_point(0)
	visual = _novo_visual(info["id"])
	pawn.add_child(visual)
	camera.alvo = pawn
	match_hud.jogador = pawn
	hud.flash(mundo.display_name(), 2.5)
	_pausar(false)


func _physics_process(dt: float) -> void:
	client.poll()   # snapshots chegam aqui e reconciliam ANTES do novo passo
	if pawn == null or _saindo:
		return
	_seq += 1
	var cmd := sampler.make_cmd(_seq, camera.yaw_rad(), camera.pitch_rad())
	cmd.view_tick = maxi(0, int(_tick_render))
	Movement.step(pawn, cmd, dt)
	_prever_tiro(cmd)
	modo_build.physics_step(not _morto and (Input.is_action_pressed("fire") or sampler.touch_fire))
	_pendentes.append(cmd)
	if _pendentes.size() > 90:
		_pendentes.pop_front()       # servidor muito atrasado: não acumula sem limite
	_historico.append(cmd)
	if _historico.size() > Protocol.INPUT_REDUNDANCY:
		_historico.pop_front()
	client.send_inputs(_historico)


func _on_snapshot(s: Dictionary) -> void:
	if s["tick"] < _ultimo_tick:
		return
	_ultimo_tick = s["tick"]
	_ultimo_tick_t = Time.get_ticks_msec() / 1000.0
	var vistos := {}
	for e: Protocol.EntityState in s["entities"]:
		vistos[e.id] = true
		if pawn and e.id == pawn.entity_id:
			_reconciliar(e, s["ack"])
			_set_morto(e.flags & Protocol.F_DEAD != 0)
		else:
			_amostra_remoto(e, s["tick"])
	# relevância (Etapa 7): quem está longe vem em metade dos snapshots ou some
	# deles; só remove quem ficou ~1 s sem aparecer
	for id in _remotos.keys():
		var am: Array = _remotos[id]["amostras"]
		if not vistos.has(id) and (am.is_empty() or s["tick"] - int(am[-1]["tick"]) > Protocol.TICK_RATE):
			_remover_remoto(id)


func _reconciliar(e: Protocol.EntityState, ack: int) -> void:
	while not _pendentes.is_empty() and _pendentes[0].seq <= ack:
		_pendentes.pop_front()
	var previsto := pawn.global_position
	var yaw_atual := pawn.yaw
	pawn.apply_state(e)
	var dt := 1.0 / Protocol.TICK_RATE
	for cmd in _pendentes:
		Movement.step(pawn, cmd, dt)
	pawn.yaw = yaw_atual
	if previsto.distance_to(pawn.global_position) > 0.05:
		_correcoes += 1


func _amostra_remoto(e: Protocol.EntityState, tick: int) -> void:
	if not _remotos.has(e.id):
		var v := _novo_visual(e.id)
		v.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		mundo.add_child(v)
		var nome := Label3D.new()
		nome.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		nome.fixed_size = true
		nome.pixel_size = 0.0014
		nome.font = load("res://assets/ui/fontes/fredoka_700.woff2")
		nome.font_size = 26
		nome.outline_size = 8
		nome.outline_modulate = Color("24252c")
		nome.position.y = 2.25
		nome.modulate = Color("ffc93c") if e.id >= GameServer.DUMMY_ID_BASE else Color.WHITE
		v.add_child(nome)
		_remotos[e.id] = {"visual": v, "amostras": [], "rotulo": nome}
	var amostras: Array = _remotos[e.id]["amostras"]
	amostras.append({"tick": tick, "pos": e.position, "vel": e.velocity, "yaw": e.yaw, "flags": e.flags, "weapon": e.weapon,
			"pitch": e.pitch, "action": e.action, "progress": e.progress, "queda": e.queda})
	while amostras.size() > 20:
		amostras.pop_front()


const NOME_DISTANCIA_M := 25.0


## Nomes sobre os outros jogadores entregariam a posição (a plaquinha tem tamanho
## fixo na tela, então aparece mesmo quando o boneco já é um pontinho). Durante o
## ônibus e o jogo do Battle Royale, adversários (humanos e bots) não têm nome à
## mostra. Na espera, no fim e no treino o nome aparece, mas só de perto.
## (Companheiros de time, quando existirem, poderão ter o nome sempre visível.)
func _mostrar_nome(boneco: bool, pos: Vector3) -> bool:
	if boneco:
		return true
	var estado: int = _partida.get("estado", Protocol.MATCH_TREINO)
	if estado == Protocol.MATCH_ONIBUS or estado == Protocol.MATCH_JOGO:
		return false
	var olho := camera.global_position if camera else pos
	return olho.distance_to(pos) <= NOME_DISTANCIA_M


var _cosmeticos := {}        # id -> {"traje", "picareta", "planador"} (S_PLAYER_INFO). Só aparência.


func _novo_visual(id: int) -> PawnVisual:
	var c: Dictionary = _cosmeticos.get(id, {})
	var v := PawnVisual.new()
	v.traje = c.get("traje", "")
	v.picareta_id = c.get("picareta", "")
	v.planador_id = c.get("planador", "")
	return v


## Cosméticos de um jogador (inclusive o próprio): troca o visual se já existir.
func _on_traje(id: int, cos: Dictionary) -> void:
	if _cosmeticos.get(id, {}) == cos:
		return
	_cosmeticos[id] = cos
	if pawn and id == pawn.entity_id and visual:
		var novo := _novo_visual(id)
		visual.queue_free()
		visual = novo
		pawn.add_child(visual)
	elif _remotos.has(id):
		var r: Dictionary = _remotos[id]
		var antigo: PawnVisual = r["visual"]
		var novo := _novo_visual(id)
		novo.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		mundo.add_child(novo)
		novo.global_transform = antigo.global_transform
		var rotulo: Node = r["rotulo"]
		rotulo.reparent(novo, false)
		antigo.queue_free()
		r["visual"] = novo


func _remover_remoto(id: int) -> void:
	if _remotos.has(id):
		(_remotos[id]["visual"] as Node).queue_free()
		_remotos.erase(id)


func _process(delta: float) -> void:
	if pawn:
		_atualizar_visual_proprio(delta)
		_atualizar_aviso()
		match_hud.yaw = camera.yaw_rad()
		_atualizar_onibus(delta)
		if _morto and _assistindo >= 0:
			_seguir_assistido()
	_interpolar_remotos()
	if inventario.is_open():
		_proximos_t += delta
		if _proximos_t > 0.2:
			_proximos_t = 0.0
			_atualizar_proximos()
	_info_t += delta
	if _info_t > 0.5:
		_info_t = 0.0
		# banda medida (carga útil): ↓ recebido, ↑ enviado, em kbit/s
		var agora := Time.get_ticks_msec() / 1000.0
		var dt := maxf(0.001, agora - _banda_t)
		var desce := (client.bytes_rec - _banda_rec) * 8.0 / 1000.0 / dt
		var sobe := (client.bytes_env - _banda_env) * 8.0 / 1000.0 / dt
		_banda_t = agora
		_banda_rec = client.bytes_rec
		_banda_env = client.bytes_env
		var sim := " · sim %d ms/%d%%" % [client.lag_ms, int(client.perda * 100)] if client.simulating() else ""
		hud.set_info(client.rtt_ms(), 1 + remote_player_count(), " · ↓%.0f ↑%.0f kbit/s%s" % [desce, sobe, sim])


func _interpolar_remotos() -> void:
	if _ultimo_tick == 0:
		return
	var agora := Time.get_ticks_msec() / 1000.0
	var tick_render := _ultimo_tick + (agora - _ultimo_tick_t) * Protocol.TICK_RATE - ATRASO_INTERP_TICKS
	_tick_render = tick_render
	for r in _remotos.values():
		var a: Array = r["amostras"]
		if a.is_empty():
			continue
		var anterior: Dictionary = a[0]
		var proxima: Dictionary = a[a.size() - 1]
		for i in range(a.size() - 1):
			if a[i]["tick"] <= tick_render and a[i + 1]["tick"] >= tick_render:
				anterior = a[i]
				proxima = a[i + 1]
				break
		var t := 0.0
		if proxima["tick"] != anterior["tick"]:
			t = clampf((tick_render - anterior["tick"]) / float(proxima["tick"] - anterior["tick"]), 0.0, 1.0)
		var v: PawnVisual = r["visual"]
		var rotulo: Label3D = r["rotulo"]
		if rotulo.text.is_empty():
			rotulo.text = _nomes.get(_remotos.find_key(r), "")
		v.global_position = (anterior["pos"] as Vector3).lerp(proxima["pos"], t)
		rotulo.visible = _mostrar_nome(proxima["flags"] & Protocol.F_DUMMY != 0, v.global_position)
		var yaw := lerp_angle(anterior["yaw"], proxima["yaw"], t)
		r["boneco"] = proxima["flags"] & Protocol.F_DUMMY != 0
		v.visible = proxima["flags"] & Protocol.F_DEAD == 0 and proxima.get("queda", 0) != Pawn.NO_ONIBUS
		v.set_fall(proxima.get("queda", 0))
		v.set_held(proxima["weapon"])
		v.update_state(proxima["vel"], proxima["flags"], yaw)
		v.set_aim(lerp_angle(anterior["pitch"], proxima["pitch"], t), proxima["flags"] & Protocol.F_AIMING != 0)
		# golpes seguidos recomeçam o progresso (1 -> 0): não interpola "para trás"
		var mesma_acao: bool = anterior["action"] == proxima["action"] and proxima["progress"] >= anterior["progress"]
		v.set_action(proxima["action"], lerpf(anterior["progress"], proxima["progress"], t) if mesma_acao else proxima["progress"])
		# abrindo baú: a mão alcança a alça do baú mais próximo
		var bau := _bau_proximo(v.global_position) if proxima["action"] == Protocol.ACT_CHEST else -1
		v.set_reach(chests.handle_position(bau) if bau >= 0 else Vector3.ZERO, 1.0 if bau >= 0 else 0.0)


# ---------- combate (cliente) ----------

func _on_status(st: Dictionary) -> void:
	var item_antes := combat_hud.current_item()
	_status = st
	combat_hud.update_status(st)
	inventario.update_status(st)
	var na_picareta: bool = st["selected"] == Protocol.SELECTED_PICKAXE
	sampler.selected = Inventory.PICKAXE if na_picareta else st["selected"]
	_mag_local = 0 if na_picareta else st["slots"][st["selected"]]["mag"]
	var agora := Time.get_ticks_msec() / 1000.0
	_acao_fim = agora + st["action_left_ms"] / 1000.0
	_acao_total = st["action_total_ms"] / 1000.0
	# sons das transições de ação
	if st["action"] != _acao_antes:
		if st["action"] == Protocol.ACT_RELOAD:
			Audio.play_sfx("recarga_inicio")
		elif _acao_antes == Protocol.ACT_RELOAD and st["action"] == 0:
			Audio.play_sfx("bomba" if item_antes == "trovao" else "recarga_fim")
		elif _acao_antes == Protocol.ACT_USE and st["action"] == 0 and _acao_fim_esperado(agora):
			Audio.play_sfx("escudo_ok" if item_antes.begins_with("celula") else "cura_ok")
	_acao_antes = st["action"]
	if combat_hud.current_item() != item_antes and not combat_hud.current_item().is_empty():
		Audio.play_sfx("picareta_sacar" if ItemDB.is_tool_item(combat_hud.current_item()) else "sacar", -6.0)


func _acao_fim_esperado(agora: float) -> bool:
	return absf(agora - _acao_fim) < 0.4 or _acao_total > 0.0


## Item na mão, mira, ação e alcance do próprio personagem.
func _atualizar_visual_proprio(delta: float) -> void:
	var atual := combat_hud.current_item()
	visual.set_held(ItemDB.index_of(atual))
	visual.update_state(pawn.velocity, pawn.flags(), pawn.yaw)
	visual.set_aim(camera.pitch_rad(), camera.mirando and ItemDB.is_weapon(atual))
	var agora := Time.get_ticks_msec() / 1000.0
	var acao: int = _status.get("action", 0)
	var prog := 0.0
	if acao != 0 and _acao_total > 0.0:
		prog = clampf(1.0 - (_acao_fim - agora) / _acao_total, 0.0, 1.0)
	# golpe de picareta previsto: anima já, sem esperar o servidor
	if _golpe_ini >= 0 and ItemDB.is_tool_item(atual):
		acao = Protocol.ACT_SWING_B if _golpe_combo == 1 else Protocol.ACT_SWING
		prog = clampf((agora - _golpe_t0) / (Combat.melee_swing_steps() / float(Protocol.TICK_RATE)), 0.0, 1.0)
	# segurando Interagir num baú: alcança a alça (previsto localmente)
	if _bau_segurando >= 0 and acao == 0:
		acao = Protocol.ACT_CHEST
		prog = clampf(_bau_t / SEGURAR_BAU_S, 0.0, 1.0)
	visual.set_action(acao, prog)
	if _bau_alcance >= 0:
		_bau_alcance_t += delta
		if _bau_alcance_t > 0.55:
			_bau_alcance = -1
	var bau := _bau_segurando if _bau_segurando >= 0 else _bau_alcance
	visual.set_reach(chests.handle_position(bau) if bau >= 0 else Vector3.ZERO, 1.0 if bau >= 0 else 0.0)


func _prever_tiro(cmd: Protocol.InputCmd) -> void:
	if cmd.slot > 0:
		_fire_next_local = _seq + CombatServer.PASSOS_TROCA
		_golpe_ini = -1
	var id := combat_hud.current_item()
	var fogo := cmd.has(Protocol.BTN_FIRE)
	if ItemDB.is_tool_item(id) and not _morto:
		_prever_golpe(cmd, fogo)
		_prev_fire_local = fogo
		return
	if _morto or not ItemDB.is_weapon(id) or _status.get("action", 0) != 0:
		_prev_fire_local = fogo
		return
	var w := ItemDB.weapon(id)
	var gatilho: bool = fogo if w["automatica"] else (fogo and not _prev_fire_local)
	_prev_fire_local = fogo
	if not gatilho or _seq < _fire_next_local or _mag_local <= 0:
		return
	_mag_local -= 1
	_fire_next_local = _seq + Protocol.TICK_RATE / float(w["cadencia"])
	var raio := Combat.aim_ray(pawn.global_position, pawn.crouched, cmd.yaw, cmd.pitch)
	var movendo := Vector2(pawn.velocity.x, pawn.velocity.z).length() > 0.5
	var disp := Combat.spread_deg(w, cmd.has(Protocol.BTN_AIM), movendo, pawn.crouched, pawn.grounded)
	visual.fire()
	var cano := visual.muzzle_position()
	var curto := int(w["projeteis"]) > 1
	for d: Vector3 in Combat.pellet_dirs(raio["dir"], disp, int(w["projeteis"]), Combat.shot_seed(pawn.entity_id, cmd.seq)):
		var fim := _fim_do_tiro(raio["origin"], d, float(w["alcance"]))
		# o traçante sai do CANO e vai até onde a linha da mira bate
		fx.tracer(cano, fim["pos"], fim["jogador"], curto, fim["normal"])
	Audio.play_sfx(_som_tiro(id))


## Mesma regra do CombatServer._picareta, no relógio local (seq): o golpe começa,
## o impacto acontece no passo melee_impact_step() com efeito imediato, e golpes
## seguidos alternam o lado. O servidor confirma (S_MELEE) e decide o dano.
func _prever_golpe(cmd: Protocol.InputCmd, fogo: bool) -> void:
	var n := Combat.melee_swing_steps()
	if _golpe_ini >= 0:
		var k := _seq - _golpe_ini
		if not _golpe_impactou and k >= Combat.melee_impact_step():
			_golpe_impactou = true
			_impacto_local(cmd)
		if k >= n:
			_golpe_ini = -1
	if fogo and _golpe_ini < 0 and _seq >= _fire_next_local:
		var seguido := _golpe_ant >= 0 and _seq - _golpe_ant <= n + 1
		_golpe_combo = (1 - _golpe_combo) if seguido else 0
		_golpe_ini = _seq
		_golpe_ant = _seq
		_golpe_impactou = false
		_fire_next_local = _seq + n
		_golpe_t0 = Time.get_ticks_msec() / 1000.0
		Audio.play_sfx("golpe_ar", -5.0, randf_range(0.92, 1.08))


func _impacto_local(cmd: Protocol.InputCmd) -> void:
	var raio := Combat.aim_ray(pawn.global_position, pawn.crouched, cmd.yaw, cmd.pitch)
	var origem: Vector3 = raio["origin"]
	var d: Vector3 = raio["dir"]
	var mundo := Combat.melee_trace(pawn.get_world_3d().direct_space_state, origem, d)
	var t_max: float = mundo["t"] if not mundo.is_empty() else Combat.melee_range()
	for rr in _remotos.values():
		var v: PawnVisual = rr["visual"]
		if not v.visible:
			continue
		var agachado: bool = rr["amostras"].size() > 0 and rr["amostras"][-1]["flags"] & Protocol.F_CROUCHED != 0
		var h := Hitbox.test(origem, d, v.global_position, agachado)
		if not h.is_empty() and h["t"] <= t_max:
			melee_local += 1
			fx.melee_impact(origem + d * float(h["t"]), -d, ImpactMaterial.JOGADOR)
			Audio.play_sfx("golpe_terra", -2.0)
			return
	if not mundo.is_empty():
		melee_local += 1
		fx.melee_impact(mundo["pos"], mundo["normal"], mundo["material"])
		Audio.play_at(_som_golpe(mundo["material"]), mundo["pos"], 0.0, randf_range(0.94, 1.06))


## Peça destruída (dano) ou desabada: fragmentos do material e som.
func _on_peca_destruida(pos: Vector3, material: int, motivo: int) -> void:
	var m: int = [ImpactMaterial.MADEIRA, ImpactMaterial.PEDRA, ImpactMaterial.METAL][material]
	fx.destroy_piece(pos, m)
	if pawn and pos.distance_to(pawn.global_position) < 80.0:
		Audio.play_at("desabar" if motivo == Protocol.GONE_DESABOU else _som_golpe(m), pos, -2.0, randf_range(0.85, 1.0))


static func _som_golpe(material: int) -> String:
	match material:
		ImpactMaterial.MADEIRA:
			return "golpe_madeira"
		ImpactMaterial.PEDRA:
			return "golpe_pedra"
		ImpactMaterial.METAL:
			return "golpe_metal"
	return "golpe_terra"


## Impacto confirmado pelo servidor. O próprio golpe já teve efeito previsto; os
## dos outros jogadores aparecem aqui.
func _on_melee(m: Dictionary) -> void:
	if pawn and m["swinger"] == pawn.entity_id:
		melee_confirmed += 1
		return
	fx.melee_impact(m["pos"], m["normal"], m["material"])
	Audio.play_at(_som_golpe(m["material"]) if m["material"] != ImpactMaterial.JOGADOR else "golpe_terra", m["pos"])


## Onde a linha da mira termina (previsão local, só para o efeito; o servidor decide
## o acerto): primeiro jogador/boneco no caminho ou o cenário.
func _fim_do_tiro(origem: Vector3, d: Vector3, alcance: float) -> Dictionary:
	var fim := origem + d * alcance
	var q := PhysicsRayQueryParameters3D.create(origem, fim, Pawn.LAYER_WORLD)
	var r := pawn.get_world_3d().direct_space_state.intersect_ray(q)
	var t_parede := origem.distance_to(r["position"]) if not r.is_empty() else alcance
	var melhor := t_parede
	var jogador := false
	for rr in _remotos.values():
		var v: PawnVisual = rr["visual"]
		if not v.visible:
			continue
		var agachado: bool = rr["amostras"].size() > 0 and rr["amostras"][-1]["flags"] & Protocol.F_CROUCHED != 0
		var h := Hitbox.test(origem, d, v.global_position, agachado)
		if not h.is_empty() and h["t"] < melhor:
			melhor = h["t"]
			jogador = true
	var normal: Vector3 = r["normal"] if not r.is_empty() and not jogador else -d
	return {"pos": origem + d * melhor, "jogador": jogador, "normal": normal}


func _on_shot(sh: Dictionary) -> void:
	var r: Dictionary = _remotos.get(sh["shooter"], {})
	var origem: Vector3 = sh["origin"]
	if not r.is_empty():
		var v: PawnVisual = r["visual"]
		v.fire()
		origem = v.muzzle_position()
		Audio.play_at(_som_tiro(ItemDB.id_of(v._item_idx)), origem)
	var curto: bool = sh["ends"].size() > 1
	for f in sh["ends"]:
		fx.tracer(origem, f["end"], f["hit"], curto)


static func _som_tiro(id: String) -> String:
	match id:
		"faisca":
			return "tiro_pistola"
		"zumbido":
			return "tiro_smg"
		"trovao":
			return "tiro_espingarda"
		"gaviao":
			return "tiro_precisao"
	return "tiro_rifle"


func _on_hit(h: Dictionary) -> void:
	hits_confirmed += 1
	var cabeca: bool = h["flags"] & Protocol.HIT_HEAD != 0
	combat_hud.hit_marker(cabeca)
	Audio.play_sfx("acerto_cabeca" if cabeca else "acerto", -3.0)
	fx.damage_number(h["pos"], h["damage"], cabeca, h["flags"] & Protocol.HIT_SHIELD != 0)


func _on_elim(e: Dictionary) -> void:
	var vitima: String = _nomes.get(e["victim"], "?")
	var quem: String = _nomes.get(e["killer"], "?")
	var arma := ItemDB.id_of(e["weapon"])
	var na_tormenta: bool = _em_partida() and e["killer"] == e["victim"]
	var texto := "%s saiu do mapa" % vitima if e["killer"] == e["victim"] or arma.is_empty() \
			else "%s eliminou %s (%s)" % [quem, vitima, ItemDB.display_name(arma)]
	if na_tormenta:
		texto = "%s foi pego pela Tormenta" % vitima
	combat_hud.kill_feed(texto)
	_cena_eliminacao(e["victim"])
	if pawn and e["killer"] == pawn.entity_id and e["victim"] != e["killer"] and _em_partida():
		match_hud.eliminacoes += 1
	if pawn and e["victim"] == pawn.entity_id:
		if _em_partida():
			combat_hud.show_eliminated("Eliminado por %s" % quem if e["killer"] != e["victim"] else ("Eliminado pela Tormenta" if na_tormenta else "Você caiu!"))
			_assistindo = e["killer"] if e["killer"] != e["victim"] else -1
		else:
			combat_hud.show_eliminated("Eliminado por %s\nReaparecendo…" % quem if e["killer"] != e["victim"] else "Você caiu!\nReaparecendo…")


## Animação de eliminação (todos os clientes veem): cópia do personagem com o traje
## dele cai e é levada pelo vento; o visual real já some pela flag F_DEAD.
func _cena_eliminacao(vitima: int) -> void:
	var v: PawnVisual = null
	if pawn and vitima == pawn.entity_id:
		v = visual
	elif _remotos.has(vitima):
		v = _remotos[vitima]["visual"]
	if v == null or not is_instance_valid(v) or not v.is_inside_tree() or not v.visible:
		return
	EliminacaoVisual.spawn(mundo, v.traje, v.global_transform)


func _set_morto(v: bool) -> void:
	if v == _morto:
		return
	_morto = v
	sampler.morto = v
	visual.visible = not v
	if v:
		_inventario(false)
		modo_build.set_active(false)
		_golpe_ini = -1
		if _em_partida():
			get_tree().create_timer(2.0).timeout.connect(func():
				if _morto:
					combat_hud.show_eliminated("")
					_proximo_assistido(0))
	else:
		_assistindo = -1
		camera.alvo = pawn
		match_hud.jogador = pawn
		match_hud.set_spectating("")
		match_hud.hide_result()
	if not v:
		combat_hud.show_eliminated("")


func _on_loot(l: Dictionary) -> void:
	_on_loot_gone(l["id"], false)
	var v := LootVisual.new()
	mundo.add_child(v)
	# saiu de um baú que acabou de abrir: salta da tampa até o chão
	var origem := Vector3.INF
	for i in chests.count():
		if chests.time_since_open(i) < 1.0 and chests.position(i).distance_to(l["pos"]) < 3.5:
			origem = chests.position(i) + Vector3(0, 0.6, 0)
	v.setup(l, origem)
	_loot[l["id"]] = v


func _on_loot_gone(id: int, coletado := true) -> void:
	if _loot.has(id):
		var v: LootVisual = _loot[id]
		if coletado and pawn and v.global_position.distance_to(pawn.global_position) < 2.6:
			Audio.play_sfx("pegar", -2.0)
		v.queue_free()
		_loot.erase(id)


func _on_chest(i: int, aberto: bool) -> void:
	if i < 0 or i >= chests.count():
		return
	if aberto:
		chests.open(i, _ultimo_tick > 0)
		_baus_abertos[i] = true
		if _bau_segurando == i:
			# a mão acompanha a alça enquanto a tampa sobe
			_bau_alcance = i
			_bau_alcance_t = 0.0
			_bau_segurando = -1
	else:
		chests.close(i)
		_baus_abertos.erase(i)


func _bau_proximo(pos: Vector3) -> int:
	for i in chests.count():
		if not chests.is_open(i) and pos.distance_to(chests.position(i)) < LootServer.BAU_DIST:
			return i
	return -1


## Indicador de interação: balão sobre o baú/item ao alcance (mesmas distâncias do
## servidor), destaque do baú e progresso de "segurar".
func _atualizar_aviso() -> void:
	combat_hud.set_prompt("")
	var cam := camera.camera()
	if _morto or hud.is_paused() or inventario.is_open():
		combat_hud.set_world_prompt(Vector2.ZERO, "", "")
		chests.highlight(-1)
		_bau_segurando = -1
		return
	var pos := pawn.global_position
	var tecla := _nome_tecla("interact")
	var segurando := Input.is_action_pressed("interact") or sampler.touch_interact
	var bau := _bau_proximo(pos)
	chests.highlight(bau)
	if bau >= 0:
		if segurando:
			if _bau_segurando != bau:
				_bau_t = 0.0
			_bau_segurando = bau
			_bau_t += get_process_delta_time()
		else:
			_bau_segurando = -1
		_balao(cam, chests.position(bau) + Vector3(0, 1.15, 0), tecla, "Abrir baú",
				clampf(_bau_t / SEGURAR_BAU_S, 0.0, 1.0) if _bau_segurando == bau else 0.0, Color("ffc93c"))
		return
	_bau_segurando = -1
	var melhor: LootVisual = null
	var dist := LootServer.PEGAR_DIST
	for v: LootVisual in _loot.values():
		if v.data["ammo"] == 0 and pos.distance_to(v.data["pos"]) < dist:
			dist = pos.distance_to(v.data["pos"])
			melhor = v
	if melhor:
		var id_l := ItemDB.id_of(melhor.data["item"])
		var cor := ItemDB.rarity_color(melhor.data["rarity"]) if ItemDB.is_weapon(id_l) else Color.WHITE
		var texto := "Pegar " + melhor.label()
		if not _cabe(id_l):
			# cheio: troca pelo item na mão; com a picareta na mão, não troca
			var na_mao := combat_hud.current_item()
			texto = "Inventário cheio (escolha o espaço)" if ItemDB.is_tool_item(na_mao) or na_mao.is_empty() \
					else "Trocar %s por %s" % [ItemDB.short_name(na_mao), melhor.label()]
		_balao(cam, melhor.data["pos"] + Vector3(0, 0.9, 0), tecla, texto, -1.0, cor)
	else:
		combat_hud.set_world_prompt(Vector2.ZERO, "", "")


## Cabe ao menos uma unidade deste item sem trocar nada? (pelo último status)
func _cabe(id: String) -> bool:
	var inv := Inventory.new()
	for i in mini(Inventory.SLOTS, _status.get("slots", []).size()):
		var sl: Dictionary = _status["slots"][i]
		var sid := ItemDB.id_of(sl["item"])
		if not sid.is_empty():
			inv.slots[i].item = sid
			inv.slots[i].count = maxi(1, sl["count"])
	return inv.room_for(id) > 0


# ---------- inventário ----------

func _inventario(abrir: bool) -> void:
	if inventario == null or abrir == inventario.is_open():
		return
	if abrir and (_morto or pawn == null or hud.is_paused()):
		return
	if abrir:
		modo_build.set_active(false)
		inventario.open()
		_atualizar_proximos()
	else:
		inventario.close()
	sampler.inventario_aberto = abrir
	camera.bloqueado = abrir or hud.is_paused()
	_atualizar_toque(InputManager.device)
	var capturar := not abrir and not hud.is_paused() and not Settings.is_mobile and InputManager.device != "toque" \
			and DisplayServer.get_name() != "headless"
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if capturar else Input.MOUSE_MODE_VISIBLE


func _pedido_inventario(op: Dictionary) -> void:
	if op["op"] == -1:
		sampler.select_slot(op["a"])        # equipar = trocar o item na mão (vai pela entrada)
		Audio.play_sfx("inv_mover", -6.0)
		return
	client.send_inventory(op)


func _on_inv_result(r: Dictionary) -> void:
	if r["code"] != Inventory.Err.OK:
		var msg: String = Inventory.MENSAGENS.get(r["code"], "")
		combat_hud.message(msg)
		inventario.show_result(r["code"])
		Audio.play_sfx("inv_erro", -4.0)
		return
	inventario.show_result(Inventory.Err.OK)
	match r["op"]:
		Protocol.OP_BUILD:
			Audio.play_sfx("construir", -4.0, randf_range(0.95, 1.05))
		Protocol.OP_EDIT:
			Audio.play_sfx("inv_mover", -2.0)
		Protocol.OP_DROP, Protocol.OP_DROP_AMMO, Protocol.OP_DROP_MATERIAL:
			Audio.play_sfx("largar", -3.0)
		Protocol.OP_SWAP, Protocol.OP_SPLIT:
			Audio.play_sfx("inv_mover", -4.0)


## Itens de espaço no chão ao alcance (para a lista da tela de inventário).
func _atualizar_proximos() -> void:
	if pawn == null:
		return
	var pos := pawn.global_position
	var lista := []
	for v: LootVisual in _loot.values():
		if not LootServer.is_reserve(v.data) and pos.distance_to(v.data["pos"]) <= LootServer.PROXIMOS_DIST:
			lista.append(v.data)
	lista.sort_custom(func(a, b): return pos.distance_to(a["pos"]) < pos.distance_to(b["pos"]))
	inventario.set_nearby(lista)


func _balao(cam: Camera3D, ponto: Vector3, tecla: String, texto: String, prog: float, cor: Color) -> void:
	if cam == null or cam.is_position_behind(ponto):
		combat_hud.set_world_prompt(Vector2.ZERO, "", "")
		return
	combat_hud.set_world_prompt(cam.unproject_position(ponto), tecla, texto, prog, cor)


func _nome_tecla(acao: String) -> String:
	match InputManager.device:
		"toque":
			return "Pegar"
		"controle":
			return "Y"
	if Settings.is_mobile:
		return "Pegar"
	var ev := InputManager.keyboard_events(acao)
	return InputSerializer.describe(ev[0]) if not ev.is_empty() else acao


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("map") and not hud.is_paused():
		match_hud.toggle_map(not match_hud.map_open())
		get_viewport().set_input_as_handled()
		return
	if _morto and _em_partida() and e.is_action_pressed("fire") and not match_hud.result_visible():
		_proximo_assistido(1)
		get_viewport().set_input_as_handled()
		return
	if e.is_action_pressed("inventory") and not hud.is_paused():
		_inventario(not inventario.is_open())
		get_viewport().set_input_as_handled()
		return
	if inventario.is_open() and (e.is_action_pressed("pause") or e.is_action_pressed("ui_cancel")):
		_inventario(false)
		get_viewport().set_input_as_handled()
		return
	if e.is_action_pressed("pause") or (e.is_action_pressed("ui_cancel") and hud.is_paused()):
		_pausar(not hud.is_paused())
		get_viewport().set_input_as_handled()
	elif e is InputEventMouseButton and e.pressed and not hud.is_paused() and not Settings.is_mobile and not match_hud.result_visible() \
			and InputManager.device == "teclado_mouse" and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:   # botão voltar do Android
		_pausar(not hud.is_paused())
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT and not hud.is_paused() and pawn:
		_pausar(true)


func _pausar(v: bool) -> void:
	if v:
		_inventario(false)
	hud.show_pause(v)
	sampler.bloqueado = v
	camera.bloqueado = v
	var capturar := not v and not Settings.is_mobile and InputManager.device != "toque" and DisplayServer.get_name() != "headless"
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if capturar else Input.MOUSE_MODE_VISIBLE


func _atualizar_toque(d: String) -> void:
	touch.visible = (d == "toque" or Settings.is_mobile) and not (inventario and inventario.is_open())
	var toque := d == "toque" or Settings.is_mobile
	if toque != _layout_toque or not _layout_feito:
		_layout_toque = toque
		_layout_feito = true
		for h in [combat_hud, build_hud, match_hud, hud]:
			if h and h.has_method("set_touch_layout"):
				h.set_touch_layout.call_deferred(toque)
	if combat_hud:
		combat_hud.set_pickaxe_key(_rotulo_picareta(d))


var _layout_toque := false
var _layout_feito := false


func _rotulo_picareta(d: String) -> String:
	if d == "toque" or Settings.is_mobile:
		return ""
	if d == "controle":
		return "►"
	var ev := InputManager.keyboard_events("pickaxe")
	return InputSerializer.describe(ev[0]) if not ev.is_empty() else "F"


func _falhar(motivo: String) -> void:
	if _saindo:
		return
	Log.warn("partida", motivo)
	SceneManager.message = motivo
	_sair()


func _sair(params := {}) -> void:
	if _saindo:
		return
	_saindo = true
	if not client.ticket.is_empty():
		Meta.match_left()          # o grupo volta ao lobby
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if client:
		client.close()
	if server:
		server.stop()
	SceneManager.go("menu", params)


func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if client:
		client.close()
	if server:
		server.stop()


# ---------- partida Battle Royale ----------

## Tick do servidor estimado agora (para o ônibus, que anda pelo relógio do servidor).
func server_tick_now() -> float:
	return _ultimo_tick + (Time.get_ticks_msec() / 1000.0 - _ultimo_tick_t) * Protocol.TICK_RATE


func _on_bus(d: Dictionary) -> void:
	onibus = OnibusBatalha.from_dict(d)
	match_hud.onibus = onibus
	if _onibus_vis == null:
		_onibus_vis = (load("res://assets/cenario/onibus_01.glb") as PackedScene).instantiate() as Node3D
		_onibus_vis.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		add_child(_onibus_vis)
	_onibus_vis.visible = true
	Audio.play_sfx("onibus", -2.0)


## Ônibus (visual pela rota), câmera no ônibus/queda e avisos da entrada.
func _atualizar_onibus(_delta: float) -> void:
	var tick := server_tick_now()
	var ativo := onibus != null and tick <= onibus.tick0 + onibus.duracao + 30
	if _onibus_vis:
		_onibus_vis.visible = ativo
		if ativo:
			var p := onibus.position_at(tick)
			var dir := onibus.direction()
			_onibus_vis.global_position = p + Vector3(0, sin(tick * 0.08) * 0.25 - 1.2, 0)
			_onibus_vis.global_transform.basis = Basis.looking_at(-dir, Vector3.UP).rotated(Vector3.UP, 0.0)
	var q := pawn.queda
	visual.set_fall(q)
	if q == Pawn.NO_ONIBUS and _onibus_vis and not _morto:
		# portas abertas: o próprio personagem aparece agachado na porta traseira,
		# segurando o batente (os outros continuam dentro do ônibus)
		var portas: bool = ativo and onibus.doors_open(tick)
		visual.visible = portas
		visual.preparando = portas
		if portas:
			visual.global_transform = _onibus_vis.global_transform * Transform3D(Basis(), Vector3(0, 0.8, -4.62))   # frente do visual (-Z) = para fora
		camera.alvo = _onibus_vis
		camera.distancia_extra = 15.0
		var falta := maxf(0.0, (onibus.abre - tick) / Protocol.TICK_RATE)
		var tecla := "Pular" if Settings.is_mobile or InputManager.device == "toque" else ("A" if InputManager.device == "controle" else "Espaço")
		match_hud.set_entry("Ônibus dos Ventos — portas abrem em %d s" % ceili(falta) if falta > 0.0 \
				else "[%s] Saltar do ônibus · portas fecham em %d s" % [tecla, ceili(maxf(0.0, (onibus.fecha - tick) / Protocol.TICK_RATE))])
	elif q == Pawn.QUEDA_LIVRE or q == Pawn.PLANADOR:
		if _queda_antes == Pawn.NO_ONIBUS:
			Audio.play_sfx("salto", -2.0)
			visual.visible = true
			visual.preparando = false
			visual.transform = Transform3D.IDENTITY      # volta a seguir o personagem
			camera.alvo = pawn
		if q == Pawn.PLANADOR and _queda_antes != Pawn.PLANADOR:
			Audio.play_sfx("planador", -3.0)
		camera.distancia_extra = 3.0
		match_hud.set_entry("Planador aberto — direcione com %s até o chão" % ("o joystick" if Settings.is_mobile else "WASD") if q == Pawn.PLANADOR \
				else ("Mergulhando! Olhe para a frente para frear" if pawn.velocity.y < -Movement.QUEDA_TERMINAL - 2.0
				else "Em queda livre — direcione com %s · olhe para baixo e vá em frente para mergulhar" % ("o joystick" if Settings.is_mobile else "WASD")))
	else:
		if _queda_antes != 0 and _queda_antes != Pawn.NO_ONIBUS:
			hud.flash("No chão! Pegue armas e fique de olho na Tormenta.", 2.5)
		if not _morto and camera.alvo != pawn and _assistindo < 0:
			camera.alvo = pawn
		camera.distancia_extra = 0.0
		match_hud.set_entry("")
	_queda_antes = q


## Mudanças de estado da Tormenta: aviso e som (zona marcada, fechando, fase concluída).
func _on_storm(t: Dictionary) -> void:
	var antes := _tormenta_antes
	tormenta.set_state(t)
	_tormenta_antes = t
	var fase: int = t["fase"] + 1
	if t["terminou"]:
		if not antes.get("terminou", false):
			match_hud.banner("Zona final! A Tormenta não para mais de causar dano.", Color("e2b8ff"))
			Audio.play_sfx("tormenta_alerta", 0.0)
		return
	if antes.is_empty() or t["fase"] != antes["fase"]:
		match_hud.banner("Fase %d de %d: nova zona segura marcada — fecha em %d s" % [fase, t["fases"], roundi(t["resta_ms"] / 1000.0)], Color.WHITE)
		Audio.play_sfx("tormenta_alerta", -4.0)
	elif t["fechando"] and not antes.get("fechando", false):
		match_hud.banner("A Tormenta está avançando! (fase %d, −%d/s)" % [fase, t["dano"]], Color("e2b8ff"))
		Audio.play_sfx("tormenta_alerta", 0.0)

func _em_partida() -> bool:
	var e: int = _partida.get("estado", Protocol.MATCH_TREINO)
	return e == Protocol.MATCH_JOGO or e == Protocol.MATCH_FIM or e == Protocol.MATCH_ONIBUS


var _privada_ui: Control


## Sala privada (lobby): mostra o código e, para o dono, o botão de começar.
func _montar_privada(camada: CanvasLayer, p: Dictionary) -> void:
	var codigo: String = p.get("private_code", "")
	if codigo.is_empty():
		return
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	col.grow_horizontal = Control.GROW_DIRECTION_BOTH
	col.offset_top = 110
	col.theme = get_tree().root.theme
	camada.add_child(col)
	var chip := PanelContainer.new()
	chip.theme_type_variation = "Chip"
	chip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var t := Label.new()
	t.add_theme_font_override("font", VentaniaTheme.FONTE_FORTE)
	t.text = "SALA PRIVADA · CÓDIGO %s" % codigo + ("" if p.get("dono_privada", false) else " · o dono começa a partida")
	chip.add_child(t)
	col.add_child(chip)
	if p.get("dono_privada", false):
		var b := Button.new()
		b.theme_type_variation = "BotaoPrimario"
		b.add_theme_font_size_override("font_size", 24)
		b.text = "COMEÇAR PARTIDA"
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		b.custom_minimum_size = Vector2(300, 64)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func():
			b.disabled = true
			Meta.private_start()
			hud.flash("Começando…", 2.0))
		col.add_child(b)
	_privada_ui = col


func _on_match(m: Dictionary) -> void:
	var antes: int = _partida.get("estado", Protocol.MATCH_TREINO)
	_partida = m
	if _privada_ui:
		_privada_ui.visible = m["estado"] == Protocol.MATCH_ESPERA
	match_hud.set_match(m)
	if m["estado"] != antes:
		match m["estado"]:
			Protocol.MATCH_CONTAGEM:
				hud.flash("Prepare-se!", 2.0)
			Protocol.MATCH_JOGO:
				hud.flash("O ônibus partiu: a Tormenta se formou!", 3.0)
			Protocol.MATCH_ONIBUS:
				hud.flash("Embarque! Salte do ônibus quando quiser.", 3.0)
			Protocol.MATCH_ESPERA:
				match_hud.eliminacoes = 0
				tormenta.clear()
				_tormenta_antes = {}
				onibus = null
				match_hud.onibus = null
				if match_hud.result_visible():
					match_hud.hide_result()
					_liberar_para_tela(false)
				if antes == Protocol.MATCH_FIM:
					hud.flash("Nova partida: área de espera", 2.5)


func _on_result(r: Dictionary) -> void:
	resultado = r
	combat_hud.show_eliminated("")
	var meu := pawn.entity_id if pawn else -1
	var venceu: bool = meu > 0 and r["vencedor"] == meu
	var traje: String = _cosmeticos.get(meu, {}).get("traje", "")
	if traje.is_empty():
		traje = Cosmeticos.default_outfit()
	var continua: bool = int(r["vencedor"]) == 0 and int(_partida.get("estado", 0)) == Protocol.MATCH_JOGO
	var de_novo := modo == "br_local" or (not client.ticket.is_empty() and Meta.logged_in())
	match_hud.show_result(r, _nomes.get(meu, Settings.get_value("network", "player_name")), _nomes.get(r["vencedor"], ""),
			venceu, traje, continua, de_novo)
	_liberar_para_tela(true)
	if venceu:
		Audio.play_ui("nivel")
	Audio.play_sfx("escudo_ok" if venceu else "dano", -2.0)


## Tela de resultado aberta: mouse livre, câmera e entradas paradas (PC); fechada: volta.
func _liberar_para_tela(aberta: bool) -> void:
	_inventario(false)
	sampler.bloqueado = aberta or hud.is_paused()
	camera.bloqueado = aberta or hud.is_paused()
	var capturar := not aberta and not hud.is_paused() and not Settings.is_mobile and InputManager.device != "toque" \
			and DisplayServer.get_name() != "headless"
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if capturar else Input.MOUSE_MODE_VISIBLE


func _assistir() -> void:
	_liberar_para_tela(false)
	_proximo_assistido(1)


## "Jogar de novo": volta ao lobby e já entra na fila do mesmo modo (online: o grupo
## volta ao lobby e o líder busca de novo; local: nova partida contra bots).
func _jogar_de_novo() -> void:
	if modo == "br_local":
		_saindo = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if client:
			client.close()
		if server:
			server.stop()
		SceneManager.go("game", {"modo": "br_local", "bots": SceneManager.params.get("bots", BotCerebro.config().get("preencher_ate", 16))})
		return
	_sair({"jogar_de_novo": true})


## Espectador: segue o jogador assistido (visual remoto) com a câmera.
func _seguir_assistido() -> void:
	var r: Dictionary = _remotos.get(_assistindo, {})
	if r.is_empty() or not (r["visual"] as PawnVisual).visible:
		_proximo_assistido(1)
		return
	camera.alvo = r["visual"]
	match_hud.jogador = r["visual"]


func _proximo_assistido(passo: int) -> void:
	var ids := _remotos.keys().filter(func(id): return id < GameServer.DUMMY_ID_BASE and (_remotos[id]["visual"] as PawnVisual).visible)
	ids.sort()
	if ids.is_empty():
		_assistindo = -1
		match_hud.set_spectating("")
		return
	var i := ids.find(_assistindo)
	_assistindo = ids[(i + passo + ids.size()) % ids.size()] if i >= 0 else ids[0]
	match_hud.set_spectating(_nomes.get(_assistindo, "?"))
	_seguir_assistido()


## Outros jogadores (sem contar os bonecos de treino).
func remote_player_count() -> int:
	return _remotos.keys().filter(func(id): return id < GameServer.DUMMY_ID_BASE).size()


## Diagnóstico (testes): quantas vezes a predição errou mais de 5 cm.
func correction_count() -> int:
	return _correcoes
