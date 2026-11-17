extends SceneTree
## ACEITE DA ETAPA 8 (automático): lobby e social de ponta a ponta, com processos
## de verdade: meta-servidor (Python) + servidor dedicado com 2 salas ligado a ele
## (--meta --segredo) + clientes deste processo.
## Fluxo: duas contas -> amizade -> convite para o grupo -> fila -> partida
## encontrada (ticket) -> os dois entram na mesma sala com o nome da conta ->
## bots completam -> partida começa. Sem ticket: recusado. Sala privada: código,
## outro grupo entra pelo código, o dono manda começar.
## Etapa 9: no fim da partida, o servidor envia o relatório e o meta-servidor
## aplica o XP (evento "progress", perfil e histórico).
## Uso: godot --headless --path game -s res://tests/integration/test_lobby.gd -- <url_meta>

var falhas := 0
var url := ""


func _checar(ok: bool, msg: String) -> void:
	print(("  ok  " if ok else "  FALHOU  ") + msg)
	if not ok:
		falhas += 1


class Jogador:
	extends Node
	var api := MetaApi.new()
	var conta := {}
	var seq := 0
	var eventos: Array = []
	var client: GameClient
	var nomes := {}
	var trajes := {}
	var partida := {}

	func _ready() -> void:
		add_child(api)

	func chamar(metodo: HTTPClient.Method, rota: String, corpo: Variant = null) -> Dictionary:
		return await api.request_json(metodo, rota, corpo)

	func criar(nome: String) -> bool:
		var r := await chamar(HTTPClient.METHOD_POST, "/v1/auth/register", {"username": nome, "password": "senha123"})
		if r["ok"]:
			api.session_token = r["data"]["token"]
			conta = r["data"]["account"]
		return r["ok"]

	func puxar(tipo: String, segundos := 8.0) -> Dictionary:
		var fim := Time.get_ticks_msec() + int(segundos * 1000)
		while Time.get_ticks_msec() < fim:
			for e in eventos:
				if e["type"] == tipo:
					eventos.erase(e)
					return e["data"]
			var r := await api.request_json(HTTPClient.METHOD_GET, "/v1/events?since=%d&wait=2" % seq, null, 6.0)
			if r["ok"]:
				for e in r["data"]["events"]:
					seq = maxi(seq, int(e["seq"]))
					eventos.append(e)
		return {}

	func entrar(m: Dictionary) -> void:
		client = GameClient.new()
		add_child(client)
		client.ticket = m.get("ticket", "")
		client.player_info.connect(func(id, n): nomes[id] = n)
		client.player_outfit.connect(func(id, c): trajes[id] = c)
		client.match_state.connect(func(x): partida = x)
		client.connect_to("127.0.0.1", int(m["port"]), "NomeQualquer")

	func _physics_process(_dt: float) -> void:
		if client:
			client.poll()
			if client.connected:
				var c := Protocol.InputCmd.new()
				c.seq = Engine.get_physics_frames()
				client.send_inputs([c])


func _esperar(n: int) -> void:
	for i in n:
		await physics_frame


func _init() -> void:
	url = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "http://127.0.0.1:8080"
	await process_frame
	var sufixo := str(randi() % 9000 + 1000)
	var a := Jogador.new()
	var b := Jogador.new()
	for j in [a, b]:
		root.add_child(j)
		j.api.base_url = url
	_checar(await a.criar("Ana" + sufixo) and await b.criar("Bia" + sufixo), "duas contas criadas")
	# amizade
	await a.chamar(HTTPClient.METHOD_POST, "/v1/friends/request", {"username": "bia" + sufixo})
	var pedido := await b.puxar("friend_request")
	_checar(pedido.get("from", {}).get("username", "") == "Ana" + sufixo, "Bia recebeu o pedido de amizade (evento)")
	await b.chamar(HTTPClient.METHOD_POST, "/v1/friends/respond", {"id": a.conta["id"], "accept": true})
	var lista := await a.chamar(HTTPClient.METHOD_GET, "/v1/friends")
	_checar(lista["data"]["friends"].size() == 1 and lista["data"]["friends"][0]["status"] == "lobby", "amigos: Bia aparece online no lobby")
	# grupo
	await a.chamar(HTTPClient.METHOD_POST, "/v1/party/invite", {"id": b.conta["id"]})
	var conv := await b.puxar("invite")
	var r := await b.chamar(HTTPClient.METHOD_POST, "/v1/party/respond", {"invite": conv.get("id", ""), "accept": true})
	_checar(r["ok"] and r["data"]["party"]["members"].size() == 2, "Bia aceitou o convite: grupo com 2")
	# a sala precisa ter se anunciado ao meta-servidor
	var salas := []
	for i in 40:
		salas = (await a.chamar(HTTPClient.METHOD_GET, "/v1/rooms"))["data"]["rooms"]
		if salas.size() >= 2:
			break
		await create_timer(0.5).timeout
	_checar(salas.size() == 2, "as 2 salas do servidor dedicado se anunciaram (%d)" % salas.size())
	# inventário: a Ana veste a Recruta Brisa (presente de todas as contas)
	r = await a.chamar(HTTPClient.METHOD_POST, "/v1/loadout", {"slot": "traje", "item": "traje_brisa"})
	_checar(r["ok"] and r["data"]["equipped"]["traje"] == "traje_brisa", "Ana equipou a Recruta Brisa")
	# fila -> partida encontrada
	r = await a.chamar(HTTPClient.METHOD_POST, "/v1/match/queue", {})
	var ma := await a.puxar("match_found")
	var mb := await b.puxar("match_found")
	_checar(not ma.is_empty() and not mb.is_empty() and ma["port"] == mb["port"], "partida encontrada para os dois, mesma sala (porta %d)" % int(ma.get("port", 0)))
	# sem ticket: recusado
	var intruso := GameClient.new()
	root.add_child(intruso)
	var recusa := [""]
	intruso.rejected.connect(func(x): recusa[0] = x)
	intruso.connect_to("127.0.0.1", int(ma.get("port", 0)), "Intruso")
	for i in 150:
		await physics_frame
		intruso.poll()
		if not recusa[0].is_empty():
			break
	_checar(recusa[0].begins_with("Entre pelo lobby"), "sem ticket: recusado (\"%s\")" % recusa[0])
	# com ticket: entram, com o nome da conta (não o que o cliente mandou)
	a.entrar(ma)
	b.entrar(mb)
	for i in 300:
		await physics_frame
		if a.client.connected and b.client.connected and a.nomes.size() >= 2:
			break
	_checar(a.client.connected and b.client.connected, "os dois entraram na sala com o ticket")
	var nomes: Array = a.nomes.values()
	_checar(("Ana" + sufixo) in nomes and ("Bia" + sufixo) in nomes and not "NomeQualquer" in nomes, "nomes vêm da conta: %s" % str(nomes))
	var cos_ana: Dictionary = b.trajes.get(a.client.my_id, {})
	_checar(cos_ana.get("traje", "") == "traje_brisa" and b.trajes.get(b.client.my_id, {}).get("traje", "x") == "traje_recruta",
			"na partida, a Bia vê a Ana de Recruta Brisa (e ela mesma de Recruta)")
	_checar(cos_ana.get("picareta", "") == "picareta_padrao" and cos_ana.get("planador", "") == "planador_padrao",
			"picareta e planador equipados também chegam aos outros (%s)" % str(cos_ana))
	var g: Dictionary = (await a.chamar(HTTPClient.METHOD_GET, "/v1/party"))["data"]
	_checar(g["state"] == "partida", "grupo em partida no meta-servidor")
	# matchmaking: a sala espera um pouco por mais pessoas (8 s nos testes) e depois os bots completam
	await create_timer(3.0).timeout
	_checar(a.partida.get("estado", 0) == Protocol.MATCH_ESPERA, "a sala ainda espera mais jogadores reais (estado %s)" % str(a.partida.get("estado")))
	# a partida começa (2 humanos) e os bots completam
	for i in 30 * 40:
		await physics_frame
		if a.partida.get("estado", 0) in [Protocol.MATCH_ONIBUS, Protocol.MATCH_JOGO]:
			break
	_checar(a.partida.get("estado", 0) in [Protocol.MATCH_ONIBUS, Protocol.MATCH_JOGO], "a partida começou (estado %s)" % str(a.partida.get("estado")))
	_checar(int(a.partida.get("total", 0)) >= 8, "bots completaram a partida (%s jogadores)" % str(a.partida.get("total")))
	var amigos: Array = (await b.chamar(HTTPClient.METHOD_GET, "/v1/friends"))["data"]["friends"]
	_checar(amigos.size() == 1 and amigos[0]["status"] == "partida", "presença: Ana aparece \"em partida\" para a Bia")

	# ---- sala privada (na outra sala do servidor) ----
	var c := Jogador.new()
	var d := Jogador.new()
	for j in [c, d]:
		root.add_child(j)
		j.api.base_url = url
	await c.criar("Caio" + sufixo)
	await d.criar("Duda" + sufixo)
	r = await c.chamar(HTTPClient.METHOD_POST, "/v1/rooms/private", {})
	_checar(r["ok"] and str(r["data"].get("code", "")).length() == 5, "sala privada criada (código %s)" % str(r["data"].get("code", "") if r["data"] is Dictionary else ""))
	var codigo: String = r["data"].get("code", "") if r["ok"] else ""
	var mc := await c.puxar("match_found")
	r = await d.chamar(HTTPClient.METHOD_POST, "/v1/rooms/join", {"code": codigo.to_lower()})
	var md := await d.puxar("match_found")
	_checar(r["ok"] and not md.is_empty() and md["port"] == mc["port"] and md["port"] != ma["port"], "Duda entrou pelo código na mesma sala privada (porta %d)" % int(md.get("port", 0)))
	c.entrar(mc)
	d.entrar(md)
	for i in 300:
		await physics_frame
		if c.client.connected and d.client.connected:
			break
	await create_timer(5.0).timeout     # sala privada não começa sozinha (espera curta do teste: 20 s)
	_checar(c.partida.get("estado", 0) == Protocol.MATCH_ESPERA, "sala privada espera o dono")
	await c.chamar(HTTPClient.METHOD_POST, "/v1/rooms/start", {})
	for i in 30 * 10:
		await physics_frame
		if c.partida.get("estado", 0) != Protocol.MATCH_ESPERA:
			break
	_checar(c.partida.get("estado", 0) in [Protocol.MATCH_CONTAGEM, Protocol.MATCH_ONIBUS], "o dono mandou começar: contagem (estado %s)" % str(c.partida.get("estado")))
	# ---- Etapa 9: fim da partida -> relatório -> XP aplicado pelo meta-servidor ----
	for i in 30 * 240:
		await physics_frame
		if a.partida.get("estado", 0) == Protocol.MATCH_FIM:
			break
	_checar(a.partida.get("estado", 0) == Protocol.MATCH_FIM, "a partida da Ana e da Bia terminou")
	var pa := await a.puxar("progress", 20.0)
	var pb := await b.puxar("progress", 5.0)
	_checar(int(pa.get("xp_total", 0)) >= 50 and int(pb.get("xp_total", 0)) >= 50, "XP aplicado pelo meta-servidor (Ana +%s, Bia +%s)" % [str(pa.get("xp_total")), str(pb.get("xp_total"))])
	var perfil: Dictionary = (await a.chamar(HTTPClient.METHOD_GET, "/v1/profile"))["data"]
	_checar(int(perfil.get("xp_total", 0)) == int(pa.get("xp_total", -1)) and int(perfil.get("matches", 0)) == 1, "perfil da Ana: %s XP, %s partida" % [str(perfil.get("xp_total")), str(perfil.get("matches"))])
	var passe: Dictionary = (await a.chamar(HTTPClient.METHOD_GET, "/v1/season"))["data"]
	_checar(pa.get("passe") is Dictionary and int(passe.get("xp", 0)) == int(pa.get("xp_total", -1)),
			"o XP da partida também subiu o passe (%s XP no passe)" % str(passe.get("xp")))
	var loja: Dictionary = (await a.chamar(HTTPClient.METHOD_GET, "/v1/shop"))["data"]
	_checar(loja.get("secoes", []).size() == 2 and loja["secoes"][1]["itens"].size() == 4, "loja: Destaques e Diária com itens")
	var caro: Dictionary = loja["secoes"][1]["itens"][0]
	var compra := await a.chamar(HTTPClient.METHOD_POST, "/v1/shop/buy", {"item": caro["id"], "preco": caro["preco"], "chave": "teste-e2e-1"})
	_checar(not compra["ok"] and compra["status"] == 409, "sem Faíscas suficientes, a compra é recusada (%s)" % compra["error"])
	var hist: Array = (await a.chamar(HTTPClient.METHOD_GET, "/v1/history"))["data"]["matches"]
	_checar(hist.size() == 1 and int(hist[0]["placement"]) == int(pa.get("colocacao", -1)), "histórico da partida gravado (colocação %s)" % str(pa.get("colocacao")))
	# o Caio pode ter recebido XP da partida da própria sala privada, nunca da partida da Ana
	var pc := await c.puxar("progress", 1.0)
	_checar(pc.is_empty() or pc.get("match_id", "") != pa.get("match_id", ""), "quem não jogou aquela partida não ganhou XP por ela")
	for j in [a, b, c, d]:
		j.client.close()
	await create_timer(0.5).timeout
	print("LOBBY %s" % ("OK" if falhas == 0 else "FALHA (%d)" % falhas))
	quit(0 if falhas == 0 else 1)
