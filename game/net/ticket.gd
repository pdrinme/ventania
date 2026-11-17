class_name Ticket
extends RefCounted
## Ticket de entrada emitido pelo meta-servidor (backend/meta_server/partidas.py):
## "<base64 do JSON>.<HMAC-SHA256 em hexadecimal>", assinado com o segredo que o
## meta-servidor e os servidores de partida compartilham. O JSON tem a conta
## ("acc"), o nome ("name"), a porta da sala ("port") e a validade ("exp", Unix).


## Retorna os dados do ticket, ou {} se a assinatura, a sala ou a validade não baterem.
static func verify(segredo: String, texto: String, porta: int) -> Dictionary:
	var partes := texto.split(".")
	if segredo.is_empty() or partes.size() != 2 or partes[1].length() != 64:
		return {}
	var h := HMACContext.new()
	if h.start(HashingContext.HASH_SHA256, segredo.to_utf8_buffer()) != OK:
		return {}
	h.update(partes[0].to_ascii_buffer())
	var esperado := h.finish().hex_encode()
	if not _iguais(esperado, partes[1].to_lower()):
		return {}
	var json: Variant = JSON.parse_string(Marshalls.base64_to_utf8(partes[0]))
	if not (json is Dictionary):
		return {}
	var d: Dictionary = json
	if int(d.get("port", -1)) != porta or float(d.get("exp", 0)) < Time.get_unix_time_from_system():
		return {}
	if int(d.get("acc", 0)) <= 0 or str(d.get("name", "")).is_empty():
		return {}
	return d


## Comparação em tempo constante (não vaza quantos caracteres batem).
static func _iguais(a: String, b: String) -> bool:
	if a.length() != b.length():
		return false
	var dif := 0
	for i in a.length():
		dif |= a.unicode_at(i) ^ b.unicode_at(i)
	return dif == 0


## Para testes: gera um ticket igual ao do meta-servidor.
static func sign(segredo: String, dados: Dictionary) -> String:
	var corpo := Marshalls.utf8_to_base64(JSON.stringify(dados))
	var h := HMACContext.new()
	h.start(HashingContext.HASH_SHA256, segredo.to_utf8_buffer())
	h.update(corpo.to_ascii_buffer())
	return corpo + "." + h.finish().hex_encode()
