"""Testes do meta-servidor. Uso: cd backend && python3 -m unittest discover -s tests -v"""
import asyncio
import json
import os
import socket
import sys
import tempfile
import threading
import unittest
import urllib.error
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from meta_server import PROTOCOL_VERSION, SERVER_VERSION, config, db  # noqa: E402
from meta_server.app import App  # noqa: E402
from meta_server.http import serve  # noqa: E402


class ServidorDeTeste:
    """Sobe o servidor numa thread com porta livre e banco em memória."""

    def __init__(self, cfg=None):
        self.cfg = cfg

    def __enter__(self):
        self.con = db.connect(":memory:")
        db.migrate(self.con)
        self.loop = asyncio.new_event_loop()
        pronto = threading.Event()

        def rodar():
            asyncio.set_event_loop(self.loop)
            self.srv = self.loop.run_until_complete(serve(App(self.con, self.cfg).router, "127.0.0.1", 0, 1024, 2.0))
            self.porta = self.srv.sockets[0].getsockname()[1]
            pronto.set()
            self.loop.run_forever()

        self.thread = threading.Thread(target=rodar, daemon=True)
        self.thread.start()
        pronto.wait(5)
        return self

    def __exit__(self, *_):
        self.loop.call_soon_threadsafe(self.srv.close)
        self.loop.call_soon_threadsafe(self.loop.stop)
        self.thread.join(5)
        self.loop.close()
        self.con.close()

    def get(self, caminho, metodo="GET", corpo=None, cabecalhos=None):
        req = urllib.request.Request(f"http://127.0.0.1:{self.porta}{caminho}", method=metodo, data=corpo,
                                     headers=cabecalhos or {})
        try:
            with urllib.request.urlopen(req, timeout=5) as r:
                return r.status, json.loads(r.read() or b"null")
        except urllib.error.HTTPError as e:
            return e.code, json.loads(e.read() or b"null")

    def bruto(self, dados: bytes) -> bytes:
        with socket.create_connection(("127.0.0.1", self.porta), timeout=5) as s:
            s.sendall(dados)
            return s.recv(4096)


class TestApi(unittest.TestCase):
    def test_health(self):
        with ServidorDeTeste() as s:
            status, d = s.get("/v1/health")
            self.assertEqual(status, 200)
            self.assertEqual(d["status"], "ok")
            self.assertEqual(d["protocol_version"], PROTOCOL_VERSION)
            self.assertEqual(d["server_version"], SERVER_VERSION)
            self.assertEqual(d["db_schema"], db.MIGRACOES[-1][0])

    def test_compat(self):
        with ServidorDeTeste() as s:
            self.assertTrue(s.get(f"/v1/compat?protocol={PROTOCOL_VERSION}")[1]["compatible"])
            st, d = s.get("/v1/compat?protocol=0")
            self.assertFalse(d["compatible"])
            self.assertIn("atualize o jogo", d["message"])
            self.assertEqual(s.get("/v1/compat")[0], 400)

    def test_rota_inexistente_e_metodo(self):
        with ServidorDeTeste() as s:
            self.assertEqual(s.get("/v1/nada")[0], 404)
            self.assertEqual(s.get("/v1/health", "POST", b"{}")[0], 405)

    def test_requisicao_malformada(self):
        with ServidorDeTeste() as s:
            self.assertIn(b"400", s.bruto(b"LIXO\r\n\r\n").split(b"\r\n")[0])

    def test_corpo_grande_demais(self):
        with ServidorDeTeste() as s:
            r = s.bruto(b"POST /v1/health HTTP/1.1\r\nContent-Length: 999999\r\n\r\n")
            self.assertIn(b"413", r.split(b"\r\n")[0])


class TestBanco(unittest.TestCase):
    def test_migracao_idempotente(self):
        with tempfile.TemporaryDirectory() as d:
            caminho = os.path.join(d, "x", "meta.sqlite3")
            con = db.connect(caminho)
            v1 = db.migrate(con)
            v2 = db.migrate(con)
            self.assertEqual(v1, v2)
            n = con.execute("SELECT COUNT(*) FROM schema_migrations").fetchone()[0]
            self.assertEqual(n, len(db.MIGRACOES))
            con.close()


class TestConfig(unittest.TestCase):
    def test_env_sobrescreve(self):
        os.environ["VENTANIA_PORT"] = "9123"
        try:
            self.assertEqual(config.load("/nao/existe.json").port, 9123)
        finally:
            del os.environ["VENTANIA_PORT"]

    def test_porta_invalida(self):
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
            json.dump({"port": 70000}, f)
        try:
            with self.assertRaises(ValueError):
                config.load(f.name)
        finally:
            os.unlink(f.name)


if __name__ == "__main__":
    unittest.main()
