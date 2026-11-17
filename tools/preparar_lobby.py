"""Cria contas, amizades e um grupo num meta-servidor de teste (para capturas do lobby).
Uso: python3 tools/preparar_lobby.py http://127.0.0.1:8090"""
import json
import sys
import urllib.request

URL = sys.argv[1]


def chamar(caminho, corpo=None, token=None):
    h = {"Content-Type": "application/json"}
    if token:
        h["Authorization"] = "Bearer " + token
    req = urllib.request.Request(URL + caminho, data=json.dumps(corpo).encode() if corpo is not None else None,
                                 headers=h, method="POST" if corpo is not None else "GET")
    with urllib.request.urlopen(req, timeout=5) as r:
        return json.loads(r.read() or b"null")


def conta(nome):
    return chamar("/v1/auth/register", {"username": nome, "password": "senha123"})


ana, bia, caio, duda, eli = (conta(n) for n in ("Ana", "Bia", "Caio", "Duda", "Eli"))
for amigo in (bia, duda, eli):
    chamar("/v1/friends/request", {"username": amigo["account"]["username"]}, ana["token"])
    chamar("/v1/friends/respond", {"id": ana["account"]["id"], "accept": True}, amigo["token"])
chamar("/v1/friends/request", {"username": "Ana"}, caio["token"])
chamar("/v1/party/invite", {"id": bia["account"]["id"]}, ana["token"])
ev = chamar("/v1/events?since=0&wait=0", token=bia["token"])["events"]
conv = [e for e in ev if e["type"] == "invite"][-1]["data"]["id"]
chamar("/v1/party/respond", {"invite": conv, "accept": True}, bia["token"])
chamar("/v1/party/promote", {"id": bia["account"]["id"]}, ana["token"])
chamar("/v1/party/promote", {"id": ana["account"]["id"]}, bia["token"])
print("pronto")

# Etapa 9: duas partidas para a Ana (como se o servidor de partida tivesse relatado)
import os  # noqa: E402
segredo = os.environ.get("VENTANIA_SEGREDO")
if segredo:
    for i, dados in enumerate([{"colocacao": 3, "eliminacoes": 4, "tempo_s": 720, "baus": 6, "coleta": 400, "construcoes": 30},
                               {"colocacao": 1, "venceu": True, "eliminacoes": 7, "tempo_s": 900, "baus": 5, "coleta": 250}]):
        req = urllib.request.Request(URL + "/v1/servers/report", method="POST", headers={
            "Content-Type": "application/json", "X-Ventania-Server": segredo},
            data=json.dumps({"match_id": f"captura-{i}", "mode": "br", "total": 16, "port": 24800,
                             "players": [{"acc": ana["account"]["id"], **dados}]}).encode())
        with urllib.request.urlopen(req, timeout=5) as r:
            print("relatório", json.loads(r.read())["status"])
