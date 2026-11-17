class_name BotCerebro
extends RefCounted
## IA de um bot (Etapa 6). Roda no servidor e só produz ENTRADAS (InputCmd), como
## um jogador humano: o movimento, o combate, o inventário, a construção e o
## ônibus passam pelos mesmos sistemas autoritativos, sem atalhos.
##
## Decisão por "utility scoring" a 5 Hz (1 Hz longe de humanos = LOD de IA):
##   combater · curar · fugir da Tormenta · abrir baú · saquear · coletar · explorar
## Execução a cada tick: seguir o caminho (A* em NavGrade + desvio local + pulo
## quando trava), mirar com o erro da dificuldade, atirar, recarregar, curar.
## Percepção: cone de visão com raio de visibilidade (orçamento de raios por tick
## no servidor), audição de tiros e reação ao levar dano.

const SALTO_PERTO := 55.0

var server: GameServer
var c: GameServer.Cliente
var dif: Dictionary
var nome_dif := ""
var rng := RandomNumberGenerator.new()
var seq := 0
var estado := "explorar"
var alvo := Vector3.INF               # destino do movimento
var caminho := PackedVector2Array()
var idx := 0
var precisa_caminho := false
var inimigo := 0
var inimigo_pos := Vector3.ZERO
var visto_tick := -9999
var reagir_tick := 0                  # pode atirar a partir deste tick (tempo de reação)
var atacado_por := 0
var atacado_tick := -9999
var loot_alvo := 0
var bau_alvo := -1
var coleta_alvo := Vector3.INF
var ignorar := {}                     # loot/baús que não deram certo: id -> tick
var destino_salto := Vector3.INF
var _dist_onibus := 1e9
var _prox_decisao := 0
var _ultima_pos := Vector3.ZERO
var _parado := 0
var _construiu_tick := -9999
var _yaw := 0.0
var _pitch := 0.0
var _alterna := false
var _desvio := 0.0
var _segurar := 0                     # ticks segurando Interagir (baú)
var _tentando := 0                    # ticks perto do alvo de loot sem conseguir
var tempo_decisao_us := 0             # diagnóstico (custo de CPU)


func _init(s: GameServer, cli: GameServer.Cliente, dificuldade: String, semente: int) -> void:
	server = s
	c = cli
	var cfg := BotCerebro.config()
	nome_dif = dificuldade
	dif = cfg["dificuldades"][dificuldade]
	rng.seed = semente


static var _cfg := {}
static var _nomes: PackedStringArray = []


## Nomes de jogadores para os bots (data/nomes_jogadores.txt, um por linha).
static func nomes() -> PackedStringArray:
	if _nomes.is_empty():
		for l in FileAccess.get_file_as_string("res://data/nomes_jogadores.txt").split("\n"):
			if not l.strip_edges().is_empty():
				_nomes.append(l.strip_edges())
	return _nomes


static func config() -> Dictionary:
	if _cfg.is_empty():
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/bots.json"))
		_cfg = d if d is Dictionary else {}
	return _cfg


# ---------------- eventos do servidor ----------------

func on_damaged(atacante: int, pos_atacante: Vector3) -> void:
	atacado_por = atacante
	atacado_tick = server.tick
	if inimigo == 0 or inimigo == atacante:
		inimigo = atacante
		inimigo_pos = pos_atacante
		visto_tick = server.tick
		reagir_tick = maxi(reagir_tick, server.tick + roundi(float(dif["reacao_s"]) * 0.5 * Protocol.TICK_RATE))
	if dif["constroi"]:
		_construir_parede(pos_atacante)


func on_heard(atirador: int, pos: Vector3) -> void:
	if inimigo == 0 and atirador != c.id:
		inimigo = atirador
		inimigo_pos = pos
		visto_tick = server.tick - Protocol.TICK_RATE      # só ouviu: ainda precisa ver


# ---------------- tick ----------------

func pensar() -> Protocol.InputCmd:
	var cmd := Protocol.InputCmd.new()
	seq += 1
	cmd.seq = seq
	cmd.yaw = _yaw
	cmd.pitch = _pitch
	if c.dead or c.pawn == null:
		return cmd
	var t0 := Time.get_ticks_usec()
	match c.pawn.queda:
		Pawn.NO_ONIBUS:
			_no_onibus(cmd)
		Pawn.QUEDA_LIVRE, Pawn.PLANADOR:
			_caindo(cmd)
		_:
			if server.tick >= _prox_decisao:
				_decidir()
				var hz := float(BotCerebro.config()["decisao_hz"]) if _perto_de_humano() else float(BotCerebro.config()["decisao_longe_hz"])
				_prox_decisao = server.tick + maxi(1, roundi(Protocol.TICK_RATE / hz)) + rng.randi_range(0, 2)
			_executar(cmd)
	tempo_decisao_us += Time.get_ticks_usec() - t0
	_yaw = cmd.yaw
	_pitch = cmd.pitch
	return cmd


func _perto_de_humano() -> bool:
	var d := float(BotCerebro.config()["lod_distancia_m"])
	for o: GameServer.Cliente in server.clientes.values():
		if o.bot == null and o.pawn and not o.dead and o.pawn.global_position.distance_to(c.pawn.global_position) < d:
			return true
	return false


# ---------------- ônibus e queda ----------------

func _no_onibus(cmd: Protocol.InputCmd) -> void:
	var p := server.partida
	if p == null or p.onibus == null:
		return
	if destino_salto == Vector3.INF:
		destino_salto = _escolher_destino_salto()
	if not p.onibus.doors_open(server.tick):
		return
	var pos := p.onibus.position_at(server.tick)
	var d := Vector2(pos.x - destino_salto.x, pos.z - destino_salto.z).length()
	# salta perto do destino, ou quando o ônibus começa a se afastar dele
	var afastando := d > _dist_onibus + 0.5
	_dist_onibus = minf(_dist_onibus, d)
	if d < SALTO_PERTO * (1.0 + float(dif["salto_cedo"])) or (afastando and rng.randf() < 0.08):
		cmd.buttons |= Protocol.BTN_JUMP


func _escolher_destino_salto() -> Vector3:
	var mapa := server.world
	var pois := mapa.points_of_interest()
	var r := rng.randf()
	if not pois.is_empty() and r < 0.65:
		var poi: Dictionary = pois[rng.randi() % pois.size()]
		var off := Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * float(poi["raio"]) * 0.6
		return poi["pos"] + Vector3(off.x, 0, off.y)
	var baus := mapa.chests()
	if not baus.is_empty():
		return baus[rng.randi() % baus.size()][0]
	return Vector3.ZERO


func _caindo(cmd: Protocol.InputCmd) -> void:
	if destino_salto == Vector3.INF:
		destino_salto = _escolher_destino_salto()
	var d := destino_salto - c.pawn.global_position
	cmd.yaw = atan2(-d.x, -d.z)
	cmd.move = Vector2(0, 1) if Vector2(d.x, d.z).length() > 6.0 else Vector2.ZERO


# ---------------- decisão (utility scoring) ----------------

func _decidir() -> void:
	_perceber()
	var arma := _melhor_arma(inimigo_pos.distance_to(c.pawn.global_position) if inimigo else 30.0)
	var vida := c.vit.health + c.vit.shield
	var notas := {}
	var visivel := inimigo != 0 and server.tick - visto_tick < Protocol.TICK_RATE * 2
	var dist_ini := c.pawn.global_position.distance_to(inimigo_pos) if inimigo else 1e9
	if visivel and arma >= 0 and dist_ini < float(dif["engaja_m"]):
		notas["combater"] = 0.85 + (0.1 if server.tick - atacado_tick < 60 else 0.0)
	elif visivel and arma < 0 and dist_ini < 4.0:
		notas["combater"] = 0.7                   # picareta
	if vida < float(dif["cura_abaixo"]) and _consumivel_util() >= 0 and not (visivel and dist_ini < 22.0):
		notas["curar"] = 0.8 - vida / 400.0
	var t := _urgencia_tormenta()
	if t > 0.0:
		notas["tormenta"] = 0.45 + t * 0.55
	if arma < 0 or c.inv.free_count() >= 2:
		var l := _loot_perto()
		if l != 0:
			loot_alvo = l
			notas["saquear"] = 0.75 if arma < 0 else 0.5
		var b := _bau_perto()
		if b >= 0:
			bau_alvo = b
			notas["bau"] = 0.62 if arma < 0 else 0.52
	if dif["coleta"] and int(c.inv.materials.get("madeira", 0)) < 60 and not visivel:
		notas["coletar"] = 0.25
	notas["explorar"] = 0.2
	var melhor := "explorar"
	for k in notas:
		if notas[k] > notas[melhor]:
			melhor = k
	if melhor != estado:
		estado = melhor
		alvo = Vector3.INF
		_segurar = 0
		_tentando = 0
	_definir_alvo()


func _perceber() -> void:
	var meu := c.pawn.global_position
	var olho := meu + Vector3(0, Combat.EYE_STAND, 0)
	var frente := Vector3(-sin(_yaw), 0, -cos(_yaw))
	var melhor := 0
	var melhor_d := float(dif["alcance_visao_m"])
	var melhor_pos := Vector3.ZERO
	for o: GameServer.Cliente in server.clientes.values():
		if o == c or o.pawn == null or o.dead or o.pawn.queda == Pawn.NO_ONIBUS:
			continue
		var p := o.pawn.global_position
		var d := meu.distance_to(p)
		if d > melhor_d:
			continue
		var dir := (p - meu)
		dir.y = 0.0
		var ang := rad_to_deg(frente.angle_to(dir.normalized())) if dir.length() > 0.1 else 0.0
		if ang > float(dif["campo_visao_graus"]) * 0.5 and d > 6.0 and o.id != atacado_por:
			continue
		if server.bot_raios <= 0:
			break
		server.bot_raios -= 1
		var q := PhysicsRayQueryParameters3D.create(olho, p + Vector3(0, 1.2, 0), Pawn.LAYER_WORLD)
		if not server.world.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
			continue
		melhor = o.id
		melhor_d = d
		melhor_pos = p
	if melhor != 0:
		if melhor != inimigo or server.tick - visto_tick > Protocol.TICK_RATE * 2:
			reagir_tick = server.tick + roundi(float(dif["reacao_s"]) * Protocol.TICK_RATE)
		inimigo = melhor
		inimigo_pos = melhor_pos
		visto_tick = server.tick
	elif inimigo != 0 and server.tick - visto_tick > Protocol.TICK_RATE * 6:
		inimigo = 0
	if inimigo != 0:
		var o := server.client_by_id(inimigo)
		if o == null or o.dead:
			inimigo = 0


func _definir_alvo() -> void:
	match estado:
		"combater":
			alvo = inimigo_pos
		"saquear":
			var l: Dictionary = server.loot.loot.get(loot_alvo, {})
			alvo = l["pos"] if not l.is_empty() else Vector3.INF
		"bau":
			alvo = server.loot.chests[bau_alvo]["pos"] if bau_alvo >= 0 else Vector3.INF
		"tormenta":
			var z := _zona_segura()
			var off := Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * float(z[1]) * 0.35
			alvo = Vector3(z[0].x + off.x, 0, z[0].y + off.y)
		"coletar":
			if coleta_alvo == Vector3.INF or c.pawn.global_position.distance_to(coleta_alvo) > 60.0:
				coleta_alvo = _arvore_perto()
			alvo = coleta_alvo
		"explorar":
			if alvo == Vector3.INF or c.pawn.global_position.distance_to(alvo) < 6.0:
				alvo = _ponto_explorar()
		_:
			alvo = Vector3.INF
	if alvo != Vector3.INF:
		alvo.y = server.world.ground_height(alvo.x, alvo.z)
		precisa_caminho = true


# ---------------- execução ----------------

func _executar(cmd: Protocol.InputCmd) -> void:
	_alterna = not _alterna
	var pos := c.pawn.global_position
	match estado:
		"combater":
			_combater(cmd)
			return
		"curar":
			_curar(cmd)
			return
		"saquear":
			var l: Dictionary = server.loot.loot.get(loot_alvo, {})
			if l.is_empty():
				_prox_decisao = server.tick
				return
			if Vector2(pos.x - l["pos"].x, pos.z - l["pos"].z).length() < 1.7:
				_tentando += 1
				if _tentando > 45:
					ignorar[loot_alvo] = server.tick
					_prox_decisao = server.tick
				if _alterna:
					cmd.buttons |= Protocol.BTN_INTERACT
				return
		"bau":
			if bau_alvo < 0 or server.loot.chests[bau_alvo]["open"]:
				_prox_decisao = server.tick
				return
			if pos.distance_to(server.loot.chests[bau_alvo]["pos"]) < LootServer.BAU_DIST - 0.5:
				cmd.buttons |= Protocol.BTN_INTERACT
				_segurar += 1
				if _segurar > LootServer.ABRIR_BAU_PASSOS * 3:
					ignorar["bau%d" % bau_alvo] = server.tick
					_prox_decisao = server.tick
				return
		"coletar":
			if coleta_alvo != Vector3.INF and Vector2(pos.x - coleta_alvo.x, pos.z - coleta_alvo.z).length() < 2.2:
				if not c.inv.pickaxe_selected():
					cmd.slot = Protocol.SLOT_PICKAXE
				var d := coleta_alvo + Vector3(0, 1.0, 0) - (pos + Vector3(0, Combat.EYE_STAND, 0))
				_mirar_direto(cmd, coleta_alvo + Vector3(0, 1.0, 0), 0.0)
				cmd.buttons |= Protocol.BTN_FIRE
				_tentando += 1
				if _tentando > Combat.melee_swing_steps() * 6 or d.length() > 4.0:
					coleta_alvo = Vector3.INF
					_tentando = 0
					_prox_decisao = server.tick
				return
	_andar(cmd, true)


func _andar(cmd: Protocol.InputCmd, correr: bool) -> void:
	if alvo == Vector3.INF:
		return
	var pos := c.pawn.global_position
	if precisa_caminho and server.bot_planejamentos > 0:
		server.bot_planejamentos -= 1
		precisa_caminho = false
		caminho = server.nav.path(Vector2(pos.x, pos.z), Vector2(alvo.x, alvo.z)) if server.nav else PackedVector2Array()
		idx = 0
	var prox := Vector2(alvo.x, alvo.z)
	if idx < caminho.size():
		prox = caminho[idx]
		if Vector2(pos.x, pos.z).distance_to(prox) < 2.2:
			idx += 1
	var d := Vector2(prox.x - pos.x, prox.y - pos.z)
	if d.length() < 0.6 and idx >= caminho.size():
		return
	cmd.yaw = atan2(-d.x, -d.y) + _desvio
	cmd.pitch = 0.0
	cmd.move = Vector2(0, 1)
	if correr:
		cmd.buttons |= Protocol.BTN_SPRINT
	# desvio local de árvores, postes etc. e pulo quando trava
	if server.tick % 4 == (c.id % 4) and server.bot_raios > 0:
		server.bot_raios -= 1
		var frente := Vector3(-sin(cmd.yaw), 0, -cos(cmd.yaw))
		var q := PhysicsRayQueryParameters3D.create(pos + Vector3(0, 0.8, 0), pos + Vector3(0, 0.8, 0) + frente * 1.8, Pawn.LAYER_WORLD)
		if not server.world.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
			_desvio = clampf(_desvio + (0.6 if (c.id % 2) == 0 else -0.6), -1.4, 1.4)
		else:
			_desvio = move_toward(_desvio, 0.0, 0.2)
	if pos.distance_to(_ultima_pos) < 0.05:
		_parado += 1
	else:
		_parado = 0
	_ultima_pos = pos
	if _parado > 12:
		cmd.buttons |= Protocol.BTN_JUMP
		cmd.move = Vector2(1 if (c.id + server.tick / 30) % 2 == 0 else -1, 1).normalized()
	if _parado > 75:
		precisa_caminho = true
		_parado = 0
		if estado == "explorar" or estado == "coletar":
			alvo = Vector3.INF
			coleta_alvo = Vector3.INF
			_prox_decisao = server.tick


func _combater(cmd: Protocol.InputCmd) -> void:
	var o := server.client_by_id(inimigo)
	if o == null or o.dead:
		inimigo = 0
		_prox_decisao = server.tick
		return
	var alvo_p := o.pawn.global_position + Vector3(0, 1.15, 0)
	var dist := c.pawn.global_position.distance_to(o.pawn.global_position)
	var arma := _melhor_arma(dist)
	if arma < 0:
		# sem arma: picareta de perto, senão foge para saquear
		if dist > 3.0:
			alvo = o.pawn.global_position
			_andar(cmd, true)
			return
		if not c.inv.pickaxe_selected():
			cmd.slot = Protocol.SLOT_PICKAXE
		_mirar_direto(cmd, alvo_p, float(dif["erro_mira_graus"]))
		cmd.move = Vector2(0, 0.6)
		cmd.buttons |= Protocol.BTN_FIRE
		return
	if c.inv.selected != arma:
		cmd.slot = arma + 1
		return
	var s := c.inv.current()
	var w := ItemDB.weapon(s.item)
	_mirar_direto(cmd, alvo_p, float(dif["erro_mira_graus"]) * (1.0 + clampf(o.pawn.velocity.length() / 6.0, 0.0, 1.0)))
	# movimento lateral (strafe) e distância de combate
	cmd.move = Vector2(sin(server.tick * 0.07 + c.id) * 0.8, 0.5 if dist > float(w["alcance"]) * 0.5 else (-0.3 if dist < 5.0 else 0.0))
	if s.mag <= 0:
		if _alterna:
			cmd.buttons |= Protocol.BTN_RELOAD
		return
	if server.tick < reagir_tick:
		return
	if w["automatica"] or _alterna:
		cmd.buttons |= Protocol.BTN_FIRE
	if dist > 18.0 and ItemDB.weapon(s.item).has("dispersao_mirando"):
		cmd.buttons |= Protocol.BTN_AIM


func _mirar_direto(cmd: Protocol.InputCmd, ponto: Vector3, erro_graus: float) -> void:
	var pos := c.pawn.global_position
	var d := ponto - (pos + Vector3(0, Combat.EYE_STAND, 0))
	var yaw := atan2(-d.x, -d.z)
	var pitch := atan2(d.y, Vector2(d.x, d.z).length())
	var r := Combat.aim_ray(pos, c.pawn.crouched, yaw, pitch)
	d = ponto - (r["origin"] as Vector3)                  # corrige o ombro
	var e := deg_to_rad(erro_graus)
	cmd.yaw = atan2(-d.x, -d.z) + rng.randf_range(-e, e)
	cmd.pitch = atan2(d.y, Vector2(d.x, d.z).length()) + rng.randf_range(-e, e) * 0.6


func _curar(cmd: Protocol.InputCmd) -> void:
	var k := _consumivel_util()
	if k < 0:
		_prox_decisao = server.tick
		return
	if c.inv.selected != k:
		cmd.slot = k + 1
		return
	cmd.buttons |= Protocol.BTN_FIRE      # segura até terminar de usar


# ---------------- apoio ----------------

## Melhor espaço de arma com munição para a distância (-1 = nenhuma).
func _melhor_arma(dist: float) -> int:
	var melhor := -1
	var nota := -1.0
	for i in Inventory.SLOTS:
		var s := c.inv.slots[i]
		if not ItemDB.is_weapon(s.item):
			continue
		var w := ItemDB.weapon(s.item)
		if s.mag <= 0 and int(c.inv.ammo[w["municao"]]) <= 0:
			continue
		var n := 1.0 + s.rarity * 0.1
		match s.item:
			"trovao":
				n += 1.5 if dist < 12.0 else -1.0
			"zumbido":
				n += 0.8 if dist < 25.0 else -0.4
			"rajada":
				n += 0.8 if dist >= 10.0 and dist < 70.0 else 0.2
			"gaviao":
				n += 1.4 if dist > 45.0 else -0.8
		if n > nota:
			nota = n
			melhor = i
	return melhor


## Espaço de consumível útil agora (vida ou escudo) ou -1.
func _consumivel_util() -> int:
	for i in Inventory.SLOTS:
		var s := c.inv.slots[i]
		if not ItemDB.is_consumable(s.item):
			continue
		var d := ItemDB.consumable(s.item)
		if d.has("vida") and c.vit.health < int(d["limite"]):
			return i
		if d.has("escudo") and c.vit.shield < int(d["limite"]):
			return i
	return -1


func _cabe(item: String) -> bool:
	return c.inv.room_for(item) > 0


func _loot_perto() -> int:
	var pos := c.pawn.global_position
	var melhor := 0
	var dist := 70.0
	var sem_arma := _melhor_arma(30.0) < 0
	for l in server.loot.loot.values():
		if LootServer.is_reserve(l) or ignorar.has(l["id"]):
			continue
		var id := ItemDB.id_of(l["item"])
		if not _cabe(id) or absf(l["pos"].y - server.world.ground_height(l["pos"].x, l["pos"].z)) > 2.5:
			continue
		var d := pos.distance_to(l["pos"]) * (0.6 if sem_arma and ItemDB.is_weapon(id) else 1.0)
		if d < dist:
			dist = d
			melhor = l["id"]
	return melhor


func _bau_perto() -> int:
	var pos := c.pawn.global_position
	var melhor := -1
	var dist := 80.0
	for i in server.loot.chests.size():
		var b: Dictionary = server.loot.chests[i]
		if b["open"] or ignorar.has("bau%d" % i):
			continue
		if absf(b["pos"].y - server.world.ground_height(b["pos"].x, b["pos"].z)) > 2.5:
			continue
		var d := pos.distance_to(b["pos"])
		if d < dist:
			dist = d
			melhor = i
	return melhor


## [centro Vector2, raio] da zona que importa agora (a próxima se já está fechando
## ou falta pouco; senão a atual).
func _zona_segura() -> Array:
	var p := server.partida
	if p == null or p.tormenta == null:
		return [Vector2.ZERO, 1e6]
	var t := p.tormenta
	if t.fechando or t.ticks_left() < Protocol.TICK_RATE * 25 or t.terminou:
		return [t.c_para, t.r_para]
	return t.current()


## 0 (seguro) .. 1 (urgente): fora da zona que importa, pior com pouco tempo e mais dano.
func _urgencia_tormenta() -> float:
	var z := _zona_segura()
	var pos := c.pawn.global_position
	var fora := Vector2(pos.x, pos.z).distance_to(z[0]) - float(z[1]) * 0.85
	if fora <= 0.0:
		return 0.0
	var p := server.partida
	var dentro_agora := p and p.tormenta and not p.tormenta.is_outside(pos)
	return clampf(0.35 + fora / 120.0 + (0.0 if dentro_agora else 0.4), 0.0, 1.0)


func _arvore_perto() -> Vector3:
	var mapa := server.world
	if not mapa.has_method("harvest_points"):
		return Vector3.INF
	var pos := c.pawn.global_position
	var melhor := Vector3.INF
	var dist := 60.0
	for p: Vector3 in mapa.harvest_points():
		var d := pos.distance_to(p)
		if d < dist:
			dist = d
			melhor = p
	return melhor


func _ponto_explorar() -> Vector3:
	var z := _zona_segura()
	var mapa := server.world
	for i in 12:
		var ang := rng.randf() * TAU
		var r := sqrt(rng.randf()) * minf(float(z[1]), 160.0) * 0.8
		var q: Vector2 = z[0] + Vector2(cos(ang), sin(ang)) * r
		if mapa.ground_height(q.x, q.y) > 1.0:
			return Vector3(q.x, 0, q.y)
	return Vector3(z[0].x, 0, z[0].y)


## Difícil: ao levar tiro, levanta uma parede na direção do atacante.
func _construir_parede(de: Vector3) -> void:
	if server.tick - _construiu_tick < Protocol.TICK_RATE * 3:
		return
	var mat := -1
	for i in 3:
		if int(c.inv.materials.get(Grade.MATERIAIS[i], 0)) >= 10:
			mat = i
	if mat < 0:
		return
	var d := de - c.pawn.global_position
	var alvo_g := Grade.target(0, c.pawn.global_position, atan2(-d.x, -d.z), 0.0)
	if server.build.try_build(c, {"escolha": 0, "material": mat, "cell": alvo_g["cell"], "rot": alvo_g["rot"]}) == Inventory.Err.OK:
		_construiu_tick = server.tick
		c.stats["construcoes"] = int(c.stats.get("construcoes", 0)) + 1
