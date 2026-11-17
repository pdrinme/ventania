class_name MetaApi
extends Node
## Cliente HTTP/JSON do meta-servidor (ARCHITECTURE §5). Cada pedido cria um
## HTTPRequest próprio, com tempo limite. Resultado sempre no formato:
##   {"ok": bool, "status": int (HTTP, 0 se não conectou), "data": Variant, "error": String}

const TIMEOUT_S := 5.0

var base_url := "http://127.0.0.1:8080"
var session_token := ""


func request_json(method: HTTPClient.Method, path: String, body: Variant = null, timeout_s := TIMEOUT_S) -> Dictionary:
	var req := HTTPRequest.new()
	req.timeout = timeout_s
	add_child(req)
	var headers := PackedStringArray(["Accept: application/json",
			"X-Ventania-Version: %s" % Version.GAME, "X-Ventania-Protocol: %d" % Version.PROTOCOL])
	var corpo := ""
	if body != null:
		headers.append("Content-Type: application/json")
		corpo = JSON.stringify(body)
	if not session_token.is_empty():
		headers.append("Authorization: Bearer " + session_token)
	var url := base_url.trim_suffix("/") + path
	var err := req.request(url, headers, method, corpo)
	if err != OK:
		req.queue_free()
		return {"ok": false, "status": 0, "data": null, "error": "URL inválida: " + url}
	var r: Array = await req.request_completed
	req.queue_free()
	var resultado: int = r[0]
	var status: int = r[1]
	var bytes: PackedByteArray = r[3]
	if resultado != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "status": 0, "data": null, "error": _erro_rede(resultado)}
	var dados: Variant = null
	if bytes.size() > 0:
		var json := JSON.new()
		if json.parse(bytes.get_string_from_utf8()) != OK:
			return {"ok": false, "status": status, "data": null, "error": "Resposta inválida do servidor"}
		dados = json.data
	var ok := status >= 200 and status < 300
	var msg := ""
	if not ok:
		msg = str(dados.get("error", "HTTP %d" % status)) if dados is Dictionary else "HTTP %d" % status
	return {"ok": ok, "status": status, "data": dados, "error": msg}


## Verifica se o servidor responde e é compatível. Retorna
## {"state": "online"|"offline"|"incompatible", "info": Dictionary, "error": String}
func check_health() -> Dictionary:
	var r := await request_json(HTTPClient.METHOD_GET, "/v1/health")
	if not r["ok"] or not (r["data"] is Dictionary):
		return {"state": "offline", "info": {}, "error": r["error"]}
	var info: Dictionary = r["data"]
	if int(info.get("protocol_version", -1)) != Version.PROTOCOL:
		return {"state": "incompatible", "info": info,
				"error": "Servidor usa protocolo %s; este jogo usa %d. Atualize o jogo ou o servidor." % [info.get("protocol_version"), Version.PROTOCOL]}
	return {"state": "online", "info": info, "error": ""}


static func _erro_rede(resultado: int) -> String:
	match resultado:
		HTTPRequest.RESULT_CANT_CONNECT, HTTPRequest.RESULT_CONNECTION_ERROR:
			return "Não foi possível conectar ao servidor"
		HTTPRequest.RESULT_CANT_RESOLVE:
			return "Endereço do servidor não encontrado"
		HTTPRequest.RESULT_TIMEOUT:
			return "O servidor não respondeu a tempo"
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
			return "Erro de conexão segura (TLS)"
	return "Erro de rede (%d)" % resultado
