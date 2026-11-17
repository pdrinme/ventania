"""Servidor HTTP/1.1 mínimo sobre asyncio (só JSON, Connection: close).

Suficiente para um grupo pequeno de amigos; atrás de um proxy reverso com TLS
se exposto na internet (ARCHITECTURE §6).
"""
import asyncio
import json
import logging
from dataclasses import dataclass, field
from urllib.parse import parse_qs, urlsplit

log = logging.getLogger("meta.http")
STATUS = {200: "OK", 201: "Created", 400: "Bad Request", 401: "Unauthorized", 403: "Forbidden", 404: "Not Found",
          405: "Method Not Allowed", 409: "Conflict", 429: "Too Many Requests",
          408: "Request Timeout", 413: "Payload Too Large", 500: "Internal Server Error"}


@dataclass
class Request:
    method: str
    path: str
    query: dict
    headers: dict
    body: bytes = b""
    peer: str = ""          # IP de quem pediu

    def json(self):
        if not self.body:
            return None
        return json.loads(self.body.decode("utf-8"))


@dataclass
class Response:
    status: int = 200
    data: object = None
    headers: dict = field(default_factory=dict)


class HttpError(Exception):
    def __init__(self, status: int, message: str):
        super().__init__(message)
        self.status = status
        self.message = message


def _serializar(resp: Response) -> bytes:
    corpo = json.dumps(resp.data, ensure_ascii=False).encode("utf-8") if resp.data is not None else b""
    cab = {"Content-Type": "application/json; charset=utf-8", "Content-Length": str(len(corpo)),
           "Connection": "close", **resp.headers}
    linhas = [f"HTTP/1.1 {resp.status} {STATUS.get(resp.status, 'OK')}"] + [f"{k}: {v}" for k, v in cab.items()]
    return ("\r\n".join(linhas) + "\r\n\r\n").encode("latin-1") + corpo


async def _ler(reader: asyncio.StreamReader, max_body: int) -> Request:
    try:
        cabecalho = await reader.readuntil(b"\r\n\r\n")
    except asyncio.LimitOverrunError:
        raise HttpError(400, "cabeçalho grande demais")
    except asyncio.IncompleteReadError:
        raise HttpError(400, "requisição incompleta")
    linhas = cabecalho.decode("latin-1").split("\r\n")
    partes = linhas[0].split(" ")
    if len(partes) != 3 or not partes[2].startswith("HTTP/1."):
        raise HttpError(400, "linha de requisição inválida")
    metodo, alvo, _ = partes
    headers = {}
    for l in linhas[1:]:
        if ":" in l:
            k, v = l.split(":", 1)
            headers[k.strip().lower()] = v.strip()
    try:
        tamanho = int(headers.get("content-length", "0"))
    except ValueError:
        raise HttpError(400, "Content-Length inválido")
    if tamanho < 0:
        raise HttpError(400, "Content-Length inválido")
    if tamanho > max_body:
        raise HttpError(413, f"corpo maior que {max_body} bytes")
    corpo = await reader.readexactly(tamanho) if tamanho else b""
    url = urlsplit(alvo)
    return Request(metodo.upper(), url.path, {k: v[-1] for k, v in parse_qs(url.query).items()}, headers, corpo)


class Router:
    def __init__(self):
        self._rotas = {}

    def add(self, metodo: str, caminho: str, handler):
        self._rotas.setdefault(caminho, {})[metodo] = handler

    async def dispatch(self, req: Request) -> Response:
        por_metodo = self._rotas.get(req.path)
        if por_metodo is None:
            raise HttpError(404, f"rota não encontrada: {req.path}")
        handler = por_metodo.get(req.method)
        if handler is None:
            raise HttpError(405, f"método {req.method} não permitido em {req.path}")
        r = handler(req)
        return await r if asyncio.iscoroutine(r) else r


async def serve(router: Router, host: str, port: int, max_body: int, timeout_s: float) -> asyncio.base_events.Server:
    async def cliente(reader, writer):
        req = None
        try:
            req = await asyncio.wait_for(_ler(reader, max_body), timeout_s)
            info = writer.get_extra_info("peername")
            req.peer = info[0] if info else ""
            resp = await router.dispatch(req)
        except HttpError as e:
            resp = Response(e.status, {"error": e.message})
        except asyncio.TimeoutError:
            resp = Response(408, {"error": "tempo esgotado"})
        except json.JSONDecodeError:
            resp = Response(400, {"error": "JSON inválido"})
        except Exception:
            log.exception("erro interno")
            resp = Response(500, {"error": "erro interno do servidor"})
        try:
            writer.write(_serializar(resp))
            await writer.drain()
        except ConnectionError:
            pass
        finally:
            writer.close()
        if req:
            log.info("%s %s -> %d", req.method, req.path, resp.status)

    return await asyncio.start_server(cliente, host, port, limit=16 * 1024)
