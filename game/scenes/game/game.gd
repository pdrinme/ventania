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
var touch: TouchControls

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
	hud = GameHud.new()
	hud.theme = tema
	camada.add_child(hud)
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
	Movement.step(pawn, cmd, dt)
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
		_remotos[e.id] = {"visual": v, "amostras": []}
	var amostras: Array = _remotos[e.id]["amostras"]
	amostras.append({"tick": tick, "pos": e.position, "vel": e.velocity, "yaw": e.yaw, "flags": e.flags})
	while amostras.size() > 20:
		amostras.pop_front()


func _remover_remoto(id: int) -> void:
	if _remotos.has(id):
		(_remotos[id]["visual"] as Node).queue_free()
		_remotos.erase(id)


func _process(delta: float) -> void:
	if pawn:
		visual.update_state(pawn.velocity, pawn.flags(), pawn.yaw)
	_interpolar_remotos()
	_info_t += delta
	if _info_t > 0.5:
		_info_t = 0.0
		hud.set_info(client.rtt_ms(), 1 + _remotos.size())


func _interpolar_remotos() -> void:
	if _ultimo_tick == 0:
		return
	var agora := Time.get_ticks_msec() / 1000.0
	var tick_render := _ultimo_tick + (agora - _ultimo_tick_t) * Protocol.TICK_RATE - ATRASO_INTERP_TICKS
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
		v.global_position = (anterior["pos"] as Vector3).lerp(proxima["pos"], t)
		var yaw := lerp_angle(anterior["yaw"], proxima["yaw"], t)
		v.update_state(proxima["vel"], proxima["flags"], yaw)


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


## Diagnóstico (testes): quantas vezes a predição errou mais de 5 cm.
func correction_count() -> int:
	return _correcoes
