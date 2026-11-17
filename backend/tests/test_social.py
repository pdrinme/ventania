"""Etapa 8: contas, amigos, grupos, convites, eventos, matchmaking, tickets e sala privada."""
import json
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from meta_server import config  # noqa: E402
from meta_server.partidas import verificar  # noqa: E402
from test_meta_server import ServidorDeTeste  # noqa: E402

CFG = config.Config(pbkdf2_iter=1000, server_secret="segredo-de-teste", longpoll_s=2.0)


class Api:
    def __init__(self, s):
        self.s = s

    def chamar(self, caminho, corpo=None, token=None, metodo=None, cab=None):
        h = dict(cab or {})
        if token:
            h["Authorization"] = "Bearer " + token
        dados = json.dumps(corpo).encode() if corpo is not None else None
        if dados is not None:
            h["Content-Type"] = "application/json"
        return self.s.get(caminho, metodo or ("POST" if corpo is not None else "GET"), dados, h)

    def conta(self, nome, senha="senha123"):
        st, d = self.chamar("/v1/auth/register", {"username": nome, "password": senha})
        assert st == 201, (st, d)
        return d["token"], d["account"]["id"]

    def heartbeat(self, porta, segredo="segredo-de-teste", **extra):
        corpo = {"port": porta, "mode": "br", "state": "espera", "humans": 0, "max": 16, "accounts": [], **extra}
        return self.chamar("/v1/servers/heartbeat", corpo, cab={"X-Ventania-Server": segredo})

    def eventos(self, token, since=0, wait=0):
        return self.chamar(f"/v1/events?since={since}&wait={wait}", token=token)[1]["events"]


class TestContas(unittest.TestCase):
    def test_cadastro_login_e_sessao(self):
        with ServidorDeTeste(CFG) as s:
            a = Api(s)
            tok, _ = a.conta("Brisa")
            self.assertEqual(a.chamar("/v1/me", token=tok)[1]["account"]["username"], "Brisa")
            self.assertEqual(a.chamar("/v1/auth/register", {"username": "brisa", "password": "outra123"})[0], 409)
            self.assertEqual(a.chamar("/v1/auth/register", {"username": "ab", "password": "senha123"})[0], 400)
            self.assertEqual(a.chamar("/v1/auth/register", {"username": "Vento", "password": "123"})[0], 400)
            self.assertEqual(a.chamar("/v1/auth/login", {"username": "BRISA", "password": "errada"})[0], 401)
            st, d = a.chamar("/v1/auth/login", {"username": "BRISA", "password": "senha123"})
            self.assertEqual(st, 200)
            self.assertEqual(a.chamar("/v1/auth/logout", {}, token=d["token"])[0], 200)
            self.assertEqual(a.chamar("/v1/me", token=d["token"])[0], 401)
            self.assertEqual(a.chamar("/v1/me", token="inventado")[0], 401)
            self.assertEqual(a.chamar("/v1/me")[0], 401)

    def test_senha_guardada_com_hash(self):
        with ServidorDeTeste(CFG) as s:
            Api(s).conta("Garoa", "minhasenha")
            row = s.con.execute("SELECT * FROM accounts").fetchone()
            self.assertNotIn(b"minhasenha", bytes(row["pass_hash"]))
            self.assertEqual(len(row["pass_salt"]), 16)

    def test_limite_de_tentativas(self):
        with ServidorDeTeste(CFG) as s:
            a = Api(s)
            a.conta("Neblina")
            codigos = [a.chamar("/v1/auth/login", {"username": "Neblina", "password": "x" * 6})[0] for _ in range(10)]
            self.assertIn(429, codigos)


class TestSocial(unittest.TestCase):
    def test_amizade_grupo_e_convite(self):
        with ServidorDeTeste(CFG) as s:
            a = Api(s)
            ta, ia = a.conta("Ana")
            tb, ib = a.conta("Bia")
            self.assertEqual(a.chamar("/v1/friends/request", {"username": "ninguem"}, ta)[0], 404)
            self.assertEqual(a.chamar("/v1/friends/request", {"username": "bia"}, ta)[0], 200)
            self.assertEqual(a.eventos(tb)[-1]["type"], "friend_request")
            self.assertEqual(a.chamar("/v1/friends", token=tb)[1]["incoming"][0]["username"], "Ana")
            # convite antes de serem amigos: proibido
            self.assertEqual(a.chamar("/v1/party/invite", {"id": ib}, ta)[0], 403)
            self.assertEqual(a.chamar("/v1/friends/respond", {"id": ia, "accept": True}, tb)[0], 200)
            amigos = a.chamar("/v1/friends", token=ta)[1]["friends"]
            self.assertEqual([(f["username"], f["status"]) for f in amigos], [("Bia", "lobby")])
            st, d = a.chamar("/v1/party/invite", {"id": ib}, ta)
            self.assertEqual(st, 200)
            conv = [e for e in a.eventos(tb) if e["type"] == "invite"][-1]["data"]
            self.assertEqual(conv["from"]["username"], "Ana")
            st, d = a.chamar("/v1/party/respond", {"invite": conv["id"], "accept": True}, tb)
            self.assertEqual(st, 200)
            grupo = a.chamar("/v1/party", token=ta)[1]
            self.assertEqual([m["username"] for m in grupo["members"]], ["Ana", "Bia"])
            self.assertEqual(grupo["leader"], ia)
            self.assertTrue(any(e["type"] == "party" for e in a.eventos(ta)))
            # só o líder escolhe o modo; liderança passa; sair do grupo
            self.assertEqual(a.chamar("/v1/party/mode", {"mode": "treino"}, tb)[0], 403)
            self.assertEqual(a.chamar("/v1/party/promote", {"id": ib}, ta)[0], 200)
            self.assertEqual(a.chamar("/v1/party/mode", {"mode": "treino"}, tb)[1]["mode"], "treino")
            self.assertEqual(a.chamar("/v1/party/leave", {}, ta)[1]["members"][0]["username"], "Ana")
            self.assertEqual(len(a.chamar("/v1/party", token=tb)[1]["members"]), 1)

    def test_long_polling_acorda_com_evento(self):
        import threading
        import time
        with ServidorDeTeste(CFG) as s:
            a = Api(s)
            ta, _ = a.conta("Ana")
            tb, _ = a.conta("Bia")
            res = {}

            def esperar():
                t = time.monotonic()
                res["ev"] = a.eventos(tb, 0, 2)
                res["t"] = time.monotonic() - t
            th = threading.Thread(target=esperar)
            th.start()
            time.sleep(0.3)
            a.chamar("/v1/friends/request", {"username": "Bia"}, ta)
            th.join(5)
            self.assertEqual(res["ev"][0]["type"], "friend_request")
            self.assertLess(res["t"], 1.5)


class TestPartidas(unittest.TestCase):
    def test_heartbeat_exige_segredo(self):
        with ServidorDeTeste(CFG) as s:
            self.assertEqual(Api(s).heartbeat(24800, segredo="errado")[0], 403)

    def test_fila_leva_o_grupo_para_a_sala_com_ticket(self):
        with ServidorDeTeste(CFG) as s:
            a = Api(s)
            ta, ia = a.conta("Ana")
            tb, ib = a.conta("Bia")
            a.chamar("/v1/friends/request", {"username": "Bia"}, ta)
            a.chamar("/v1/friends/respond", {"id": ia, "accept": True}, tb)
            a.chamar("/v1/party/invite", {"id": ib}, ta)
            conv = [e for e in a.eventos(tb) if e["type"] == "invite"][-1]["data"]["id"]
            a.chamar("/v1/party/respond", {"invite": conv, "accept": True}, tb)
            self.assertEqual(a.chamar("/v1/match/queue", {}, tb)[0], 403)      # não é líder
            self.assertEqual(a.chamar("/v1/match/queue", {}, ta)[1]["state"], "fila")   # sem servidor: espera
            a.heartbeat(24801, state="jogo")              # em jogo: não serve
            a.heartbeat(24800, humans=15)                 # sem vaga para 2
            self.assertEqual(a.chamar("/v1/party", token=ta)[1]["state"], "fila")
            st, ordem = a.heartbeat(24802, humans=3)      # serve
            grupo = a.chamar("/v1/party", token=ta)[1]
            self.assertEqual(grupo["state"], "partida")
            self.assertEqual(grupo["match"]["port"], 24802)
            for tok, conta, nome in ((ta, ia, "Ana"), (tb, ib, "Bia")):
                ev = [e for e in a.eventos(tok) if e["type"] == "match_found"][-1]["data"]
                self.assertEqual(ev["port"], 24802)
                t = verificar("segredo-de-teste", ev["ticket"])
                self.assertEqual((t["acc"], t["name"], t["port"]), (conta, nome, 24802))
                self.assertIsNone(verificar("outro-segredo", ev["ticket"]))
            # as 2 vagas ficam reservadas e o servidor sabe que tem gente chegando
            self.assertEqual(a.heartbeat(24802, humans=3)[1]["pending"], 2)
            self.assertEqual(a.heartbeat(24802, humans=5, accounts=[ia, ib])[1]["pending"], 0)
            salas = {r["port"]: r for r in a.chamar("/v1/rooms", token=ta)[1]["rooms"]}
            self.assertEqual(salas[24802]["humans"], 5)
            self.assertEqual(a.chamar("/v1/match/left", {}, tb)[1]["state"], "lobby")

    def test_sala_privada_com_codigo(self):
        with ServidorDeTeste(CFG) as s:
            a = Api(s)
            ta, ia = a.conta("Ana")
            tc, ic = a.conta("Caio")
            self.assertEqual(a.chamar("/v1/rooms/private", {}, ta)[0], 409)   # nenhuma sala
            a.heartbeat(24800)
            st, d = a.chamar("/v1/rooms/private", {}, ta)
            self.assertEqual(st, 200)
            codigo = d["code"]
            self.assertEqual(len(codigo), 5)
            self.assertTrue(a.heartbeat(24800)[1]["private"])
            # a fila pública não usa a sala privada
            a.chamar("/v1/match/queue", {}, tc)
            self.assertEqual(a.chamar("/v1/party", token=tc)[1]["state"], "fila")
            a.chamar("/v1/match/cancel", {}, tc)
            self.assertEqual(a.chamar("/v1/rooms/join", {"code": "ZZZZZ"}, tc)[0], 404)
            st, d = a.chamar("/v1/rooms/join", {"code": codigo.lower()}, tc)
            self.assertEqual((st, d["port"]), (200, 24800))
            ev = [e for e in a.eventos(tc) if e["type"] == "match_found"][-1]["data"]
            self.assertEqual(verificar("segredo-de-teste", ev["ticket"])["port"], 24800)
            self.assertEqual(a.chamar("/v1/rooms/start", {}, tc)[0], 404)      # Caio não é o dono
            a.chamar("/v1/rooms/start", {}, ta)
            self.assertTrue(a.heartbeat(24800, humans=2, accounts=[ia, ic])[1]["start"])


if __name__ == "__main__":
    unittest.main()
