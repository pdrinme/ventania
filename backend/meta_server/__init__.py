"""Meta-servidor do Ventania: contas, progressão, loja, passe, grupos (ARCHITECTURE §5).

Etapa 1: esqueleto — servidor HTTP/JSON (asyncio, stdlib), configuração,
banco SQLite com migrações, /v1/health e /v1/compat.
"""
SERVER_VERSION = "0.1.0"
PROTOCOL_VERSION = 1   # deve bater com game/core/version.gd PROTOCOL
CONTENT_VERSION = 1
