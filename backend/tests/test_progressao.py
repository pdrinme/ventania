"""Etapa 9: XP, níveis, missões, Faíscas (ledger), desbloqueios, equipados e relatório de partida."""
import copy
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from meta_server import db  # noqa: E402
from meta_server.contas import Contas  # noqa: E402
from meta_server.http import HttpError  # noqa: E402
from meta_server.progressao import Progressao, carregar_config, validar  # noqa: E402
from meta_server.social import Eventos  # noqa: E402
from meta_server import config  # noqa: E402
from test_meta_server import ServidorDeTeste  # noqa: E402
from test_social import Api, CFG  # noqa: E402

DIA = 1_795_000_000.0          # um instante fixo (UTC)


class Base(unittest.TestCase):
    def setUp(self):
        self.con = db.connect(":memory:")
        db.migrate(self.con)
        self.t = [DIA]
        self.ev = Eventos()
        self.contas = Contas(self.con, config.Config(pbkdf2_iter=1000))
        self.p = Progressao(self.con, self.contas, self.ev, agora=lambda: self.t[0])
        self.a = self.contas.registrar("Ana", "senha123")["account"]["id"]
        self.b = self.contas.registrar("Bia", "senha123")["account"]["id"]

    def tearDown(self):
        self.con.close()

    def relatorio(self, mid, **jogadores):
        players = [{"acc": acc, **dados} for acc, dados in jogadores.items()]
        return self.p.aplicar_relatorio({"match_id": mid, "mode": "br", "total": 16, "players": players}, "sala")


class TestProgressao(Base):
    def test_perfil_inicial(self):
        pf = self.p.perfil(self.a)
        self.assertEqual((pf["level"], pf["xp_total"], pf["sparks"]), (1, 0, 0))
        self.assertEqual({u["item"] for u in pf["unlocks"]}, {"traje_recruta", "picareta_padrao", "planador_padrao", "traje_brisa"})
        self.assertEqual(pf["equipped"]["traje"], "traje_recruta")
        self.assertEqual({u["item"]: u["source"] for u in pf["unlocks"]}["traje_brisa"], "presente")

    def test_presente_chega_em_conta_antiga_e_equipa(self):
        self.p.garantir(self.a)
        self.con.execute("DELETE FROM unlocks WHERE item_id = 'traje_brisa'")       # conta de antes do presente
        tem = lambda: self.con.execute("SELECT 1 FROM unlocks WHERE account_id = ? AND item_id = 'traje_brisa'", (self.a,)).fetchone()
        self.assertIsNone(tem())
        pf = self.p.perfil(self.a)              # qualquer consulta ao perfil entrega o presente
        self.assertIsNotNone(tem())
        self.assertIn("traje_brisa", {u["item"] for u in pf["unlocks"]})
        self.assertEqual(self.p.equipar(self.a, "traje", "traje_brisa")["equipped"]["traje"], "traje_brisa")
        self.assertEqual(self.p.equipado(self.a, "traje"), "traje_brisa")

    def test_xp_da_partida_e_idempotencia(self):
        r = self.relatorio("m1", **{str(self.a): {"colocacao": 1, "venceu": True, "eliminacoes": 4, "tempo_s": 600, "baus": 3}})
        self.assertEqual(r["status"], "aplicado")
        pf = self.p.perfil(self.a)
        # 50 + 10 min*10 + 4*40 + 300 vitória + 120 top5 + 3*10 = 760 (+ missões que porventura concluiu)
        self.assertGreaterEqual(pf["xp_total"], 760)
        self.assertEqual((pf["matches"], pf["wins"], pf["kills"]), (1, 1, 4))
        ev = [e for e in self.ev.desde(self.a, 0) if e["type"] == "progress"][-1]["data"]
        self.assertEqual(ev["xp_total"], pf["xp_total"])
        self.assertIn("Vitória!", [x["motivo"] for x in ev["xp"]])
        # o mesmo relatório de novo não conta
        self.assertEqual(self.relatorio("m1", **{str(self.a): {"colocacao": 1, "venceu": True}})["status"], "repetido")
        self.assertEqual(self.p.perfil(self.a)["xp_total"], pf["xp_total"])

    def test_numeros_absurdos_sao_limitados(self):
        self.relatorio("m2", **{str(self.a): {"colocacao": 1, "venceu": True, "eliminacoes": 99999, "tempo_s": 10 ** 9, "baus": 10 ** 6}})
        pf = self.p.perfil(self.a)
        self.assertLessEqual(pf["kills"], 15)
        # partida (máx. ~1.600) + missões diárias e semanais que essa partida conclui; nada de desafio da temporada
        self.assertLess(pf["xp_total"], 6000)
        self.assertFalse(any(q["concluida"] for q in self.p.missoes(self.a).get("temporada", {}).get("quests", [])))

    def test_nivel_faiscas_ledger_e_recompensa(self):
        self.relatorio("m3", **{str(self.a): {"colocacao": 1, "venceu": True, "eliminacoes": 15, "tempo_s": 1200, "baus": 20,
                                               "coleta": 2000, "construcoes": 400}})
        pf = self.p.perfil(self.a)
        self.assertGreaterEqual(pf["level"], 2)
        self.assertIn("emote_aceno", {u["item"] for u in pf["unlocks"]})
        aceno = [u for u in pf["unlocks"] if u["item"] == "emote_aceno"][0]
        self.assertEqual(aceno["source"], "nivel:2")
        led = self.p.ledger(self.a)
        self.assertEqual(sum(x["delta"] for x in led), pf["sparks"])
        self.assertEqual(led[0]["balance_after"], pf["sparks"])
        self.assertTrue(any(x["reason"] == "Nível 2" for x in led))

    def test_missoes_do_dia_e_troca_de_periodo(self):
        m = self.p.missoes(self.a)
        self.assertEqual(len(m["diaria"]["quests"]), 3)
        self.assertEqual(len(m["semanal"]["quests"]), 5)
        self.assertEqual(m, self.p.missoes(self.a))                      # determinístico
        q = m["diaria"]["quests"][0]
        tipo_para_campo = {"partidas": None, "eliminacoes": "eliminacoes", "baus": "baus", "minutos_vivo": "tempo_s",
                           "top10": "colocacao", "vitorias": None, "coleta": "coleta", "construcoes": "construcoes",
                           "dano": "dano", "curas": "curas"}
        dados = {"colocacao": 3, "venceu": False, "tempo_s": 60 * q["meta"], "eliminacoes": min(15, q["meta"]),
                 "baus": q["meta"], "coleta": q["meta"], "construcoes": q["meta"], "dano": q["meta"], "curas": q["meta"]}
        for i in range(q["meta"] if q["tipo"] == "partidas" else 1):
            self.relatorio(f"q{i}", **{str(self.a): dados})
        m2 = self.p.missoes(self.a)
        q2 = [x for x in m2["diaria"]["quests"] if x["id"] == q["id"]][0]
        self.assertTrue(q2["concluida"], (q, q2, tipo_para_campo[q["tipo"]]))
        self.assertTrue(any(x["reason"].startswith("Missão") for x in self.p.ledger(self.a)))
        # dia seguinte: missões novas (ou as mesmas, sem progresso)
        self.t[0] += 86400
        m3 = self.p.missoes(self.a)
        self.assertNotEqual(m3["diaria"]["period"], m2["diaria"]["period"])
        self.assertTrue(all(not x["concluida"] and x["progresso"] == 0 for x in m3["diaria"]["quests"]))

    def test_equipar_so_o_que_tem(self):
        with self.assertRaises(HttpError) as e:
            self.p.equipar(self.a, "emote", "emote_aceno")
        self.assertEqual(e.exception.status, 403)
        with self.assertRaises(HttpError):
            self.p.equipar(self.a, "traje", "picareta_padrao")      # categoria errada
        with self.assertRaises(HttpError):
            self.p.equipar(self.a, "traje", "inexistente")
        self.con.execute("INSERT INTO unlocks VALUES (?, 'emote_aceno', 'teste', 0)", (self.a,))
        self.assertEqual(self.p.equipar(self.a, "emote", "emote_aceno")["equipped"]["emote"], "emote_aceno")

    def test_saldo_nunca_negativo(self):
        self.p.garantir(self.a)
        with self.assertRaises(HttpError):
            with self.p._tx():
                self.p._creditar(self.a, -1, "teste", "neg:1")
        self.assertEqual(self.p.perfil(self.a)["sparks"], 0)
        self.assertEqual(self.p.ledger(self.a), [])

    def test_treino_e_conta_inexistente_nao_contam(self):
        r = self.p.aplicar_relatorio({"match_id": "t1", "mode": "treino", "players": [{"acc": self.a}]}, "s")
        self.assertEqual(r["status"], "ignorado")
        r = self.relatorio("m9", **{"999": {"colocacao": 1}, str(self.b): {"colocacao": 2}})
        self.assertEqual(r["jogadores"], 1)

    def test_config_invalida_impede_subir(self):
        cfg = carregar_config()
        ruim = copy.deepcopy(cfg)
        ruim["progressao"]["itens_iniciais"].append("nao_existe")
        with self.assertRaises(ValueError):
            validar(ruim)
        ruim = copy.deepcopy(cfg)
        ruim["missoes"]["diarias"][0]["tipo"] = "voar"
        with self.assertRaises(ValueError):
            validar(ruim)


class TestApiProgressao(unittest.TestCase):
    def test_relatorio_exige_segredo_e_perfil_pela_api(self):
        with ServidorDeTeste(CFG) as s:
            a = Api(s)
            tok, conta = a.conta("Ana")
            corpo = {"match_id": "x1", "mode": "br", "total": 16, "port": 24800,
                     "players": [{"acc": conta, "colocacao": 2, "eliminacoes": 3, "tempo_s": 400}]}
            self.assertEqual(a.chamar("/v1/servers/report", corpo, cab={"X-Ventania-Server": "errado"})[0], 403)
            self.assertEqual(a.chamar("/v1/servers/report", corpo, token=tok)[0], 403)   # cliente não pode
            st, r = a.chamar("/v1/servers/report", corpo, cab={"X-Ventania-Server": "segredo-de-teste"})
            self.assertEqual((st, r["status"]), (200, "aplicado"))
            pf = a.chamar("/v1/profile", token=tok)[1]
            self.assertGreater(pf["xp_total"], 0)
            self.assertEqual(a.chamar("/v1/history", token=tok)[1]["matches"][0]["placement"], 2)
            self.assertEqual(len(a.chamar("/v1/quests", token=tok)[1]["diaria"]["quests"]), 3)
            self.assertEqual(a.chamar("/v1/loadout", {"slot": "emote", "item": "emote_aceno"}, tok)[0], 403)
            self.assertEqual(a.eventos(tok)[-1]["type"], "progress")

    def test_traje_equipado_vai_no_ticket_e_no_grupo(self):
        from meta_server.partidas import verificar
        with ServidorDeTeste(CFG) as s:
            a = Api(s)
            tok, conta = a.conta("Ana")
            self.assertEqual(a.chamar("/v1/loadout", {"slot": "traje", "item": "traje_brisa"}, tok)[0], 200)
            self.assertEqual(a.chamar("/v1/party", token=tok)[1]["members"][0]["traje"], "traje_brisa")
            a.heartbeat(24800)
            a.chamar("/v1/match/queue", {}, tok)
            ev = [e for e in a.eventos(tok) if e["type"] == "match_found"][-1]["data"]
            t = verificar("segredo-de-teste", ev["ticket"])
            self.assertEqual((t["traje"], t["pic"], t["plan"]), ("traje_brisa", "picareta_padrao", "planador_padrao"))


if __name__ == "__main__":
    unittest.main()
