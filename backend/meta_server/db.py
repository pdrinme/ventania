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
    (2, "contas, sessões e amizades (Etapa 8)", """
        CREATE TABLE accounts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            username TEXT NOT NULL,
            username_norm TEXT NOT NULL UNIQUE,
            pass_salt BLOB NOT NULL,
            pass_hash BLOB NOT NULL,
            pass_iter INTEGER NOT NULL,
            created_at INTEGER NOT NULL
        );
        CREATE TABLE sessions (
            token_hash BLOB PRIMARY KEY,
            account_id INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
            created_at INTEGER NOT NULL,
            expires_at INTEGER NOT NULL
        );
        CREATE INDEX sessions_account ON sessions(account_id);
        CREATE TABLE friendships (
            a INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
            b INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
            requester INTEGER NOT NULL,
            status TEXT NOT NULL CHECK (status IN ('pending', 'accepted')),
            created_at INTEGER NOT NULL,
            PRIMARY KEY (a, b),
            CHECK (a < b)
        );
        CREATE INDEX friendships_b ON friendships(b);
    """),
    (3, "progressão: perfil, ledger de Faíscas, desbloqueios, equipados, missões e partidas (Etapa 9)", """
        CREATE TABLE profiles (
            account_id INTEGER PRIMARY KEY REFERENCES accounts(id) ON DELETE CASCADE,
            xp_total INTEGER NOT NULL DEFAULT 0,
            level INTEGER NOT NULL DEFAULT 1,
            sparks INTEGER NOT NULL DEFAULT 0 CHECK (sparks >= 0),
            matches INTEGER NOT NULL DEFAULT 0,
            wins INTEGER NOT NULL DEFAULT 0,
            kills INTEGER NOT NULL DEFAULT 0
        );
        CREATE TABLE ledger (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            account_id INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
            delta INTEGER NOT NULL,
            balance_after INTEGER NOT NULL,
            reason TEXT NOT NULL,
            idem_key TEXT NOT NULL UNIQUE,
            created_at INTEGER NOT NULL
        );
        CREATE INDEX ledger_account ON ledger(account_id, id);
        CREATE TABLE unlocks (
            account_id INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
            item_id TEXT NOT NULL,
            source TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            PRIMARY KEY (account_id, item_id)
        );
        CREATE TABLE loadout (
            account_id INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
            slot TEXT NOT NULL,
            item_id TEXT NOT NULL,
            PRIMARY KEY (account_id, slot)
        );
        CREATE TABLE quest_progress (
            account_id INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
            quest_id TEXT NOT NULL,
            period TEXT NOT NULL,
            progress INTEGER NOT NULL DEFAULT 0,
            completed_at INTEGER,
            PRIMARY KEY (account_id, quest_id, period)
        );
        CREATE TABLE match_reports (
            match_id TEXT PRIMARY KEY,
            room TEXT NOT NULL,
            mode TEXT NOT NULL,
            total INTEGER NOT NULL,
            received_at INTEGER NOT NULL
        );
        CREATE TABLE match_results (
            match_id TEXT NOT NULL REFERENCES match_reports(match_id),
            account_id INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
            placement INTEGER NOT NULL,
            kills INTEGER NOT NULL,
            time_alive_s INTEGER NOT NULL,
            xp INTEGER NOT NULL,
            sparks INTEGER NOT NULL,
            details TEXT NOT NULL,
            PRIMARY KEY (match_id, account_id)
        );
        CREATE INDEX match_results_account ON match_results(account_id);
    """),
    (4, "passe de batalha: progresso por temporada (Etapa 10)", """
        CREATE TABLE season_progress (
            account_id INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
            season_id TEXT NOT NULL,
            xp INTEGER NOT NULL DEFAULT 0,
            level INTEGER NOT NULL DEFAULT 1,
            PRIMARY KEY (account_id, season_id)
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
