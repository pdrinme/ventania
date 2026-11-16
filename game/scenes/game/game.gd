extends Control
## Partida (cliente). Modos (SceneManager.params["modo"]):
##   "local"  — treino: sobe um GameServer neste processo, num mundo 3D separado
##              (SubViewport com own_world_3d), e conecta por ENet em 127.0.0.1.
##   "remoto" — conecta em params["host"]:params["porta"].
## O jogador local é PREDITO (Movement.step com a mesma entrada enviada ao
## servidor) e RECONCILIADO a cada snapshot. Os outros são INTERPOLADOS ~150 ms atrás.

const ATRASO_INTERP_TICKS := 4.5
const PORTAS_LOCAIS := [24801, 24802, 24803, 24804]

var modo := "local"
var server: GameServer
var client: GameClient
var mundo: CampoTreino
var pawn: Pawn
var visual: PawnVisual
var camera: PlayerCamera
var sampler: InputSampler
var hud: GameHud
var combat_hud: CombatHud
var touch: TouchControls
var fx: CombatFx

var _seq := 0
var _pendentes: Array = []          # InputCmd ainda não confirmados pelo servidor
var _historico: Array = []          # últimas entradas enviadas (redundância)
var _remotos := {}                  # id -> {"visual": PawnVisual, "amostras": Array, "nome": String}
var _nomes := {}
var _ultimo_tick := 0
var _ultimo_tick_t := 0.0
var _info_t := 0.0
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


func _ready() -> void:
	var p: Dictionary = SceneManager.params
	modo = p.get("modo", "local")

	mundo = CampoTreino.new()
	add_child(mundo)
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
	camada.add_child(touch)
	combat_hud = CombatHud.new()
	combat_hud.theme = tema
	camada.add_child(combat_hud)
	combat_hud.slot_tapped.connect(func(i): sampler.select_slot(i))
	hud = GameHud.new()
	hud.theme = tema
	camada.add_child(hud)
	fx = CombatFx.new()
	add_child(fx)
	hud.resume_requested.connect(func(): _pausar(false))
	hud.quit_requested.connect(_sair)
	_atualizar_toque(InputManager.device)
	InputManager.device_changed.connect(_atualizar_toque)

	client = GameClient.new()
	add_child(client)
	client.welcomed.connect(_on_welcome)
	client.rejected.connect(func(r): _falhar(r))
	client.disconnected.connect(func(): _falhar("Conexão com o servidor perdida."))
	client.snapshot_received.connect(_on_snapshot)
	client.player_info.connect(func(id, nome): _nomes[id] = nome)
	client.player_left.connect(_remover_remoto)
	client.status_received.connect(_on_status)
	client.shot_received.connect(_on_shot)
	client.hit_confirmed.connect(_on_hit)
	client.damaged.connect(func(_i): combat_hud.damage_flash())
	client.eliminated.connect(_on_elim)
	client.loot_spawned.connect(_on_loot)
	client.loot_removed.connect(_on_loot_gone)
	client.chest_changed.connect(_on_chest)

	var host: String = p.get("host", "127.0.0.1")
	var porta: int = p.get("porta", Protocol.DEFAULT_PORT)
	if modo == "local":
		porta = _subir_servidor_local()
		if porta == 0:
			_falhar("Não foi possível iniciar o servidor local.")
			return
		host = "127.0.0.1"
	var nome: String = Settings.get_value("network", "player_name")
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
	var mundo_srv := CampoTreino.new()
	mundo_srv.com_ambiente = false
	vp.add_child(mundo_srv)
	server = GameServer.new(mundo_srv)
	add_child(server)
	for porta in PORTAS_LOCAIS:
		if server.start(porta, "127.0.0.1") == OK:
			local_port = porta
			return porta
	return 0


func _on_welcome(info: Dictionary) -> void:
	pawn = Pawn.new()
	pawn.entity_id = info["id"]
	mundo.add_child(pawn)
	pawn.global_position = mundo.spawn_point(0)
	visual = PawnVisual.new()
	pawn.add_child(visual)
	camera.alvo = pawn
	hud.flash("Campo de treino" if modo == "local" else "Conectado", 2.5)
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
	for id in _remotos.keys():
		if not vistos.has(id):
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
		var v := PawnVisual.new()
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
	amostras.append({"tick": tick, "pos": e.position, "vel": e.velocity, "yaw": e.yaw, "flags": e.flags, "weapon": e.weapon})
	while amostras.size() > 20:
		amostras.pop_front()


func _remover_remoto(id: int) -> void:
	if _remotos.has(id):
		(_remotos[id]["visual"] as Node).queue_free()
		_remotos.erase(id)


func _process(delta: float) -> void:
	if pawn:
		var atual := combat_hud.current_item()
		visual.set_weapon(ItemDB.index_of(atual) if ItemDB.is_weapon(atual) else 0)
		visual.update_state(pawn.velocity, pawn.flags(), pawn.yaw)
		_atualizar_aviso()
	_interpolar_remotos()
	_info_t += delta
	if _info_t > 0.5:
		_info_t = 0.0
		hud.set_info(client.rtt_ms(), 1 + remote_player_count())


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
		var yaw := lerp_angle(anterior["yaw"], proxima["yaw"], t)
		r["boneco"] = proxima["flags"] & Protocol.F_DUMMY != 0
		v.visible = proxima["flags"] & Protocol.F_DEAD == 0
		v.set_weapon(proxima["weapon"])
		v.update_state(proxima["vel"], proxima["flags"], yaw)


# ---------- combate (cliente) ----------

func _on_status(st: Dictionary) -> void:
	_status = st
	combat_hud.update_status(st)
	sampler.selected = st["selected"]
	var atual: Dictionary = st["slots"][st["selected"]]
	_mag_local = atual["mag"]


func _prever_tiro(cmd: Protocol.InputCmd) -> void:
	if cmd.slot > 0:
		_fire_next_local = _seq + CombatServer.PASSOS_TROCA
	var id := combat_hud.current_item()
	var fogo := cmd.has(Protocol.BTN_FIRE)
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
	var espaco := pawn.get_world_3d().direct_space_state
	for d: Vector3 in Combat.pellet_dirs(raio["dir"], disp, int(w["projeteis"]), Combat.shot_seed(pawn.entity_id, cmd.seq)):
		var fim: Vector3 = raio["origin"] + d * float(w["alcance"])
		var q := PhysicsRayQueryParameters3D.create(raio["origin"], fim, Pawn.LAYER_WORLD)
		var r := espaco.intersect_ray(q)
		fx.tracer(raio["origin"] + d * 0.6, r["position"] if not r.is_empty() else fim)


func _on_shot(sh: Dictionary) -> void:
	for f in sh["ends"]:
		fx.tracer(sh["origin"], f["end"], f["hit"])


func _on_hit(h: Dictionary) -> void:
	hits_confirmed += 1
	var cabeca: bool = h["flags"] & Protocol.HIT_HEAD != 0
	combat_hud.hit_marker(cabeca)
	fx.damage_number(h["pos"], h["damage"], cabeca, h["flags"] & Protocol.HIT_SHIELD != 0)


func _on_elim(e: Dictionary) -> void:
	var vitima: String = _nomes.get(e["victim"], "?")
	var quem: String = _nomes.get(e["killer"], "?")
	var arma := ItemDB.id_of(e["weapon"])
	var texto := "%s saiu do mapa" % vitima if e["killer"] == e["victim"] or arma.is_empty() \
			else "%s eliminou %s (%s)" % [quem, vitima, ItemDB.def(arma).get("nome", "")]
	combat_hud.kill_feed(texto)
	if pawn and e["victim"] == pawn.entity_id:
		combat_hud.show_eliminated("Eliminado por %s\nReaparecendo…" % quem if e["killer"] != e["victim"] else "Você caiu!\nReaparecendo…")


func _set_morto(v: bool) -> void:
	if v == _morto:
		return
	_morto = v
	sampler.morto = v
	visual.visible = not v
	if not v:
		combat_hud.show_eliminated("")


func _on_loot(l: Dictionary) -> void:
	_on_loot_gone(l["id"])
	var v := LootVisual.new()
	mundo.add_child(v)
	v.setup(l)
	_loot[l["id"]] = v


func _on_loot_gone(id: int) -> void:
	if _loot.has(id):
		(_loot[id] as Node).queue_free()
		_loot.erase(id)


func _on_chest(i: int, aberto: bool) -> void:
	if i < 0 or i >= mundo.chest_nodes.size():
		return
	var aps := mundo.chest_nodes[i].find_children("*", "AnimationPlayer", true, false)
	if aberto:
		_baus_abertos[i] = true
		if not aps.is_empty():
			(aps[0] as AnimationPlayer).play("abrir")
	else:
		_baus_abertos.erase(i)
		if not aps.is_empty():
			(aps[0] as AnimationPlayer).stop()
			(aps[0] as AnimationPlayer).seek(0.0, true)


## Mostra o que dá para fazer perto do jogador (mesmas distâncias do servidor).
func _atualizar_aviso() -> void:
	if _morto:
		combat_hud.set_prompt("")
		return
	var pos := pawn.global_position
	var tecla := _nome_tecla("interact")
	for i in CampoTreino.CHESTS.size():
		if not _baus_abertos.has(i) and pos.distance_to(CampoTreino.CHESTS[i][0]) < LootServer.BAU_DIST:
			combat_hud.set_prompt("Segure %s: abrir baú" % tecla)
			return
	var melhor: LootVisual = null
	var dist := LootServer.PEGAR_DIST
	for v: LootVisual in _loot.values():
		if v.data["ammo"] == 0 and pos.distance_to(v.data["pos"]) < dist:
			dist = pos.distance_to(v.data["pos"])
			melhor = v
	combat_hud.set_prompt("%s: pegar %s" % [tecla, melhor.label()] if melhor else "")


func _nome_tecla(acao: String) -> String:
	match InputManager.device:
		"toque":
			return "Pegar"
		"controle":
			return "Y"
	var ev := InputManager.keyboard_events(acao)
	return InputSerializer.describe(ev[0]) if not ev.is_empty() else acao


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("pause") or (e.is_action_pressed("ui_cancel") and hud.is_paused()):
		_pausar(not hud.is_paused())
		get_viewport().set_input_as_handled()
	elif e is InputEventMouseButton and e.pressed and not hud.is_paused() and not Settings.is_mobile \
			and InputManager.device == "teclado_mouse" and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:   # botão voltar do Android
		_pausar(not hud.is_paused())
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT and not hud.is_paused() and pawn:
		_pausar(true)


func _pausar(v: bool) -> void:
	hud.show_pause(v)
	sampler.bloqueado = v
	camera.bloqueado = v
	var capturar := not v and not Settings.is_mobile and InputManager.device != "toque" and DisplayServer.get_name() != "headless"
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if capturar else Input.MOUSE_MODE_VISIBLE


func _atualizar_toque(d: String) -> void:
	touch.visible = d == "toque" or Settings.is_mobile


func _falhar(motivo: String) -> void:
	if _saindo:
		return
	Log.warn("partida", motivo)
	SceneManager.message = motivo
	_sair()


func _sair() -> void:
	if _saindo:
		return
	_saindo = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if client:
		client.close()
	if server:
		server.stop()
	SceneManager.go("menu")


func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if client:
		client.close()
	if server:
		server.stop()


## Outros jogadores (sem contar os bonecos de treino).
func remote_player_count() -> int:
	return _remotos.keys().filter(func(id): return id < GameServer.DUMMY_ID_BASE).size()


## Diagnóstico (testes): quantas vezes a predição errou mais de 5 cm.
func correction_count() -> int:
	return _correcoes
