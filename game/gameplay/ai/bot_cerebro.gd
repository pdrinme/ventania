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
var caminho := PackedVector3Array()
var precisos := PackedByteArray()
var nos_caminho := PackedInt32Array()
var idx := 0
var _evitar := {}                     # arestas da navegação onde este bot travou -> tick até quando evitar
var _manobra := 0                     # ticks restantes da manobra de destravar
var _manobra_lado := 1.0
var _recuperacoes := 0                # recuperações no alvo atual
var _sem_caminho := 0
var _prog_idx := -1
var memoria_pos := Vector3.INF        # última posição conhecida do inimigo (vista ou de onde veio o tiro)
var memoria_tick := -9999
var ouviu_pos := Vector3.INF          # tiro ouvido (para investigar; não revela quem atirou)
var ouviu_tick := -9999
var _visada_ini := 0                  # desde quando vê o inimigo atual (a mira assenta)
var _cobertura_ate := 0
var _cobertura_ponto := Vector3.INF
var _cobertura_sorteio := 0.5         # sorteio por troca de tiros (dif["usa_cobertura"])
var _observar := 0                    # ticks olhando em volta (chegou onde investigava)
var _yaw_disparo := 0.0
var _rajada := 0                      # ticks na rajada atual (+) ou na pausa (-)
var _recuar_ate := 0
var _visitados := {}                  # cômodos já explorados (índice -> tick)
var _alvo_rota := Vector3.INF         # destino da rota atual
var _alvo_3d := false                 # alvo com altura própria (andar de cima): não projeta no relevo
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
var ordem := Vector3.INF              # testes de navegação: destino fixo (ignora as decisões)
var _dist_onibus := 1e9
var _prox_decisao := 0
var _ultima_pos := Vector3.ZERO
var _parado := 0
var _prog_tick := 0
var _prog_dist := 1e9
var _sem_progresso := 0                # segundos seguidos sem se aproximar do alvo
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
	# quem leva tiro sabe de onde veio (direção do disparo): reage, mas ainda precisa
	# VER o atacante para mirar com precisão (a mira assenta com o tempo de visada)
	atacado_por = atacante
	atacado_tick = server.tick
	memoria_pos = pos_atacante
	memoria_tick = server.tick
	if inimigo == 0 or inimigo == atacante:
		inimigo = atacante
		inimigo_pos = pos_atacante
		visto_tick = server.tick - Protocol.TICK_RATE      # ainda não viu: só sabe a direção
		reagir_tick = maxi(reagir_tick, server.tick + roundi(float(dif["reacao_s"]) * 0.5 * Protocol.TICK_RATE))
	if server.tick >= _prox_decisao + 2:
		_prox_decisao = server.tick                          # reavalia na hora
	if dif["constroi"]:
		_construir_parede(pos_atacante)


func on_heard(atirador: int, pos: Vector3) -> void:
	# ouvir um tiro NÃO revela o atirador: só um ponto para investigar
	if atirador == c.id or rng.randf() > float(dif.get("investiga", 0.7)):
		return
	ouviu_pos = pos
	ouviu_tick = server.tick


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
			if ordem != Vector3.INF:             # testes: vai até um ponto, sem outras decisões
				if estado != "ordem" or alvo != ordem:
					estado = "ordem"
					alvo = ordem
					precisa_caminho = true
				_andar(cmd, true)
			elif server.tick >= _prox_decisao:
				_decidir()
				var hz := float(dif.get("decisao_hz", BotCerebro.config()["decisao_hz"])) if _perto_de_humano() else float(BotCerebro.config()["decisao_longe_hz"])
				_prox_decisao = server.tick + maxi(1, roundi(Protocol.TICK_RATE / hz)) + rng.randi_range(0, 2)
				_executar(cmd)
			else:
				_executar(cmd)
	if c.pawn.queda == 0 and server.tick % Protocol.TICK_RATE == c.id % Protocol.TICK_RATE:
		var p := c.pawn.global_position
		if p.y - server.world.ground_height(p.x, p.z) > 3.0 and c.pawn.grounded:
			GameServer.add_stat(c, "andar_cima_s")          # diagnóstico: tempo em andares de cima
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
	var pos := c.pawn.global_position
	var visivel := inimigo != 0 and server.tick - visto_tick < Protocol.TICK_RATE * 1.5
	var dist_ini := pos.distance_to(inimigo_pos) if inimigo else 1e9
	var arma := _melhor_arma(dist_ini if inimigo else 30.0)
	var vida := c.vit.health + c.vit.shield
	var atacado := server.tick - atacado_tick < Protocol.TICK_RATE * 2
	var notas := {}
	if visivel:
		if arma >= 0 and dist_ini < float(dif["engaja_m"]):
			notas["combater"] = 0.85 + (0.1 if atacado else 0.0)
		elif arma < 0 and dist_ini < 5.0:
			notas["combater"] = 0.7                           # picareta, de perto
		elif arma < 0:
			notas["recuar"] = 0.75                            # sem arma: foge e procura loot
		# cobertura: sob fogo ou recarregando, se a dificuldade sabe usar
		var recarga := arma >= 0 and c.inv.slots[arma].mag <= int(ItemDB.weapon(c.inv.slots[arma].item)["pente"]) / 4
		if arma >= 0 and (atacado or recarga) and _cobertura_sorteio < float(dif.get("usa_cobertura", 0.0)) and vida < float(dif.get("cobertura_vida", 200)):
			notas["cobertura"] = 0.9 if estado != "cobertura" or server.tick < _cobertura_ate else 0.0
		# recua em desvantagem (pouca vida, levando tiro)
		if vida < float(dif.get("recua_vida", 0)) and atacado and dist_ini < 35.0:
			notas["recuar"] = 0.93
	elif memoria_pos != Vector3.INF and arma >= 0 and server.tick - memoria_tick < float(dif.get("memoria_s", 5.0)) * Protocol.TICK_RATE:
		notas["perseguir"] = 0.55 + (0.15 if atacado else 0.0)   # vai até a última posição conhecida
	if not visivel and ouviu_pos != Vector3.INF and arma >= 0 and server.tick - ouviu_tick < Protocol.TICK_RATE * 12:
		notas["investigar"] = 0.42
	var util := _consumivel_util()
	if vida < float(dif["cura_abaixo"]) and util >= 0 and not (visivel and dist_ini < 22.0):
		notas["curar"] = 0.8 - vida / 400.0 + (0.12 if estado == "cobertura" else 0.0)
	var t := _urgencia_tormenta()
	if t > 0.0:
		notas["tormenta"] = 0.45 + t * 0.55
	if arma < 0 or c.inv.free_count() >= 1:
		var l := _loot_perto()
		if l != 0:
			loot_alvo = l
			notas["saquear"] = 0.75 if arma < 0 else 0.4 + 0.1 * minf(_valor_loot(server.loot.loot[l]), 2.0)
		var b := _bau_perto()
		if b >= 0:
			bau_alvo = b
			notas["bau"] = 0.62 if arma < 0 else 0.52
	if dif["coleta"] and int(c.inv.materials.get("madeira", 0)) < 60 and not visivel:
		notas["coletar"] = 0.25
	notas["explorar"] = 0.2
	# inércia: o estado atual ganha um pouco (evita trocar de ideia a cada decisão);
	# recuar tem compromisso mínimo de tempo
	if notas.has(estado):
		notas[estado] += 0.08
	if estado == "recuar" and server.tick < _recuar_ate:
		notas["recuar"] = maxf(float(notas.get("recuar", 0.0)), 0.95)
	var melhor := "explorar"
	for k in notas:
		if notas[k] > notas[melhor]:
			melhor = k
	if melhor != estado:
		if melhor == "recuar":
			_recuar_ate = server.tick + roundi(Protocol.TICK_RATE * 2.5)
		if melhor == "cobertura":
			_cobertura_ate = server.tick + roundi(Protocol.TICK_RATE * rng.randf_range(1.5, 3.0))
			_cobertura_ponto = Vector3.INF
		if estado == "cobertura" or melhor == "combater":
			_cobertura_sorteio = rng.randf()                 # nova chance na próxima troca de tiros
		estado = melhor
		GameServer.add_stat(c, "estado_" + melhor)            # diagnóstico: comportamentos usados
		alvo = Vector3.INF
		_segurar = 0
		_tentando = 0
		_recuperacoes = 0
		_observar = 0
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
			_visada_ini = server.tick                         # a mira começa a assentar agora
		inimigo = melhor
		inimigo_pos = melhor_pos
		visto_tick = server.tick
		memoria_pos = melhor_pos                              # memória: última posição VISTA
		memoria_tick = server.tick
		ouviu_pos = Vector3.INF
	elif inimigo != 0 and server.tick - visto_tick > float(dif.get("memoria_s", 5.0)) * Protocol.TICK_RATE:
		inimigo = 0                                           # esqueceu
	if inimigo != 0:
		var o := server.client_by_id(inimigo)
		if o == null or o.dead:
			inimigo = 0


func _definir_alvo() -> void:
	_alvo_3d = estado in ["combater", "saquear", "bau", "perseguir", "investigar", "cobertura", "ordem", "explorar"]
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
			if alvo == Vector3.INF or Vector2(alvo.x, alvo.z).distance_to(z[0]) > float(z[1]) * 0.6:
				var off := Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * float(z[1]) * 0.35
				alvo = Vector3(z[0].x + off.x, 0, z[0].y + off.y)
		"coletar":
			if coleta_alvo == Vector3.INF or c.pawn.global_position.distance_to(coleta_alvo) > 60.0:
				coleta_alvo = _arvore_perto()
			alvo = coleta_alvo
		"explorar":
			if alvo == Vector3.INF or c.pawn.global_position.distance_to(alvo) < 3.0:
				alvo = _ponto_explorar()
		"perseguir":
			alvo = memoria_pos
		"investigar":
			alvo = ouviu_pos
		"cobertura":
			if _cobertura_ponto == Vector3.INF:
				_cobertura_ponto = _achar_cobertura()
			alvo = _cobertura_ponto
		"recuar":
			var fuga := c.pawn.global_position - inimigo_pos
			fuga.y = 0.0
			var z := _zona_segura()
			var dz := Vector3(z[0].x, 0, z[0].y) - c.pawn.global_position
			dz.y = 0.0
			var dir := (fuga.normalized() * 0.7 + dz.normalized() * 0.3).normalized() if fuga.length() > 0.1 else dz.normalized()
			for k in 6:
				var q := c.pawn.global_position + dir.rotated(Vector3.UP, (k / 2) * 0.6 * (1 if k % 2 == 0 else -1)) * 18.0
				if server.world.ground_height(q.x, q.z) > 0.8:
					alvo = q
					break
		_:
			alvo = Vector3.INF
	if alvo != Vector3.INF:
		if not _alvo_3d:
			alvo.y = server.world.ground_height(alvo.x, alvo.z)
		# só recalcula a rota se o destino mudou de verdade (senão o monitor de
		# progresso nunca enxergaria o bot travado e o A* rodaria à toa)
		if caminho.is_empty() or _alvo_rota == Vector3.INF or _alvo_rota.distance_to(alvo) > 3.0:
			precisa_caminho = true
			_alvo_rota = alvo


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
		"cobertura":
			# chegou na cobertura: recarrega/cura; quem sabe atirar andando revida no caminho
			if _cobertura_ponto != Vector3.INF and Vector2(pos.x - _cobertura_ponto.x, pos.z - _cobertura_ponto.z).length() < 0.9:
				_na_cobertura(cmd)
				return
			if dif.get("atira_andando", false) and inimigo != 0 and server.tick - visto_tick < 10:
				_disparar(cmd, true)
		"recuar":
			_andar(cmd, true)
			if dif.get("atira_andando", false) and inimigo != 0 and server.tick - visto_tick < 10:
				_disparar(cmd, false)
				cmd.yaw = _yaw_disparo
			return
		"perseguir", "investigar":
			var ponto := memoria_pos if estado == "perseguir" else ouviu_pos
			if ponto == Vector3.INF or Vector2(pos.x - ponto.x, pos.z - ponto.z).length() < 1.5 or _observar > 0:
				_olhar_em_volta(cmd)
				return
			_andar(cmd, true)
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
	if precisa_caminho and server.bot_planejamentos > 0 and server.nav:
		server.bot_planejamentos -= 1
		precisa_caminho = false
		_limpar_evitar()
		var r: Dictionary = server.nav.path3(pos, alvo, _evitar)
		caminho = r["pontos"]
		precisos = r["precisos"]
		nos_caminho = r["nos"]
		idx = 0
		_prog_dist = 1e9
		_prog_idx = -1
		if caminho.is_empty():
			if estado in ["explorar", "tormenta", "recuar", "cobertura", "coletar"]:
				# destino de movimento sem rota (água, área fechada): escolhe outro, sem "abandono"
				GameServer.add_stat(c, "sem_rota")
				alvo = Vector3.INF
				_alvo_rota = Vector3.INF
				_cobertura_ponto = Vector3.INF
				_prox_decisao = server.tick
				return
			_sem_caminho += 1
			if _sem_caminho >= 2:
				_abandonar_alvo("sem caminho")
				return
		else:
			_sem_caminho = 0
	# avança os pontos de passagem (porta/escada/rampa: só bem perto)
	var prox := alvo
	while idx < caminho.size():
		prox = caminho[idx]
		var raio := 0.7 if precisos[idx] != 0 else 1.7
		if Vector2(prox.x - pos.x, prox.z - pos.z).length() < raio and absf(prox.y - pos.y) < 1.9:
			idx += 1
			continue
		break
	if idx >= caminho.size():
		prox = alvo
	var d := Vector2(prox.x - pos.x, prox.z - pos.z)
	if idx >= caminho.size() and d.length() < 0.6 and absf(alvo.y - pos.y) < 1.9:
		_sem_progresso = 0
		return                                   # chegou: esperar/observar não é estar preso
	cmd.yaw = atan2(-d.x, -d.y) + _desvio
	cmd.pitch = 0.0
	cmd.move = Vector2(0, 1)
	if correr:
		cmd.buttons |= Protocol.BTN_SPRINT
	# desvio local de árvores, postes, mobília (perto de porta/escada vai reto)
	var preciso := idx < precisos.size() and precisos[idx] != 0
	if server.tick % 4 == (c.id % 4) and server.bot_raios > 0:
		server.bot_raios -= 1
		var frente := Vector3(-sin(cmd.yaw), 0, -cos(cmd.yaw))
		var q := PhysicsRayQueryParameters3D.create(pos + Vector3(0, 0.8, 0), pos + Vector3(0, 0.8, 0) + frente * 1.8, Pawn.LAYER_WORLD)
		if not preciso and not server.world.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
			_desvio = clampf(_desvio + (0.6 if (c.id % 2) == 0 else -0.6), -1.4, 1.4)
		else:
			_desvio = move_toward(_desvio, 0.0, 0.3)
	_monitorar_progresso(cmd, pos, prox)


## Monitor de progresso: querendo andar e sem se aproximar do próximo ponto.
## 1,5 s: manobra (recua, pula, passo de lado); 3 s: evita a aresta onde travou e
## recalcula a rota; 3 recuperações no mesmo alvo: desiste dele.
func _monitorar_progresso(cmd: Protocol.InputCmd, pos: Vector3, prox: Vector3) -> void:
	if _manobra > 0:
		_manobra -= 1
		cmd.move = Vector2(_manobra_lado, -0.6)
		cmd.yaw += 0.0
		if _manobra == 19:
			cmd.buttons |= Protocol.BTN_JUMP
		return
	if server.tick - _prog_tick < 15:
		return
	_prog_tick = server.tick
	var dist := Vector2(prox.x - pos.x, prox.z - pos.z).length() + absf(prox.y - pos.y)
	if idx != _prog_idx or _prog_dist - dist > 0.35:
		_prog_dist = dist
		_prog_idx = idx
		_sem_progresso = 0
		return
	_sem_progresso += 15
	if _sem_progresso >= Protocol.TICK_RATE * 3:
		GameServer.add_stat(c, "preso_ticks", 15)       # diagnóstico: > 3 s sem progresso
		if _sem_progresso == Protocol.TICK_RATE * 3:
			GameServer.add_stat(c, "preso_episodios")
	if _sem_progresso == 45:
		_manobra = 20
		_manobra_lado = 1.0 if rng.randf() < 0.5 else -1.0
		GameServer.add_stat(c, "manobras")
	elif _sem_progresso >= 90 and _sem_progresso % 45 == 0:
		# trava de novo: evita a aresta atual por 25 s e recalcula
		var de: int = server.nav.node_of(pos) if server.nav else -1
		var para: int = server.nav.node_of(prox) if server.nav else -1
		if de == para:
			var k := nos_caminho.find(de)
			para = nos_caminho[k + 1] if k >= 0 and k + 1 < nos_caminho.size() else -1
		if de >= 0 and para >= 0 and de != para:
			_evitar[NavGrade.edge_key(de, para)] = server.tick + Protocol.TICK_RATE * 25
		precisa_caminho = true
		_recuperacoes += 1
		GameServer.add_stat(c, "recuperacoes")
		if _recuperacoes >= 3:
			_abandonar_alvo("travou")


func _limpar_evitar() -> void:
	for k in _evitar.keys():
		if int(_evitar[k]) < server.tick:
			_evitar.erase(k)


## Desiste do alvo atual (não fica andando contra a parede para sempre).
func _abandonar_alvo(_motivo: String) -> void:
	GameServer.add_stat(c, "abandonos")
	_recuperacoes = 0
	_sem_progresso = 0
	match estado:
		"saquear":
			ignorar[loot_alvo] = server.tick
		"bau":
			ignorar["bau%d" % bau_alvo] = server.tick
		"coletar":
			coleta_alvo = Vector3.INF
		"combater", "perseguir", "investigar":
			memoria_pos = Vector3.INF
			if estado != "combater":
				inimigo = 0
		"ordem":
			_evitar.clear()
			precisa_caminho = true
			return
	alvo = Vector3.INF
	caminho = PackedVector3Array()
	_prox_decisao = server.tick


func _combater(cmd: Protocol.InputCmd) -> void:
	var o := server.client_by_id(inimigo)
	if o == null or o.dead:
		inimigo = 0
		memoria_pos = Vector3.INF
		_prox_decisao = server.tick
		return
	var visivel := server.tick - visto_tick < Protocol.TICK_RATE
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
		_mirar_direto(cmd, o.pawn.global_position + Vector3(0, 1.15, 0), float(dif["erro_mira_graus"]))
		cmd.move = Vector2(0, 0.6)
		cmd.buttons |= Protocol.BTN_FIRE
		return
	if not visivel:
		# perdeu de vista: vai até onde viu por último (não sabe onde está agora)
		alvo = memoria_pos
		_andar(cmd, true)
		return
	if c.inv.selected != arma:
		cmd.slot = arma + 1
		return
	var w := ItemDB.weapon(c.inv.current().item)
	# distância preferida da arma: aproxima ou afasta; passos de lado para não ficar parado
	var pref: float = {"trovao": 6.0, "zumbido": 13.0, "faisca": 16.0, "rajada": 24.0, "gaviao": 50.0}.get(c.inv.current().item, 18.0)
	var frente := 0.7 if dist > pref * 1.35 else (-0.6 if dist < pref * 0.6 else 0.0)
	var lado := sin(server.tick * float(dif.get("ritmo_lateral", 0.07)) + c.id) * 0.85
	cmd.move = Vector2(lado, frente)
	_disparar(cmd, false)


## Mira e dispara no inimigo visto. O erro diminui com o tempo de visada (a mira
## "assenta"); rajadas nas automáticas; cadência controlada nas outras.
func _disparar(cmd: Protocol.InputCmd, andando: bool) -> void:
	var o := server.client_by_id(inimigo)
	if o == null or o.dead or c.inv.current().item.is_empty() or not ItemDB.is_weapon(c.inv.current().item):
		return
	var s := c.inv.current()
	var w := ItemDB.weapon(s.item)
	var visada := (server.tick - _visada_ini) / float(Protocol.TICK_RATE)
	var assenta := float(dif.get("mira_assenta_s", 0.8))
	var erro := float(dif["erro_mira_graus"]) * (1.0 + 2.0 * clampf(1.0 - visada / assenta, 0.0, 1.0)) \
			* (1.0 + clampf(o.pawn.velocity.length() / 6.0, 0.0, 1.0)) * (1.4 if andando else 1.0)
	var antes_yaw := cmd.yaw
	_mirar_direto(cmd, o.pawn.global_position + Vector3(0, 1.15, 0), erro)
	_yaw_disparo = cmd.yaw
	if andando:
		cmd.yaw = antes_yaw
	if s.mag <= 0:
		if _alterna:
			cmd.buttons |= Protocol.BTN_RELOAD
		return
	if server.tick < reagir_tick:
		return
	var dist := c.pawn.global_position.distance_to(o.pawn.global_position)
	if dist > 18.0 and w.has("dispersao_mirando"):
		cmd.buttons |= Protocol.BTN_AIM
	if w["automatica"]:
		# rajadas: atira N ticks, pausa M (mais longe = rajadas curtas)
		var n := int(dif.get("rajada_ticks", 10)) if dist < 20.0 else int(dif.get("rajada_ticks", 10)) / 2
		_rajada += 1
		if _rajada > n:
			_rajada = -int(dif.get("pausa_ticks", 6))
		if _rajada > 0:
			cmd.buttons |= Protocol.BTN_FIRE
	elif _alterna:
		cmd.buttons |= Protocol.BTN_FIRE


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
	var nota := 0.0
	for l in server.loot.loot.values():
		if LootServer.is_reserve(l) or ignorar.has(l["id"]):
			continue
		var id := ItemDB.id_of(l["item"])
		if not _cabe(id):
			continue
		var d := pos.distance_to(l["pos"])
		if d > 70.0:
			continue
		# valor do item para ESTE inventário, descontada a distância (andares contam)
		var v := _valor_loot(l)
		if v <= 0.0:
			continue
		var n := v / (1.0 + d / 18.0)
		if n > nota:
			nota = n
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
		var d := pos.distance_to(b["pos"]) + absf(b["pos"].y - pos.y) * 1.5     # andares: um pouco mais caro
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
	var pos := c.pawn.global_position
	# prefere cômodos de edifícios ainda não explorados, dentro da zona e não muito longe
	if mapa.has_method("rooms") and rng.randf() < float(dif.get("explora_predios", 0.7)):
		var melhor := -1
		var nota := 1e9
		var comodos: Array = mapa.rooms()
		for k in 24:
			var i := rng.randi() % comodos.size()
			if _visitados.has(i):
				continue
			var cc: Vector3 = comodos[i]["centro"]
			if Vector2(cc.x, cc.z).distance_to(z[0]) > float(z[1]) * 0.9:
				continue
			var d := pos.distance_to(cc)
			if d < 4.0 or d > 140.0:
				continue
			if d < nota:
				nota = d
				melhor = i
		if melhor >= 0:
			_visitados[melhor] = server.tick
			return comodos[melhor]["centro"]
	for i in 12:
		var ang := rng.randf() * TAU
		var r := sqrt(rng.randf()) * minf(float(z[1]), 160.0) * 0.8
		var q: Vector2 = z[0] + Vector2(cos(ang), sin(ang)) * r
		if mapa.ground_height(q.x, q.y) > 1.0:
			return Vector3(q.x, mapa.ground_height(q.x, q.y), q.y)
	return Vector3(z[0].x, mapa.ground_height(z[0].x, z[0].y), z[0].y)


## Na cobertura: recarrega e cura; quando o tempo de cobertura acaba, volta a lutar.
func _na_cobertura(cmd: Protocol.InputCmd) -> void:
	cmd.move = Vector2.ZERO
	var s := c.inv.current()
	if ItemDB.is_weapon(s.item) and s.mag < int(ItemDB.weapon(s.item)["pente"]) and _alterna:
		cmd.buttons |= Protocol.BTN_RELOAD
	elif c.vit.health + c.vit.shield < float(dif["cura_abaixo"]) and _consumivel_util() >= 0:
		_curar(cmd)
	if inimigo_pos != Vector3.INF:
		var d := inimigo_pos - c.pawn.global_position
		cmd.yaw = atan2(-d.x, -d.z)
	if server.tick > _cobertura_ate:
		_prox_decisao = server.tick


## Chegou onde ouviu o tiro / viu o inimigo pela última vez: olha em volta um pouco
## e, sem ninguém à vista, esquece.
func _olhar_em_volta(cmd: Protocol.InputCmd) -> void:
	if _observar == 0:
		_observar = Protocol.TICK_RATE * 3
	_observar -= 1
	cmd.move = Vector2.ZERO
	cmd.yaw = _yaw + 0.09 * (1.0 if c.id % 2 == 0 else -1.0)
	if _observar <= 1:
		_observar = 0
		if estado == "perseguir":
			memoria_pos = Vector3.INF
			inimigo = 0
		else:
			ouviu_pos = Vector3.INF
		_prox_decisao = server.tick


## Ponto de cobertura perto: um lugar alcançável a 3-9 m em que o inimigo NÃO
## enxerga (raio da posição do inimigo até a altura do peito bloqueado por algo).
func _achar_cobertura() -> Vector3:
	var pos := c.pawn.global_position
	var olho_ini := inimigo_pos + Vector3(0, Combat.EYE_STAND, 0)
	var espaco := server.world.get_world_3d().direct_space_state
	var melhor := Vector3.INF
	var nota := 1e9
	var base := rng.randf() * TAU
	for k in 10:
		if server.bot_raios <= 1:
			break
		var ang := base + k * TAU / 10.0
		var r := 3.0 + (k % 3) * 3.0
		var q := pos + Vector3(cos(ang), 0, sin(ang)) * r
		q.y = pos.y if absf(server.world.ground_height(q.x, q.z) - pos.y) > 2.5 else server.world.ground_height(q.x, q.z)
		# o ponto precisa estar livre (sem parede no meio do caminho até ele)
		server.bot_raios -= 2
		var ida := PhysicsRayQueryParameters3D.create(pos + Vector3(0, 0.9, 0), q + Vector3(0, 0.9, 0), Pawn.LAYER_WORLD)
		if not espaco.intersect_ray(ida).is_empty():
			continue
		var vista := PhysicsRayQueryParameters3D.create(olho_ini, q + Vector3(0, 1.2, 0), Pawn.LAYER_WORLD)
		if espaco.intersect_ray(vista).is_empty():
			continue                                 # o inimigo veria
		var n := r + q.distance_to(inimigo_pos) * -0.05
		if n < nota:
			nota = n
			melhor = q
	if melhor == Vector3.INF:
		# sem cobertura por perto: se afasta de lado
		var lado := (pos - inimigo_pos).cross(Vector3.UP).normalized() * (1.0 if rng.randf() < 0.5 else -1.0)
		melhor = pos + lado * 6.0
		melhor.y = server.world.ground_height(melhor.x, melhor.z)
	return melhor


## Quanto um item no chão melhora o inventário (0 = nada; 1 = útil; 2+ = muito).
func _valor_loot(l: Dictionary) -> float:
	var id := ItemDB.id_of(l["item"])
	if ItemDB.is_weapon(id):
		var raridade := int(l.get("rarity", 0))
		var melhor_igual := -1
		var armas := 0
		for s in c.inv.slots:
			if ItemDB.is_weapon(s.item):
				armas += 1
				if s.item == id:
					melhor_igual = maxi(melhor_igual, s.rarity)
		if armas == 0:
			return 3.0
		if melhor_igual >= 0:
			return 0.0 if raridade <= melhor_igual else 1.0 + 0.4 * (raridade - melhor_igual)
		return 1.2 if c.inv.free_count() > 0 else 0.0
	if ItemDB.is_consumable(id):
		var tem := 0
		for s in c.inv.slots:
			if ItemDB.is_consumable(s.item):
				tem += s.count
		return 0.9 if tem < 3 else 0.2
	return 0.3


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
		_construiu_tick = server.tick           # a estatística "construcoes" conta no BuildServer
