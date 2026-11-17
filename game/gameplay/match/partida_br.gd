class_name PartidaBR
extends RefCounted
## Regras da partida Battle Royale no servidor (autoridade).
##  ESPERA   — jogadores na área de espera (Mirante); sem dano; quem cai volta.
##             Com min_jogadores (ou depois de espera_maxima_s com 1+), começa a contagem.
##  CONTAGEM — contagem regressiva; quem entra ainda participa.
##  ONIBUS   — loot novo, inventário vazio (só a picareta); todos no Ônibus de
##             Batalha, que atravessa a ilha. Cada um salta quando quiser (Pular,
##             com as portas abertas sobre terra); quem fica é ejetado antes de o
##             ônibus sair da ilha. Queda livre → planador → chão. Sem dano entre
##             jogadores nesta fase (proteção de pouso).
##  JOGO     — começa quando o ônibus sai: a Tormenta nasce aqui (fase 1: anúncio
##             da zona, espera, fechamento…). Sem reaparecer. Eliminado = espectador.
##  FIM      — vencedor anunciado; depois de fim_s, nova partida (volta à ESPERA).
## Vitória: sobra 1 (partida com 2+); sozinho: sobreviver até a Tormenta terminar.

const ARQUIVO := "res://data/partida.json"

var server: GameServer
var config: Dictionary
var estado := Protocol.MATCH_ESPERA


func estado_nome() -> String:
	return {Protocol.MATCH_ESPERA: "esperando", Protocol.MATCH_CONTAGEM: "contagem", Protocol.MATCH_ONIBUS: "ônibus",
			Protocol.MATCH_JOGO: "em jogo", Protocol.MATCH_FIM: "fim"}.get(estado, "?")
var t := 0                          # ticks no estado atual
var modo_lobby := false             # sala do matchmaking (--meta): espera curta por humanos e depois bots
var _espera_desde := -1             # tick em que chegou o primeiro humano (modo lobby)
var tormenta: Tormenta
var onibus: OnibusBatalha
var saltaram := 0                   # diagnóstico/testes
var ejetados := 0
var participantes := {}             # id -> {"nome","eliminacoes","colocacao","inicio","fim"}
var vivos: Array[int] = []
var total_inicial := 0
var vencedor := 0
var partidas := 0                   # partidas iniciadas (diagnóstico/testes)
var historico: Array = []           # resumo de cada partida terminada (testes)
var _ultimo_envio := -999


func _init(s: GameServer, cfg := {}) -> void:
	server = s
	config = cfg if not cfg.is_empty() else carregar_config()


static func carregar_config() -> Dictionary:
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(ARQUIVO))
	return d if d is Dictionary else {}


func _ticks(s: float) -> int:
	return roundi(s * Protocol.TICK_RATE)


func dano_ativo() -> bool:
	return estado == Protocol.MATCH_JOGO and t >= _ticks(float(config.get("protecao_inicio_s", 0)))


func em_jogo() -> bool:
	return estado == Protocol.MATCH_JOGO or estado == Protocol.MATCH_ONIBUS


func jogadores() -> Array:
	return server.clientes.values().filter(func(c): return c.pawn != null)


# ---------- ciclo ----------

func update() -> void:
	t += 1
	match estado:
		Protocol.MATCH_ESPERA:
			var n := jogadores().size()
			var minimo := int(config.get("min_jogadores", 2))
			if server.privada:
				# sala privada: quem decide é o dono (pelo lobby)
				if server.forcar_inicio and n >= 1:
					server.forcar_inicio = false
					_mudar(Protocol.MATCH_CONTAGEM)
			elif modo_lobby:
				# matchmaking: espera curta por mais pessoas; sem ninguém novo, os bots completam
				if n == 0:
					_espera_desde = -1
				elif _espera_desde < 0:
					_espera_desde = server.tick
				if n > 0:
					var passou := server.tick - _espera_desde
					var cheia: bool = n >= server.max_jogadores
					var pendentes: bool = server.reservas_pendentes > 0 and passou < _ticks(float(config.get("espera_lobby_max_s", 60)))
					if cheia or (passou >= _ticks(float(config.get("espera_lobby_s", 30))) and not pendentes):
						_mudar(Protocol.MATCH_CONTAGEM)
			elif n >= minimo or (n >= 1 and t >= _ticks(float(config.get("espera_maxima_s", 90)))):
				_mudar(Protocol.MATCH_CONTAGEM)
		Protocol.MATCH_CONTAGEM:
			if jogadores().is_empty() and not config.get("somente_bots", false):
				_mudar(Protocol.MATCH_ESPERA)
			elif t >= _ticks(float(config.get("contagem_s", 10))):
				_iniciar()
		Protocol.MATCH_ONIBUS:
			_atualizar_onibus()
		Protocol.MATCH_JOGO:
			if tormenta.update():
				server.broadcast(Protocol.pack_storm(tormenta.to_dict()), true)
			if t % Protocol.TICK_RATE == 0:
				_dano_tormenta()
			_checar_vitoria()
		Protocol.MATCH_FIM:
			if t >= _ticks(float(config.get("fim_s", 15))):
				_reiniciar()
	if t - _ultimo_envio >= Protocol.TICK_RATE:
		_enviar_estado()


func _mudar(novo: int) -> void:
	estado = novo
	t = 0
	_enviar_estado()


func _enviar_estado() -> void:
	_ultimo_envio = t
	server.broadcast(Protocol.pack_match(match_dict()), true)


func match_dict() -> Dictionary:
	var resta := 0
	match estado:
		Protocol.MATCH_ESPERA:
			if modo_lobby:
				resta = 0 if _espera_desde < 0 else maxi(0, _ticks(float(config.get("espera_lobby_s", 30))) - (server.tick - _espera_desde))
			else:
				resta = maxi(0, _ticks(float(config.get("espera_maxima_s", 90))) - t)
		Protocol.MATCH_CONTAGEM:
			resta = maxi(0, _ticks(float(config.get("contagem_s", 10))) - t)
		Protocol.MATCH_ONIBUS:
			resta = maxi(0, onibus.fecha - server.tick)
		Protocol.MATCH_JOGO:
			resta = tormenta.ticks_left()
		Protocol.MATCH_FIM:
			resta = maxi(0, _ticks(float(config.get("fim_s", 15))) - t)
	var na_partida := estado == Protocol.MATCH_JOGO or estado == Protocol.MATCH_FIM or estado == Protocol.MATCH_ONIBUS
	return {"estado": estado, "vivos": vivos.size() if na_partida else jogadores().size(),
			"total": total_inicial, "resta_ms": roundi(resta * 1000.0 / Protocol.TICK_RATE), "vencedor": vencedor}


func _iniciar() -> void:
	partidas += 1
	participantes.clear()
	vivos.clear()
	vencedor = 0
	var semente := int(Time.get_unix_time_from_system()) + partidas * 7919 if not config.has("semente") else int(config["semente"]) + partidas
	server.loot.reset(semente)
	server.build.reset()                # mapa intacto e sem construções da partida anterior
	var mundo := server.world
	tormenta = null
	saltaram = 0
	ejetados = 0
	_preencher_bots()
	var terra := func(x: float, z: float) -> bool: return mundo.ground_height(x, z) > 0.4
	onibus = OnibusBatalha.sortear(semente, server.tick + Protocol.TICK_RATE, mundo.limit(), terra)
	var k := 0
	for c: GameServer.Cliente in jogadores():
		c.inv = Inventory.new()
		c.vit.reset()
		c.dead = false
		server.combat.cancel(c)
		var dif = c.stats.get("dificuldade")
		c.stats = {} if dif == null else {"dificuldade": dif}
		c.pawn.queda = Pawn.NO_ONIBUS
		c.pawn.velocity = Vector3.ZERO
		c.pawn.global_position = _no_onibus(k)
		participantes[c.id] = {"nome": c.nome, "eliminacoes": 0, "colocacao": 0, "inicio": server.tick, "fim": 0, "assento": k,
				"conta": c.conta, "stats": {}}
		vivos.append(c.id)
		c.dirty = true
		k += 1
	total_inicial = vivos.size()
	_mudar(Protocol.MATCH_ONIBUS)
	server.broadcast(Protocol.pack_bus(onibus.to_dict()), true)
	server.log_msg("partida %d começou com %d jogador(es): Ônibus de Batalha saindo" % [partidas, total_inicial])


## Posição de um jogador dentro do ônibus (assentos ao longo do corredor).
func _no_onibus(assento: int) -> Vector3:
	var p := onibus.position_at(server.tick)
	var ao_longo := onibus.direction() * ((assento % 6) - 2.5) * 1.2
	return p + ao_longo + Vector3(0, 0.6, 0)


## Pular dentro do ônibus com as portas abertas: salta (só este jogador).
func on_bus_input(c: GameServer.Cliente, cmd: Protocol.InputCmd) -> void:
	if estado == Protocol.MATCH_ONIBUS and cmd.has(Protocol.BTN_JUMP) and onibus.doors_open(server.tick):
		_saltar(c)
		saltaram += 1


func _saltar(c: GameServer.Cliente) -> void:
	c.pawn.queda = Pawn.QUEDA_LIVRE
	c.pawn.global_position = onibus.position_at(server.tick) + Vector3(0, -3.0, 0)
	c.pawn.velocity = onibus.direction() * 6.0 + Vector3(0, -2.0, 0)
	c.pawn.grounded = false
	c.dirty = true


func _atualizar_onibus() -> void:
	var ainda := 0
	for c: GameServer.Cliente in jogadores():
		if c.pawn.queda != Pawn.NO_ONIBUS:
			continue
		if onibus.finished(server.tick):
			_saltar(c)                  # portas fechando: ejetado, ainda sobre a ilha
			ejetados += 1
		else:
			c.pawn.global_position = _no_onibus(int(participantes.get(c.id, {}).get("assento", 0)))
			c.pawn.velocity = onibus.direction() * OnibusBatalha.VELOCIDADE
			ainda += 1
	if ainda == 0 and onibus.finished(server.tick):
		# o ônibus saiu da ilha: a Tormenta começa agora (fase 1: zona marcada + espera)
		var mundo := server.world
		var semente := int(onibus.tick0) * 31 + partidas
		tormenta = Tormenta.new(config["tormenta"], semente, func(c: Vector2, r: float) -> bool: return _zona_valida(mundo, c, r))
		_mudar(Protocol.MATCH_JOGO)
		server.broadcast(Protocol.pack_storm(tormenta.to_dict()), true)
		server.log_msg("partida %d: ônibus saiu (%d saltaram, %d ejetados); Tormenta fase 1" % [partidas, saltaram, ejetados])


## Centro de zona aceitável: em terra e longe o bastante do mar para a zona ser jogável.
static func _zona_valida(mundo: Mapa, c: Vector2, r: float) -> bool:
	if mundo.ground_height(c.x, c.y) <= 1.0:
		return false
	if mundo.has_method("inland"):
		return mundo.inland(c.x, c.y) >= minf(r * 0.35, 60.0) + 8.0
	return true


func _reiniciar() -> void:
	vivos.clear()
	participantes.clear()
	total_inicial = 0
	vencedor = 0
	tormenta = null
	onibus = null
	for b in server.bots():
		server.remove_bot(b)
	for c: GameServer.Cliente in jogadores():
		c.inv = Inventory.new()
		c.vit.reset()
		c.dead = false
		server.combat.cancel(c)
		c.pawn.queda = 0
		server.respawn_lobby(c)
		c.dirty = true
	server.loot.reset(0, true)
	_mudar(Protocol.MATCH_ESPERA)


# ---------- eventos ----------

## Jogador entrou: na espera/contagem participa; com a partida em andamento, assiste.
func on_join(c: GameServer.Cliente) -> void:
	if estado == Protocol.MATCH_JOGO or estado == Protocol.MATCH_FIM or estado == Protocol.MATCH_ONIBUS:
		c.dead = true
		c.dirty = true
	server.send_to(c.peer_id, Protocol.pack_match(match_dict()), true)
	if tormenta:
		server.send_to(c.peer_id, Protocol.pack_storm(tormenta.to_dict()), true)
	if onibus and estado == Protocol.MATCH_ONIBUS:
		server.send_to(c.peer_id, Protocol.pack_bus(onibus.to_dict()), true)


func on_leave(c: GameServer.Cliente) -> void:
	if vivos.has(c.id):
		_eliminar_registro(c.id, 0)


## Completa a partida com bots até `preencher_ate` (data/bots.json, ou "bots" na config).
func _preencher_bots() -> void:
	var cfg := BotCerebro.config()
	var b_cfg: Dictionary = config.get("bots", {})
	var alvo := int(b_cfg.get("preencher_ate", cfg.get("preencher_ate", 0)))
	var mistura: Array = b_cfg.get("mistura", cfg["mistura"])
	var humanos := jogadores().filter(func(c): return c.bot == null).size()
	for k in maxi(0, alvo - humanos):
		server.add_bot(mistura[k % mistura.size()])


## Chamado pelo CombatServer.eliminate. Retorna true se o jogador deve reaparecer (espera).
func on_elimination(v: GameServer.Cliente, quem: int) -> bool:
	if estado != Protocol.MATCH_JOGO and estado != Protocol.MATCH_ONIBUS:
		return true                 # espera/contagem/fim: só caiu do mapa, volta
	if not vivos.has(v.id):
		return false
	if quem != v.id and participantes.has(quem):
		participantes[quem]["eliminacoes"] += 1
	_eliminar_registro(v.id, quem)
	return false


func _eliminar_registro(id: int, _quem: int) -> void:
	var p: Dictionary = participantes.get(id, {})
	if not p.is_empty():
		p["colocacao"] = vivos.size()
		p["fim"] = server.tick
		var c := server.client_by_id(id)
		if c:
			p["stats"] = c.stats.duplicate()     # quem sai depois de eliminado não perde o que fez
	vivos.erase(id)
	_enviar_resultado(id)
	_enviar_estado()


func _enviar_resultado(id: int) -> void:
	var p: Dictionary = participantes.get(id, {})
	var c := server.client_by_id(id)
	if p.is_empty() or c == null:
		return
	var fim: int = p["fim"] if p["fim"] > 0 else server.tick
	server.send_to(c.peer_id, Protocol.pack_result({"colocacao": p["colocacao"], "total": total_inicial,
			"eliminacoes": p["eliminacoes"], "tempo_s": roundi((fim - int(p["inicio"])) / float(Protocol.TICK_RATE)),
			"vencedor": vencedor}), true)


## A cada segundo: quem está fora da zona perde vida (ignora o escudo). Se o dano
## eliminaria todos os que restam, o de mais vida sobrevive (é o vencedor).
func _dano_tormenta() -> void:
	var dano := tormenta.damage_per_second()
	var fora := []
	for id in vivos:
		var c := server.client_by_id(id)
		if c and c.pawn and tormenta.is_outside(c.pawn.global_position):
			fora.append(c)
	fora.sort_custom(func(a, b): return a.vit.health < b.vit.health)
	for c: GameServer.Cliente in fora:
		if total_inicial >= 2 and vivos.size() <= 1:
			break                   # o último que resta é o vencedor
		c.dirty = true
		server.send_to(c.peer_id, Protocol.pack_damaged(dano, c.pawn.global_position), true)
		GameServer.add_stat(c, "dano_tormenta", dano)
		if c.vit.take_storm_damage(dano):
			server.combat.eliminate(c, c.id, "")


func _checar_vitoria() -> void:
	if estado != Protocol.MATCH_JOGO:
		return
	var acabou := false
	if total_inicial >= 2 and vivos.size() <= 1:
		acabou = true
	elif total_inicial < 2 and (vivos.is_empty() or tormenta.terminou):
		acabou = true
	if not acabou:
		return
	vencedor = vivos[0] if vivos.size() == 1 else 0
	if vencedor:
		participantes[vencedor]["colocacao"] = 1
		participantes[vencedor]["fim"] = server.tick
	var metricas := {}
	for c: GameServer.Cliente in server.clientes.values():
		if participantes.has(c.id):
			var m: Dictionary = c.stats.duplicate()
			m["colocacao"] = participantes[c.id]["colocacao"]
			m["eliminacoes"] = participantes[c.id]["eliminacoes"]
			m["tempo_s"] = (int(participantes[c.id]["fim"]) - int(participantes[c.id]["inicio"])) / float(Protocol.TICK_RATE)
			m["bot"] = c.bot != null
			metricas[c.id] = m
	historico.append({"partida": partidas, "total": total_inicial, "vencedor": vencedor, "saltaram": saltaram, "ejetados": ejetados, "metricas": metricas,
			"fase_tormenta": tormenta.fase, "duracao_s": t / float(Protocol.TICK_RATE),
			"colocacoes": participantes.duplicate(true)})
	server.log_msg("partida %d terminou: vencedor %d (%d jogador[es])" % [partidas, vencedor, total_inicial])
	_mudar(Protocol.MATCH_FIM)
	for id in participantes:
		_enviar_resultado(id)
	_relatorio()


## Etapa 9: relatório para o meta-servidor (só jogadores com conta). Quem concede
## XP e Faíscas é o meta-servidor; aqui só se conta o que aconteceu.
func _relatorio() -> void:
	var jogadores := []
	for id in participantes:
		var p: Dictionary = participantes[id]
		if int(p.get("conta", 0)) <= 0:
			continue
		var c := server.client_by_id(id)
		var st: Dictionary = c.stats if c and vivos.has(id) else p.get("stats", {})
		jogadores.append({"acc": p["conta"], "colocacao": p["colocacao"], "eliminacoes": p["eliminacoes"],
				"tempo_s": roundi((int(p["fim"]) - int(p["inicio"])) / float(Protocol.TICK_RATE)), "venceu": id == vencedor,
				"baus": int(st.get("baus", 0)), "coleta": int(st.get("coleta", 0)), "construcoes": int(st.get("construcoes", 0)),
				"dano": int(st.get("dano", 0)), "curas": int(st.get("curas", 0))})
	if jogadores.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	server.match_report.emit({"match_id": "%d-%d-%d-%08x" % [server.porta, partidas, int(Time.get_unix_time_from_system()), rng.randi()],
			"mode": "br", "total": total_inicial, "port": server.porta, "players": jogadores})
