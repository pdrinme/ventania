"""Uso: cd backend && python3 -m meta_server [--config config/server.json] [--port 8080]"""
import argparse
import asyncio
import logging
import signal

from . import SERVER_VERSION, config, db
from .app import App
from .http import serve


async def principal(cfg: config.Config) -> None:
    con = db.connect(cfg.db_abs())
    versao = db.migrate(con)
    app = App(con)
    servidor = await serve(app.router, cfg.host, cfg.port, cfg.max_body_bytes, cfg.request_timeout_s)
    enderecos = ", ".join(f"{s.getsockname()[0]}:{s.getsockname()[1]}" for s in servidor.sockets)
    logging.info("Ventania meta-servidor %s ouvindo em %s (banco v%d: %s)", SERVER_VERSION, enderecos, versao, cfg.db_abs())
    parar = asyncio.Event()
    loop = asyncio.get_running_loop()
    for s in (signal.SIGINT, signal.SIGTERM):
        try:
            loop.add_signal_handler(s, parar.set)
        except NotImplementedError:  # Windows
            pass
    async with servidor:
        try:
            await parar.wait()
        except asyncio.CancelledError:
            pass
    con.close()
    logging.info("meta-servidor encerrado")


def main() -> None:
    p = argparse.ArgumentParser(description="Meta-servidor do Ventania")
    p.add_argument("--config")
    p.add_argument("--port", type=int)
    p.add_argument("--host")
    a = p.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
    cfg = config.load(a.config)
    if a.port is not None or a.host:
        cfg = config.Config(**{**cfg.__dict__, **({"port": a.port} if a.port is not None else {}),
                               **({"host": a.host} if a.host else {})})
    try:
        asyncio.run(principal(cfg))
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
