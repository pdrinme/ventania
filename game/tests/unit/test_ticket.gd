extends TestCase
## Etapa 8: ticket do meta-servidor (assinado em Python, conferido em GDScript).

const DO_PYTHON := "eyJhY2MiOjcsIm5hbWUiOiJWZW50aW5obyIsInBvcnQiOjI0ODAwLCJleHAiOjQxMDI0NDQ4MDAsIm4iOiJhYjEyIn0=.39a8cdb9834765fa8759cdcfb27f6eda6792a6474d22552de89b32bda6a76dd9"


func test_ticket_do_meta_servidor_confere() -> void:
	var d := Ticket.verify("segredo-x", DO_PYTHON, 24800)
	assert_eq(int(d.get("acc", 0)), 7)
	assert_eq(d.get("name", ""), "Ventinho")


func test_ticket_recusado() -> void:
	assert_true(Ticket.verify("outro", DO_PYTHON, 24800).is_empty(), "segredo errado")
	assert_true(Ticket.verify("segredo-x", DO_PYTHON, 24801).is_empty(), "outra sala")
	var adulterado := DO_PYTHON.substr(0, 10) + ("A" if DO_PYTHON[10] != "A" else "B") + DO_PYTHON.substr(11)
	assert_true(Ticket.verify("segredo-x", adulterado, 24800).is_empty(), "conteúdo alterado")
	var vencido := Ticket.sign("segredo-x", {"acc": 7, "name": "X", "port": 24800, "exp": 1000})
	assert_true(Ticket.verify("segredo-x", vencido, 24800).is_empty(), "vencido")
	assert_true(Ticket.verify("segredo-x", "", 24800).is_empty())
	assert_true(Ticket.verify("", DO_PYTHON, 24800).is_empty())


func test_hello_leva_o_ticket() -> void:
	var h := Protocol.unpack_hello(Protocol.pack_hello("Ana", 5, DO_PYTHON))
	assert_eq(h["ticket"], DO_PYTHON)
	assert_eq(h["token"], 5)
	assert_eq(Protocol.unpack_hello(Protocol.pack_hello("Ana"))["ticket"], "")
