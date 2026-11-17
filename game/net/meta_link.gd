class_name MetaLink
extends Node
## Liga as salas de um servidor dedicado ao meta-servidor (Etapa 8): a cada 2 s
## cada sala manda um heartbeat (porta, modo, estado, humanos, contas presentes)
## e recebe as ordens (sala privada; começar a partida). O segredo vai no
## cabeçalho X-Ventania-Server e também confere os tickets dos jogadores.

const INTERVALO_S := 2.0

var url := ""
var segredo := ""
var anunciar := ""              # IP/host que os jogadores usam (vazio: o meta usa o IP de origem)
var salas: Array[GameServer] = []
var ultimo_erro := ""
var _t := 0.0
var _ocupado := {}              # sala -> pedido em andamento


func _process(delta: float) -> void:
	_t += delta
	if _t < INTERVALO_S:
		return
	_t = 0.0
	for s in salas:
		if not _ocupado.get(s, false):
			_enviar(s)


func _enviar(s: GameServer) -> void:
	_ocupado[s] = true
	var corpo := {"port": s.porta, "mode": "br" if s.partida else "treino",
			"state": _estado(s), "humans": s.humanos(), "max": s.max_jogadores, "accounts": s.accounts()}
	if not anunciar.is_empty():
		corpo["host"] = anunciar
	var req := HTTPRequest.new()
	req.timeout = 5.0
	add_child(req)
	req.request(url.trim_suffix("/") + "/v1/servers/heartbeat",
			PackedStringArray(["Content-Type: application/json", "X-Ventania-Server: " + segredo]),
			HTTPClient.METHOD_POST, JSON.stringify(corpo))
	var r: Array = await req.request_completed
	req.queue_free()
	_ocupado[s] = false
	if r[0] != HTTPRequest.RESULT_SUCCESS or r[1] != 200:
		var erro := "meta-servidor: %s" % ("sem resposta" if r[0] != HTTPRequest.RESULT_SUCCESS else "HTTP %d" % r[1])
		if r[1] == 403:
			erro = "meta-servidor recusou o segredo (confira --segredo)"
		if erro != ultimo_erro:
			Log.warn("servidor", erro)
		ultimo_erro = erro
		return
	if not ultimo_erro.is_empty():
		Log.info("servidor", "meta-servidor conectado")
		ultimo_erro = ""
	var d: Variant = JSON.parse_string((r[3] as PackedByteArray).get_string_from_utf8())
	if d is Dictionary:
		s.privada = bool(d.get("private", false))
		if d.get("start", false):
			s.forcar_inicio = true


static func _estado(s: GameServer) -> String:
	if s.partida == null:
		return "treino"
	match s.partida.estado:
		Protocol.MATCH_ESPERA: return "espera"
		Protocol.MATCH_CONTAGEM: return "contagem"
		Protocol.MATCH_ONIBUS: return "onibus"
		Protocol.MATCH_JOGO: return "jogo"
	return "fim"
