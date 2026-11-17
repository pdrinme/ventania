"""Contas e sessões (ARCHITECTURE §6).

- Nome de usuário: 3 a 16 caracteres (letras, números, _), único sem diferenciar
  maiúsculas. Sem e-mail nem dados pessoais.
- Senha: PBKDF2-SHA256 com salt aleatório (iterações na configuração).
- Sessão: token aleatório entregue ao cliente; o banco guarda só o SHA-256 dele.
- Tentativas de login: no máximo 8 por minuto por nome e por IP.
"""
import hashlib
import hmac
import re
import secrets
import time
import unicodedata

from .http import HttpError, Request

NOME_RE = re.compile(r"^[A-Za-z0-9_À-ÖØ-öø-ÿ]{3,16}$")
SENHA_MIN = 6
SENHA_MAX = 128
TENTATIVAS_POR_MIN = 8


def normalizar(nome: str) -> str:
    return unicodedata.normalize("NFC", nome).casefold()


def _hash_senha(senha: str, salt: bytes, iteracoes: int) -> bytes:
    return hashlib.pbkdf2_hmac("sha256", senha.encode("utf-8"), salt, iteracoes)


def _hash_token(token: str) -> bytes:
    return hashlib.sha256(token.encode("utf-8")).digest()


class Contas:
    def __init__(self, con, cfg):
        self.con = con
        self.cfg = cfg
        self._tentativas: dict[str, list[float]] = {}

    # ---------- cadastro e login ----------
    def registrar(self, nome: str, senha: str) -> dict:
        nome = unicodedata.normalize("NFC", (nome or "").strip())
        if not NOME_RE.match(nome):
            raise HttpError(400, "Nome inválido: use de 3 a 16 letras, números ou _.")
        if not isinstance(senha, str) or not (SENHA_MIN <= len(senha) <= SENHA_MAX):
            raise HttpError(400, f"A senha precisa ter de {SENHA_MIN} a {SENHA_MAX} caracteres.")
        salt = secrets.token_bytes(16)
        it = self.cfg.pbkdf2_iter
        try:
            cur = self.con.execute(
                "INSERT INTO accounts (username, username_norm, pass_salt, pass_hash, pass_iter, created_at) "
                "VALUES (?, ?, ?, ?, ?, ?)", (nome, normalizar(nome), salt, _hash_senha(senha, salt, it), it, int(time.time())))
        except Exception as e:  # sqlite3.IntegrityError
            if "UNIQUE" in str(e):
                raise HttpError(409, "Esse nome já está em uso.")
            raise
        return self._nova_sessao(cur.lastrowid)

    def entrar(self, nome: str, senha: str, ip: str) -> dict:
        nome = (nome or "").strip()
        for chave in ("n:" + normalizar(nome), "ip:" + ip):
            self._limitar(chave)
        row = self.con.execute("SELECT * FROM accounts WHERE username_norm = ?", (normalizar(nome),)).fetchone()
        if row is None or not isinstance(senha, str) or len(senha) > SENHA_MAX or \
                not hmac.compare_digest(_hash_senha(senha, row["pass_salt"], row["pass_iter"]), row["pass_hash"]):
            raise HttpError(401, "Nome ou senha incorretos.")
        return self._nova_sessao(row["id"])

    def sair(self, token: str) -> None:
        self.con.execute("DELETE FROM sessions WHERE token_hash = ?", (_hash_token(token),))

    def _nova_sessao(self, conta_id: int) -> dict:
        token = secrets.token_urlsafe(32)
        agora = int(time.time())
        self.con.execute("INSERT INTO sessions VALUES (?, ?, ?, ?)",
                         (_hash_token(token), conta_id, agora, agora + self.cfg.session_days * 86400))
        self.con.execute("DELETE FROM sessions WHERE expires_at < ?", (agora,))
        return {"token": token, "account": self.publica(conta_id)}

    def _limitar(self, chave: str) -> None:
        agora = time.monotonic()
        lista = [t for t in self._tentativas.get(chave, []) if agora - t < 60.0]
        if len(lista) >= TENTATIVAS_POR_MIN:
            self._tentativas[chave] = lista
            raise HttpError(429, "Muitas tentativas. Espere um minuto.")
        lista.append(agora)
        self._tentativas[chave] = lista

    # ---------- consulta ----------
    def autenticar(self, req: Request) -> int:
        """Conta da sessão do cabeçalho Authorization: Bearer <token>; 401 se não houver."""
        cab = req.headers.get("authorization", "")
        if not cab.startswith("Bearer "):
            raise HttpError(401, "Entre na sua conta.")
        row = self.con.execute("SELECT account_id, expires_at FROM sessions WHERE token_hash = ?",
                               (_hash_token(cab[7:].strip()),)).fetchone()
        if row is None or row["expires_at"] < time.time():
            raise HttpError(401, "Sessão expirada. Entre de novo.")
        return row["account_id"]

    def publica(self, conta_id: int) -> dict:
        row = self.con.execute("SELECT id, username FROM accounts WHERE id = ?", (conta_id,)).fetchone()
        if row is None:
            raise HttpError(404, "Conta não encontrada.")
        return {"id": row["id"], "username": row["username"]}

    def por_nome(self, nome: str) -> int | None:
        row = self.con.execute("SELECT id FROM accounts WHERE username_norm = ?", (normalizar(nome or ""),)).fetchone()
        return row["id"] if row else None

    def nome(self, conta_id: int) -> str:
        return self.publica(conta_id)["username"]
