"""Etapa 11: loja rotativa (rotação, agenda, compra atômica e idempotente, ferramenta)."""
import copy
import datetime
import os
import subprocess
import sys
import threading
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from meta_server.http import HttpError  # noqa: E402
from meta_server.loja import Loja, carregar_loja, validar_loja  # noqa: E402
from test_meta_server import ServidorDeTeste  # noqa: E402
from test_progressao import Base  # noqa: E402
from test_social import Api, CFG  # noqa: E402

RAIZ = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


class TestLoja(Base):
    def setUp(self):
        super().setUp()
        self.loja = Loja(self.p)

    def dar(self, conta, n):
        self.p.garantir(conta)
        with self.p._tx():
            self.p._creditar(conta, n, "teste", f"teste:{conta}:{n}:{len(self.p.ledger(conta))}")

    def test_rotacao_deterministica_e_sem_repetir_destaques(self):
        hoje = self.loja._hoje()
        v1, v2 = self.loja.vitrine(), Loja(self.p).vitrine()
        self.assertEqual(v1, v2)
        dest, _ = v1["destaques"]
        dia, resta = v1["diaria"]
        self.assertEqual(len(dest), 2)
        self.assertEqual(len(dia), 4)
        self.assertFalse(set(dest) & set(dia))
        self.assertTrue(0 < resta <= 86400)
        # a Diária de amanhã traz itens que não estavam hoje
        amanha = self.loja.diaria(hoje + datetime.timedelta(days=1))
        self.assertTrue(set(amanha) - set(dia))
        # itens do passe e iniciais nunca entram
        for i in dest + dia:
            self.assertTrue(self.p.cfg["catalogo"][i].get("loja"))

    def test_agenda_manda(self):
        cfg = copy.deepcopy(self.loja.cfg)
        segunda = self.loja._hoje() - datetime.timedelta(days=self.loja._hoje().weekday())
        cfg["agenda"] = [{"data": segunda.isoformat(), "secao": "destaques", "itens": ["traje_capitao_mare", "picareta_ancora"]}]
        loja = Loja(self.p, cfg)
        self.assertEqual(loja.vitrine()["destaques"][0], ["traje_capitao_mare", "picareta_ancora"])
        cfg["agenda"][0]["itens"] = ["traje_guardiao"]            # item do passe não pode
        self.assertTrue(validar_loja(cfg, self.p.cfg["catalogo"], self.p.cfg["temporadas"]))

    def test_compra_atomica_e_idempotente(self):
        item = self.loja.vitrine()["diaria"][0][0]
        preco = self.loja.preco(item)
        with self.assertRaises(HttpError) as e:
            self.loja.comprar(self.a, item, preco, "chave-0001")
        self.assertEqual(e.exception.status, 409)                     # sem saldo
        self.assertNotIn(item, {u["item"] for u in self.p.perfil(self.a)["unlocks"]})
        self.dar(self.a, 5000)
        saldo = self.p.perfil(self.a)["sparks"]
        r = self.loja.comprar(self.a, item, preco, "chave-0002")
        self.assertEqual(r["status"], "comprado")
        self.assertEqual(r["perfil"]["sparks"], saldo - preco)
        self.assertEqual({u["item"]: u["source"] for u in r["perfil"]["unlocks"]}[item], "loja")
        # o mesmo pedido de novo (rede caiu e o cliente repetiu): não cobra
        self.assertEqual(self.loja.comprar(self.a, item, preco, "chave-0002")["status"], "ja_comprado")
        self.assertEqual(self.p.perfil(self.a)["sparks"], saldo - preco)
        # outro pedido do mesmo item: já tem
        with self.assertRaises(HttpError):
            self.loja.comprar(self.a, item, preco, "chave-0003")
        self.assertEqual(self.p.ledger(self.a)[0]["reason"], f"Loja: {self.p.cfg['catalogo'][item]['nome']}")

    def test_so_o_que_esta_na_loja_e_pelo_preco_certo(self):
        self.dar(self.a, 5000)
        a_venda = {i for itens, _ in self.loja.vitrine().values() for i in itens}
        fora = [i for i, it in self.p.cfg["catalogo"].items() if it.get("loja") and i not in a_venda][0]
        with self.assertRaises(HttpError):
            self.loja.comprar(self.a, fora, None, "chave-fora")
        with self.assertRaises(HttpError):
            self.loja.comprar(self.a, "traje_guardiao", None, "chave-passe")      # do passe
        item = sorted(a_venda)[0]
        with self.assertRaises(HttpError) as e:
            self.loja.comprar(self.a, item, 1, "chave-preco")                    # preço diferente
        self.assertIn("preço", e.exception.message)
        with self.assertRaises(HttpError):
            self.loja.comprar(self.a, item, None, "curta")                       # sem chave decente

    def test_compras_simultaneas_nao_passam_do_saldo(self):
        itens = [i for itens, _ in self.loja.vitrine().values() for i in itens]
        caro = sorted(itens, key=self.loja.preco)[-2:]
        self.dar(self.a, self.loja.preco(caro[0]))                                # dá para só um deles
        resultados = []

        def tentar(item, k):
            try:
                self.loja.comprar(self.a, item, None, f"paralela-{k}")
                resultados.append("ok")
            except HttpError:
                resultados.append("recusada")
            except Exception as e:                                               # sqlite ocupado etc.
                resultados.append(type(e).__name__)
        ts = [threading.Thread(target=tentar, args=(caro[k % 2], k)) for k in range(2)]
        for t in ts:
            t.start()
        for t in ts:
            t.join()
        self.assertGreaterEqual(self.p.perfil(self.a)["sparks"], 0)
        self.assertLessEqual(resultados.count("ok"), 1)

    def test_configuracao_publicada_valida(self):
        self.assertEqual(validar_loja(carregar_loja(), self.p.cfg["catalogo"], self.p.cfg["temporadas"]), [])


class TestApiLoja(unittest.TestCase):
    def test_loja_pela_api(self):
        with ServidorDeTeste(CFG) as s:
            a = Api(s)
            tok, conta = a.conta("Ana")
            st, d = a.chamar("/v1/shop", token=tok)
            self.assertEqual(st, 200)
            self.assertEqual([x["id"] for x in d["secoes"]], ["destaques", "diaria"])
            item = d["secoes"][1]["itens"][0]
            st, r = a.chamar("/v1/shop/buy", {"item": item["id"], "preco": item["preco"], "chave": "api-compra-1"}, tok)
            self.assertEqual(st, 409)                                            # saldo inicial: só 0 (ou 50 do passe)
            self.assertEqual(a.chamar("/v1/shop/buy", {"item": item["id"]})[0], 401)


class TestFerramenta(unittest.TestCase):
    def test_admin_validar_e_prever(self):
        for args in (["validar"], ["prever", "--dias", "3"], ["listar"]):
            r = subprocess.run([sys.executable, os.path.join(RAIZ, "tools", "admin_loja.py"), *args], capture_output=True, text=True)
            self.assertEqual(r.returncode, 0, r.stdout + r.stderr)


if __name__ == "__main__":
    unittest.main()
