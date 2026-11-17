"""Etapa 10: passe de batalha gratuito (temporada, níveis, recompensas, desafios, validação)."""
import copy
import os
import subprocess
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from meta_server.progressao import _data, carregar_config, estimar_horas, validar_temporada  # noqa: E402
from test_progressao import Base, DIA  # noqa: E402

RAIZ = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


class TestPasse(Base):
    def test_temporada_ativa_e_nivel_1_na_hora(self):
        pa = self.p.passe(self.a)
        self.assertTrue(pa["ativa"])
        self.assertEqual((pa["id"], pa["nivel"], pa["maximo"]), ("t1", 1, 50))
        self.assertTrue(pa["niveis"][0]["obtido"])
        self.assertEqual(self.p.perfil(self.a)["sparks"], 50)          # recompensa do nível 1
        self.p.passe(self.a)
        self.assertEqual(self.p.perfil(self.a)["sparks"], 50)          # não repete
        self.assertEqual(len(pa["desafios"]), 8)

    def test_xp_sobe_o_passe_e_entrega_o_traje(self):
        xp_por = self.p.temporada()["xp_por_nivel"]
        # várias partidas grandes até passar do nível 8 (Recruta Tormenta)
        i = 0
        while self.p.passe(self.a)["nivel"] < 9 and i < 60:
            self.relatorio(f"p{i}", **{str(self.a): {"colocacao": 1, "venceu": True, "eliminacoes": 15, "tempo_s": 1200,
                                                      "baus": 20, "coleta": 1000, "construcoes": 200}})
            i += 1
        pa = self.p.passe(self.a)
        self.assertGreaterEqual(pa["nivel"], 9)
        self.assertEqual(pa["xp"] // xp_por + 1, pa["nivel"])
        tormenta = [u for u in self.p.perfil(self.a)["unlocks"] if u["item"] == "traje_tormenta"]
        self.assertEqual(tormenta[0]["source"], "passe:t1:8")
        self.assertTrue(pa["niveis"][7]["obtido"])
        self.assertFalse(pa["niveis"][49]["obtido"])
        # a Faísca de cada nível entrou uma vez só no extrato
        motivos = [e["reason"] for e in self.p.ledger(self.a, 200)]
        self.assertEqual(motivos.count("Passe Temporada 1: Primeiros Ventos: nível 2"), 1)
        ev = [e for e in self.ev.desde(self.a, 0) if e["type"] == "progress"][-1]["data"]
        self.assertIsNotNone(ev["passe"])

    def test_fora_da_temporada_nao_sobe(self):
        self.t[0] = _data("2027-02-01T00:00:00Z")
        self.assertFalse(self.p.passe(self.a)["ativa"])
        self.relatorio("fora", **{str(self.a): {"colocacao": 1, "venceu": True, "tempo_s": 600}})
        self.assertEqual(self.con.execute("SELECT COUNT(*) FROM season_progress").fetchone()[0], 0)
        self.assertGreater(self.p.perfil(self.a)["xp_total"], 0)          # o nível da conta sobe mesmo assim

    def test_desafio_da_temporada_conta_entre_partidas(self):
        for i in range(5):
            self.relatorio(f"v{i}", **{str(self.a): {"colocacao": 1, "venceu": True, "tempo_s": 300}})
        d = {q["id"]: q for q in self.p.passe(self.a)["desafios"]}
        self.assertTrue(d["t1_vitorias_5"]["concluida"])
        self.assertEqual(d["t1_partidas_50"]["progresso"], 5)
        self.assertTrue(any(e["reason"] == "Missão: Vença 5 partidas" for e in self.p.ledger(self.a, 200)))


class TestValidacao(unittest.TestCase):
    def setUp(self):
        self.cfg = carregar_config()
        self.t = copy.deepcopy(self.cfg["temporadas"][0])

    def erros(self, t, outras=()):
        return validar_temporada(t, self.cfg, outras, {"trajes": {"traje_tormenta": 1, "traje_aurora": 1, "traje_ourodesol": 1, "traje_meianoite": 1}})

    def test_publicada_e_valida_e_dentro_da_meta_de_horas(self):
        self.assertEqual(self.erros(self.t), [])
        self.assertTrue(25 <= estimar_horas(self.t, self.cfg)["horas"] <= 30)

    def test_erros_detectados(self):
        t = copy.deepcopy(self.t); t["recompensas"][3]["nivel"] = 99
        self.assertTrue(any("1..N" in e for e in self.erros(t)))
        t = copy.deepcopy(self.t); t["recompensas"][7] = {"nivel": 8, "item": "nao_existe"}
        self.assertTrue(any("catálogo" in e for e in self.erros(t)))
        t = copy.deepcopy(self.t); t["recompensas"][9] = {"nivel": 10, "item": "traje_tormenta"}
        self.assertTrue(any("repetido" in e for e in self.erros(t)))
        t = copy.deepcopy(self.t); t["recompensas"][9] = {"nivel": 10, "item": "traje_brisa"}
        self.assertTrue(any("todo mundo" in e for e in self.erros(t)))
        t = copy.deepcopy(self.t); t["recompensas"][2] = {"nivel": 3, "faiscas": 10, "item": "traje_aurora"}
        self.assertTrue(any("exatamente uma" in e for e in self.erros(t)))
        t = copy.deepcopy(self.t); t["fim"] = t["inicio"]
        self.assertTrue(any("depois" in e for e in self.erros(t)))
        outra = copy.deepcopy(self.t); outra["id"] = "t2"
        self.assertTrue(any("sobrepõem" in e for e in self.erros(self.t, [self.t, outra])))
        t = copy.deepcopy(self.t)
        self.assertTrue(any("visual" in e for e in validar_temporada(t, self.cfg, (), {"trajes": {}})))

    def test_ferramenta_de_linha_de_comando(self):
        r = subprocess.run([sys.executable, os.path.join(RAIZ, "tools", "validar_temporada.py")], capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("estimativa", r.stdout)


if __name__ == "__main__":
    unittest.main()
