"""Banco SQLite com migrações versionadas. Toda alteração de esquema entra em MIGRACOES."""
import os
import sqlite3
import time

# (versão, descrição, SQL). Nunca edite uma migração já publicada: adicione outra.
MIGRACOES = [
    (1, "metadados do servidor", """
        CREATE TABLE server_meta (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );
    """),
]


def connect(path: str) -> sqlite3.Connection:
    if path != ":memory:":
        os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    con = sqlite3.connect(path, isolation_level=None, check_same_thread=False)
    con.row_factory = sqlite3.Row
    con.execute("PRAGMA foreign_keys = ON")
    if path != ":memory:":
        con.execute("PRAGMA journal_mode = WAL")
    con.execute("PRAGMA busy_timeout = 5000")
    return con


def migrate(con: sqlite3.Connection) -> int:
    """Aplica as migrações pendentes em transação. Retorna a versão final."""
    con.execute("CREATE TABLE IF NOT EXISTS schema_migrations (version INTEGER PRIMARY KEY, "
                "description TEXT NOT NULL, applied_at INTEGER NOT NULL)")
    atual = con.execute("SELECT COALESCE(MAX(version), 0) FROM schema_migrations").fetchone()[0]
    for versao, desc, sql in MIGRACOES:
        if versao <= atual:
            continue
        con.execute("BEGIN IMMEDIATE")
        try:
            for comando in [c for c in sql.split(";") if c.strip()]:
                con.execute(comando)
            con.execute("INSERT INTO schema_migrations VALUES (?, ?, ?)", (versao, desc, int(time.time())))
            con.execute("COMMIT")
        except Exception:
            con.execute("ROLLBACK")
            raise
        atual = versao
    return atual
