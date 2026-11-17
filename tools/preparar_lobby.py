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
