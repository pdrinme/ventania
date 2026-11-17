"""Rotas da API v1."""
import asyncio
import secrets
import time

from . import CONTENT_VERSION, PROTOCOL_VERSION, SERVER_VERSION
from .config import Config
from .contas import Contas
from .http import HttpError, Request, Response, Router
from .partidas import Partidas
from .social import Eventos, Social


def segredo_dos_servidores(con, cfg: Config) -> str:
    """O da configuração/ambiente; senão, um gerado na primeira vez e guardado no banco."""
    if cfg.server_secret:
        return cfg.server_secret
    row = con.execute("SELECT value FROM server_meta WHERE key = 'server_secret'").fetchone()
    if row:
        return row["value"]
    s = secrets.token_urlsafe(24)
    con.execute("INSERT INTO server_meta VALUES ('server_secret', ?)", (s,))
    return s


class App:
    def __init__(self, con, cfg: Config | None = None):
        self.con = con
        self.cfg = cfg or Config()
        self.inicio = time.time()
        self.contas = Contas(con, self.cfg)
        self.eventos = Eventos()
        self.social = Social(con, self.contas, self.eventos)
        self.segredo = segredo_dos_servidores(con, self.cfg)
        self.partidas = Partidas(self.social, self.contas, self.segredo, self.cfg.ticket_ttl_s)
        r = self.router = Router()
        r.add("GET", "/v1/health", self.health)
        r.add("GET", "/v1/compat", self.compat)
        # contas
        r.add("POST", "/v1/auth/register", self.registrar)
        r.add("POST", "/v1/auth/login", self.entrar)
        r.add("POST", "/v1/auth/logout", self.sair)
        r.add("GET", "/v1/me", self.eu)
        r.add("GET", "/v1/events", self.eventos_get)
        # amigos
        r.add("GET", "/v1/friends", self._a(lambda c, d: self.social.lista_amigos(c)))
        r.add("POST", "/v1/friends/request", self._a(lambda c, d: self.social.pedir_amizade(c, d.get("username", ""))))
        r.add("POST", "/v1/friends/respond", self._a(lambda c, d: self.social.responder_amizade(c, self._id(d, "id"), bool(d.get("accept")))))
        r.add("POST", "/v1/friends/remove", self._a(lambda c, d: self.social.remover_amigo(c, self._id(d, "id"))))
        # grupo
        r.add("GET", "/v1/party", self._a(lambda c, d: self.social.grupo_dict(self.social.grupo(c))))
        r.add("POST", "/v1/party/invite", self._a(lambda c, d: self.social.convidar(c, self._id(d, "id"))))
        r.add("POST", "/v1/party/respond", self._a(lambda c, d: self.social.responder_convite(c, str(d.get("invite", "")), bool(d.get("accept")))))
        r.add("POST", "/v1/party/leave", self._a(lambda c, d: self.social.sair_do_grupo(c)))
        r.add("POST", "/v1/party/kick", self._a(lambda c, d: self.social.expulsar(c, self._id(d, "id"))))
        r.add("POST", "/v1/party/promote", self._a(lambda c, d: self.social.promover(c, self._id(d, "id"))))
        r.add("POST", "/v1/party/mode", self._a(lambda c, d: self.social.escolher_modo(c, str(d.get("mode", "")))))
        # partidas
        r.add("POST", "/v1/match/queue", self._a(lambda c, d: self.partidas.entrar_na_fila(c)))
        r.add("POST", "/v1/match/cancel", self._a(lambda c, d: self.partidas.cancelar_fila(c)))
        r.add("POST", "/v1/match/left", self._a(lambda c, d: self.partidas.voltou_ao_lobby(c)))
        r.add("POST", "/v1/rooms/private", self._a(lambda c, d: self.partidas.criar_privada(c)))
        r.add("POST", "/v1/rooms/join", self._a(lambda c, d: self.partidas.entrar_privada(c, str(d.get("code", "")))))
        r.add("POST", "/v1/rooms/start", self._a(lambda c, d: self.partidas.iniciar_privada(c)))
        r.add("GET", "/v1/rooms", self._a(lambda c, d: {"rooms": self.partidas.lista_salas()}))
        r.add("POST", "/v1/servers/heartbeat", self.heartbeat)

    # ---------- utilidades ----------
    def _a(self, f):
        """Rota autenticada: f(conta, corpo_json) -> dict."""
        def handler(req: Request) -> Response:
            conta = self.contas.autenticar(req)
            self.social.tocar(conta)
            d = req.json() if req.body else {}
            if not isinstance(d, dict):
                raise HttpError(400, "corpo deve ser um objeto JSON")
            return Response(200, f(conta, d))
        return handler

    @staticmethod
    def _id(d: dict, chave: str) -> int:
        try:
            return int(d.get(chave))
        except (TypeError, ValueError):
            raise HttpError(400, f"'{chave}' obrigatório (inteiro)")

    @staticmethod
    def _corpo(req: Request) -> dict:
        d = req.json() if req.body else {}
        if not isinstance(d, dict):
            raise HttpError(400, "corpo deve ser um objeto JSON")
        return d

    async def tick(self) -> None:
        while True:
            await asyncio.sleep(1.0)
            self.social.expirar()
            self.partidas.combinar()

    # ---------- rotas ----------
    def health(self, _req: Request) -> Response:
        versao_db = self.con.execute("SELECT MAX(version) FROM schema_migrations").fetchone()[0]
        return Response(200, {
            "status": "ok", "server_version": SERVER_VERSION, "protocol_version": PROTOCOL_VERSION,
            "content_version": CONTENT_VERSION, "db_schema": versao_db,
            "time": int(time.time()), "uptime_s": int(time.time() - self.inicio),
            "rooms": len(self.partidas.lista_salas()),
        })

    def compat(self, req: Request) -> Response:
        try:
            proto = int(req.query.get("protocol", ""))
        except ValueError:
            raise HttpError(400, "parâmetro 'protocol' obrigatório (inteiro)")
        return Response(200, {"compatible": proto == PROTOCOL_VERSION, "server_protocol": PROTOCOL_VERSION,
                              "message": "" if proto == PROTOCOL_VERSION else
                              f"o servidor usa protocolo {PROTOCOL_VERSION}; atualize o {'jogo' if proto < PROTOCOL_VERSION else 'servidor'}"})

    def registrar(self, req: Request) -> Response:
        d = self._corpo(req)
        r = self.contas.registrar(d.get("username", ""), d.get("password", ""))
        self.social.tocar(r["account"]["id"])
        return Response(201, r)

    def entrar(self, req: Request) -> Response:
        d = self._corpo(req)
        r = self.contas.entrar(d.get("username", ""), d.get("password", ""), req.peer)
        self.social.tocar(r["account"]["id"])
        return Response(200, r)

    def sair(self, req: Request) -> Response:
        conta = self.contas.autenticar(req)
        self.social.sair_do_grupo(conta)
        self.social.visto.pop(conta, None)
        self.contas.sair(req.headers["authorization"][7:].strip())
        return Response(200, {"status": "ok"})

    def eu(self, req: Request) -> Response:
        conta = self.contas.autenticar(req)
        self.social.tocar(conta)
        return Response(200, {"account": self.contas.publica(conta),
                              "party": self.social.grupo_dict(self.social.grupo(conta)),
                              "events_seq": self.eventos.ultimo(conta)})

    async def eventos_get(self, req: Request) -> Response:
        conta = self.contas.autenticar(req)
        self.social.tocar(conta)
        try:
            since = int(req.query.get("since", "0"))
            espera = min(float(req.query.get("wait", self.cfg.longpoll_s)), self.cfg.longpoll_s)
        except ValueError:
            raise HttpError(400, "since/wait inválidos")
        evs = await self.eventos.esperar(conta, since, espera)
        self.social.tocar(conta)
        return Response(200, {"events": evs, "seq": self.eventos.ultimo(conta)})

    def heartbeat(self, req: Request) -> Response:
        return Response(200, self.partidas.heartbeat(req.headers.get("x-ventania-server", ""), req.peer, self._corpo(req)))
