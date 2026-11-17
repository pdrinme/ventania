"""Configuração do meta-servidor (arquivo JSON + variáveis de ambiente)."""
import json
import os
from dataclasses import dataclass

AQUI = os.path.dirname(os.path.abspath(__file__))
BACKEND = os.path.dirname(AQUI)


@dataclass(frozen=True)
class Config:
    host: str = "0.0.0.0"
    port: int = 8080
    db_path: str = "data/meta.sqlite3"
    max_body_bytes: int = 64 * 1024
    request_timeout_s: float = 10.0
    pbkdf2_iter: int = 200_000          # senhas (ARCHITECTURE §6); os testes usam menos
    session_days: int = 30
    server_secret: str = ""             # segredo compartilhado com os servidores de partida (tickets HMAC)
    ticket_ttl_s: int = 120
    longpoll_s: float = 25.0

    def db_abs(self) -> str:
        return self.db_path if os.path.isabs(self.db_path) or self.db_path == ":memory:" \
            else os.path.join(BACKEND, self.db_path)


def load(path: str | None = None) -> Config:
    """Lê o JSON (se existir) e aplica VENTANIA_HOST / VENTANIA_PORT / VENTANIA_DB."""
    dados = {}
    path = path or os.path.join(BACKEND, "config", "server.json")
    if os.path.exists(path):
        with open(path, encoding="utf-8") as f:
            dados = json.load(f)
    validos = {k: v for k, v in dados.items() if k in Config.__dataclass_fields__}
    env = {"host": os.environ.get("VENTANIA_HOST"), "port": os.environ.get("VENTANIA_PORT"),
           "db_path": os.environ.get("VENTANIA_DB"), "server_secret": os.environ.get("VENTANIA_SEGREDO")}
    for k, v in env.items():
        if v:
            validos[k] = int(v) if k == "port" else v
    cfg = Config(**validos)
    if not (0 <= cfg.port <= 65535):
        raise ValueError(f"porta inválida: {cfg.port}")
    return cfg
