class_name PartidaBR
extends RefCounted
## Regras da partida Battle Royale no servidor (autoridade).
##  ESPERA   — jogadores na área de espera (Mirante); sem dano; quem cai volta.
##             Com min_jogadores (ou depois de espera_maxima_s com 1+), começa a contagem.
##  CONTAGEM — contagem regressiva; quem entra ainda participa.
##  JOGO     — loot novo, todos espalhados pelo mapa com inventário vazio (só a
##             picareta), Tormenta ativa, sem reaparecer. Eliminado = espectador.
##  FIM      — vencedor anunciado; depois de fim_s, nova partida (volta à ESPERA).
## Vitória: sobra 1 (partida com 2+); sozinho: sobreviver até a Tormenta terminar.

const ARQUIVO := "res://data/partida.json"

var server: GameServer
var config: Dictionary
var estado := Protocol.MATCH_ESPERA
var t := 0                          # ticks no estado atual
var tormenta: Tormenta
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
	return estado == Protocol.MATCH_JOGO


func jogadores() -> Array:
	return server.clientes.values().filter(func(c): return c.pawn != null)


# ---------- ciclo ----------

func update() -> void:
	t += 1
	match estado:
		Protocol.MATCH_ESPERA:
			var n := jogadores().size()
			var minimo := int(config.get("min_jogadores", 2))
			if n >= minimo or (n >= 1 and t >= _ticks(float(config.get("espera_maxima_s", 90)))):
				_mudar(Protocol.MATCH_CONTAGEM)
		Protocol.MATCH_CONTAGEM:
			if jogadores().is_empty():
				_mudar(Protocol.MATCH_ESPERA)
			elif t >= _ticks(float(config.get("contagem_s", 10))):
				_iniciar()
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
			resta = maxi(0, _ticks(float(config.get("espera_maxima_s", 90))) - t)
		Protocol.MATCH_CONTAGEM:
			resta = maxi(0, _ticks(float(config.get("contagem_s", 10))) - t)
		Protocol.MATCH_JOGO:
			resta = tormenta.ticks_left()
		Protocol.MATCH_FIM:
			resta = maxi(0, _ticks(float(config.get("fim_s", 15))) - t)
	return {"estado": estado, "vivos": vivos.size() if estado >= Protocol.MATCH_JOGO else jogadores().size(),
			"total": total_inicial, "resta_ms": roundi(resta * 1000.0 / Protocol.TICK_RATE), "vencedor": vencedor}


func _iniciar() -> void:
	partidas += 1
	participantes.clear()
	vivos.clear()
	vencedor = 0
	var semente := int(Time.get_unix_time_from_system()) + partidas * 7919 if not config.has("semente") else int(config["semente"]) + partidas
	server.loot.reset(semente)
	var mundo := server.world
	tormenta = Tormenta.new(config["tormenta"], semente, func(c: Vector2): return mundo.ground_height(c.x, c.y) > 1.0)
	var pontos: Array = mundo.match_spawn_points().duplicate()
	var rng := RandomNumberGenerator.new()
	rng.seed = semente
	for i in range(pontos.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = pontos[i]
		pontos[i] = pontos[j]
		pontos[j] = tmp
	var k := 0
	for c: GameServer.Cliente in jogadores():
		c.inv = Inventory.new()
		c.vit.reset()
		c.dead = false
		server.combat.cancel(c)
		var p: Vector3 = pontos[k % pontos.size()] if not pontos.is_empty() else mundo.spawn_point(k)
		c.pawn.global_position = p
		c.pawn.velocity = Vector3.ZERO
		participantes[c.id] = {"nome": c.nome, "eliminacoes": 0, "colocacao": 0, "inicio": server.tick, "fim": 0}
		vivos.append(c.id)
		c.dirty = true
		k += 1
	total_inicial = vivos.size()
	_mudar(Protocol.MATCH_JOGO)
	server.broadcast(Protocol.pack_storm(tormenta.to_dict()), true)
	server.log_msg("partida %d começou com %d jogador(es)" % [partidas, total_inicial])


func _reiniciar() -> void:
	vivos.clear()
	participantes.clear()
	total_inicial = 0
	vencedor = 0
	tormenta = null
	for c: GameServer.Cliente in jogadores():
		c.inv = Inventory.new()
		c.vit.reset()
		c.dead = false
		server.combat.cancel(c)
		server.respawn_lobby(c)
		c.dirty = true
	server.loot.reset(0, true)
	_mudar(Protocol.MATCH_ESPERA)


# ---------- eventos ----------

## Jogador entrou: na espera/contagem participa; com a partida em andamento, assiste.
func on_join(c: GameServer.Cliente) -> void:
	if estado == Protocol.MATCH_JOGO or estado == Protocol.MATCH_FIM:
		c.dead = true
		c.dirty = true
	server.send_to(c.peer_id, Protocol.pack_match(match_dict()), true)
	if tormenta:
		server.send_to(c.peer_id, Protocol.pack_storm(tormenta.to_dict()), true)


func on_leave(c: GameServer.Cliente) -> void:
	if vivos.has(c.id):
		_eliminar_registro(c.id, 0)


## Chamado pelo CombatServer.eliminate. Retorna true se o jogador deve reaparecer (espera).
func on_elimination(v: GameServer.Cliente, quem: int) -> bool:
	if estado != Protocol.MATCH_JOGO:
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
	historico.append({"partida": partidas, "total": total_inicial, "vencedor": vencedor,
			"fase_tormenta": tormenta.fase, "duracao_s": t / float(Protocol.TICK_RATE),
			"colocacoes": participantes.duplicate(true)})
	server.log_msg("partida %d terminou: vencedor %d (%d jogador[es])" % [partidas, vencedor, total_inicial])
	_mudar(Protocol.MATCH_FIM)
	for id in participantes:
		_enviar_resultado(id)
