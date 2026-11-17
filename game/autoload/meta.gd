extends MetaApi
## Conexão com o meta-servidor: estado do servidor, conta, grupo, amigos e
## eventos (long-polling). A interface só lê daqui e chama os métodos; quem
## decide tudo é o servidor (o cliente nunca concede nada a si mesmo).

signal status_changed(state: String, info: Dictionary, error: String)
signal account_changed(account: Dictionary)      # {} = saiu
signal party_changed(party: Dictionary)
signal friends_changed(friends: Dictionary)
signal invite_received(invite: Dictionary)
signal friend_request(from: Dictionary)
signal match_found(m: Dictionary)
signal notice(text: String)                      # avisos curtos para a interface
signal profile_changed(profile: Dictionary)      # Etapa 9: nível, XP, Faíscas, itens
signal progress(p: Dictionary)                   # resumo do XP de uma partida (vem do servidor)

const SESSAO := "user://session.cfg"
const ESPERA_EVENTOS_S := 25.0

## "desconhecido" | "verificando" | "online" | "offline" | "incompatible"
var state := "desconhecido"
var info := {}
var last_error := ""
var account := {}
var party := {}
var friends := {"friends": [], "incoming": [], "outgoing": []}
var profile := {}
var last_progress := {}       # último resumo de partida (a tela de resultado mostra)
var _seq := 0
var _geracao := 0           # muda a cada login/logout: o laço de eventos antigo para


func _ready() -> void:
	base_url = Settings.get_value("network", "server_url")
	Settings.changed.connect(func(s, k, v):
		if s == "network" and k == "server_url":
			base_url = v)
	var cfg := ConfigFile.new()
	if cfg.load(SESSAO) == OK:
		session_token = cfg.get_value("sessao", "token", "")


func logged_in() -> bool:
	return not account.is_empty()


func is_leader() -> bool:
	return logged_in() and int(party.get("leader", -1)) == int(account.get("id", -2))


func refresh() -> void:
	if state == "verificando":
		return
	_mudar_estado("verificando", {}, "")
	var r := await check_health()
	_mudar_estado(r["state"], r["info"], r["error"])
	if state == "online":
		Log.info("rede", "meta-servidor online: %s (versão %s)" % [base_url, info.get("server_version", "?")])
		if not session_token.is_empty() and not logged_in():
			await _retomar_sessao()
	else:
		Log.warn("rede", "meta-servidor %s: %s" % [state, last_error])


func _mudar_estado(s: String, i: Dictionary, e: String) -> void:
	state = s
	info = i
	last_error = e
	status_changed.emit(state, info, last_error)


# ---------- conta ----------

func register(nome: String, senha: String) -> Dictionary:
	return await _autenticar("/v1/auth/register", nome, senha)


func login(nome: String, senha: String) -> Dictionary:
	return await _autenticar("/v1/auth/login", nome, senha)


func _autenticar(rota: String, nome: String, senha: String) -> Dictionary:
	session_token = ""
	var r := await request_json(HTTPClient.METHOD_POST, rota, {"username": nome.strip_edges(), "password": senha})
	if r["ok"]:
		session_token = r["data"]["token"]
		_salvar_sessao()
		await _retomar_sessao()
	return r


func logout() -> void:
	if logged_in():
		await request_json(HTTPClient.METHOD_POST, "/v1/auth/logout", {})
	session_token = ""
	_salvar_sessao()
	_geracao += 1
	account = {}
	party = {}
	profile = {}
	account_changed.emit(account)


func _salvar_sessao() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("sessao", "token", session_token)
	cfg.save(SESSAO)


func _retomar_sessao() -> void:
	var r := await request_json(HTTPClient.METHOD_GET, "/v1/me")
	if not r["ok"]:
		if r["status"] == 401:
			session_token = ""
			_salvar_sessao()
		return
	account = r["data"]["account"]
	_seq = int(r["data"]["events_seq"])
	_set_party(r["data"]["party"])
	account_changed.emit(account)
	Log.info("conta", "entrou como %s" % account["username"])
	refresh_friends()
	refresh_profile()
	_geracao += 1
	_laco_eventos(_geracao)


# ---------- eventos ----------

func _laco_eventos(geracao: int) -> void:
	var falhas := 0
	while geracao == _geracao and logged_in():
		var r := await request_json(HTTPClient.METHOD_GET, "/v1/events?since=%d&wait=%d" % [_seq, ESPERA_EVENTOS_S],
				null, ESPERA_EVENTOS_S + 8.0)
		if geracao != _geracao:
			return
		if not r["ok"]:
			if r["status"] == 401:
				notice.emit("Sua sessão expirou. Entre de novo.")
				logout()
				return
			falhas += 1
			await get_tree().create_timer(minf(2.0 * falhas, 10.0)).timeout
			continue
		falhas = 0
		for ev: Dictionary in r["data"]["events"]:
			_seq = maxi(_seq, int(ev["seq"]))
			_tratar(ev)


func _tratar(ev: Dictionary) -> void:
	var d: Dictionary = ev.get("data", {})
	match ev["type"]:
		"party":
			_set_party(d)
		"friends":
			refresh_friends()
		"friend_request":
			friend_request.emit(d.get("from", {}))
			refresh_friends()
		"invite":
			invite_received.emit(d)
		"invite_declined":
			notice.emit("%s recusou o convite." % d.get("by", {}).get("username", "?"))
		"kicked":
			notice.emit("Você foi removido do grupo.")
		"progress":
			last_progress = d
			progress.emit(d)
			refresh_profile()
		"match_found":
			var m := d.duplicate()
			m["host"] = _host_alcancavel(str(m.get("host", "")))
			match_found.emit(m)


## Se a sala se anunciou como "127.0.0.1" (servidor no mesmo PC do meta), usa o
## endereço do meta-servidor, que é o que este aparelho consegue alcançar.
func _host_alcancavel(h: String) -> String:
	if h.is_empty() or h == "127.0.0.1" or h == "::1" or h == "localhost":
		var u := base_url.trim_prefix("http://").trim_prefix("https://")
		return u.split("/")[0].rsplit(":", true, 1)[0]
	return h


func _set_party(p: Dictionary) -> void:
	party = p
	party_changed.emit(party)


# ---------- progressão (Etapa 9) ----------

func refresh_profile() -> void:
	var r := await request_json(HTTPClient.METHOD_GET, "/v1/profile")
	if r["ok"]:
		profile = r["data"]
		profile_changed.emit(profile)


func get_quests() -> Dictionary:
	return await request_json(HTTPClient.METHOD_GET, "/v1/quests")


func get_shop() -> Dictionary:
	return await request_json(HTTPClient.METHOD_GET, "/v1/shop")


## Compra com Faíscas (o servidor confere tudo). A chave evita cobrança dupla se
## o pedido for repetido depois de uma falha de rede.
func buy(item: String, preco: int, chave: String) -> Dictionary:
	var r := await request_json(HTTPClient.METHOD_POST, "/v1/shop/buy", {"item": item, "preco": preco, "chave": chave}, 10.0)
	if r["ok"]:
		profile = r["data"]["perfil"]
		profile_changed.emit(profile)
	return r


func get_season() -> Dictionary:
	return await request_json(HTTPClient.METHOD_GET, "/v1/season")


func get_ledger() -> Dictionary:
	return await request_json(HTTPClient.METHOD_GET, "/v1/ledger")


func get_history() -> Dictionary:
	return await request_json(HTTPClient.METHOD_GET, "/v1/history")


func equip(slot: String, item: String) -> Dictionary:
	var r := await request_json(HTTPClient.METHOD_POST, "/v1/loadout", {"slot": slot, "item": item})
	if r["ok"]:
		profile = r["data"]
		profile_changed.emit(profile)
	else:
		notice.emit(r["error"])
	return r


# ---------- amigos e grupo ----------

func refresh_friends() -> void:
	var r := await request_json(HTTPClient.METHOD_GET, "/v1/friends")
	if r["ok"]:
		friends = r["data"]
		friends_changed.emit(friends)


func _post(rota: String, corpo := {}) -> Dictionary:
	var r := await request_json(HTTPClient.METHOD_POST, rota, corpo)
	if not r["ok"]:
		notice.emit(r["error"])
	elif r["data"] is Dictionary and r["data"].has("members"):
		_set_party(r["data"])
	return r


func friend_add(nome: String) -> Dictionary:
	var r := await _post("/v1/friends/request", {"username": nome})
	if r["ok"]:
		notice.emit("Pedido enviado para %s." % nome)
		refresh_friends()
	return r


func friend_respond(id: int, aceitar: bool) -> Dictionary:
	var r := await _post("/v1/friends/respond", {"id": id, "accept": aceitar})
	refresh_friends()
	return r


func friend_remove(id: int) -> Dictionary:
	var r := await _post("/v1/friends/remove", {"id": id})
	refresh_friends()
	return r


func invite(id: int) -> Dictionary:
	var r := await _post("/v1/party/invite", {"id": id})
	if r["ok"]:
		notice.emit("Convite enviado.")
	return r


func invite_respond(convite: String, aceitar: bool) -> Dictionary:
	var r := await _post("/v1/party/respond", {"invite": convite, "accept": aceitar})
	if r["ok"] and r["data"].has("party"):
		_set_party(r["data"]["party"])
	return r


func party_leave() -> Dictionary:
	return await _post("/v1/party/leave")


func party_kick(id: int) -> Dictionary:
	return await _post("/v1/party/kick", {"id": id})


func party_promote(id: int) -> Dictionary:
	return await _post("/v1/party/promote", {"id": id})


func set_mode(modo: String) -> Dictionary:
	return await _post("/v1/party/mode", {"mode": modo})


func queue() -> Dictionary:
	return await _post("/v1/match/queue")


func cancel_queue() -> Dictionary:
	return await _post("/v1/match/cancel")


func match_left() -> void:
	if logged_in():
		await _post("/v1/match/left")


func private_create() -> Dictionary:
	return await _post("/v1/rooms/private")


func private_join(codigo: String) -> Dictionary:
	return await _post("/v1/rooms/join", {"code": codigo})


func private_start() -> Dictionary:
	return await _post("/v1/rooms/start")
