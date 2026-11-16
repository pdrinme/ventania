"""Rotas da API v1."""
import time

from . import CONTENT_VERSION, PROTOCOL_VERSION, SERVER_VERSION
from .http import HttpError, Request, Response, Router


class App:
    def __init__(self, con):
        self.con = con
        self.inicio = time.time()
        self.router = Router()
        self.router.add("GET", "/v1/health", self.health)
        self.router.add("GET", "/v1/compat", self.compat)

    def health(self, _req: Request) -> Response:
        versao_db = self.con.execute("SELECT MAX(version) FROM schema_migrations").fetchone()[0]
        return Response(200, {
            "status": "ok", "server_version": SERVER_VERSION, "protocol_version": PROTOCOL_VERSION,
            "content_version": CONTENT_VERSION, "db_schema": versao_db,
            "time": int(time.time()), "uptime_s": int(time.time() - self.inicio),
        })

    def compat(self, req: Request) -> Response:
        try:
            proto = int(req.query.get("protocol", ""))
        except ValueError:
            raise HttpError(400, "parâmetro 'protocol' obrigatório (inteiro)")
        return Response(200, {"compatible": proto == PROTOCOL_VERSION, "server_protocol": PROTOCOL_VERSION,
                              "message": "" if proto == PROTOCOL_VERSION else
                              f"o servidor usa protocolo {PROTOCOL_VERSION}; atualize o {'jogo' if proto < PROTOCOL_VERSION else 'servidor'}"})
