from dataclasses import dataclass
from hashlib import sha256
from typing import Annotated
from uuid import UUID

from fastapi import Depends, Request, Security
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from psycopg import Connection

from .errors import DomainError

ADMIN_ROLES = frozenset({"administrator", "operator", "compliance_reviewer", "technical_reviewer", "quality_reviewer"})
bearer = HTTPBearer(auto_error=False)


@dataclass(frozen=True)
class Actor:
    id: UUID
    audience: str
    roles: frozenset[str]
    session_id: UUID | None = None


def get_tx(request: Request):
    path = request.url.path
    if path.startswith(("/api/v1/mobile/", "/api/v1/admin/")) and not path.endswith(("/auth/login", "/auth/register")):
        authorization = request.headers.get("authorization", "")
        if not authorization.lower().startswith("bearer ") or not authorization[7:].strip():
            raise DomainError(401, "AUTH_REQUIRED", "请先登录 / ログインしてください")
    request.state.uploaded_keys = []
    try:
        with request.app.state.database.transaction(request.state.correlation_id) as conn:
            yield conn
    except Exception:
        # Compensate local byte writes if the database transaction (including commit) fails.
        from .files import storage_path
        for key in request.state.uploaded_keys:
            storage_path(request.app.state.settings.storage_root, key).unlink(missing_ok=True)
        raise


TxDep = Annotated[Connection, Depends(get_tx, scope="function")]


def get_actor(request: Request, conn: TxDep,
              credentials: Annotated[HTTPAuthorizationCredentials | None, Security(bearer)]) -> Actor:
    if not credentials or credentials.scheme.lower() != "bearer" or len(credentials.credentials) > 256:
        raise DomainError(401, "AUTH_REQUIRED", "请先登录 / ログインしてください")
    audience = "admin" if request.url.path.startswith("/api/v1/admin/") else "mobile"
    token_hash = sha256(credentials.credentials.encode()).hexdigest()
    row = conn.execute("""SELECT a.id, a.status, s.id AS session_id FROM opc.auth_sessions s
        JOIN opc.accounts a ON a.id=s.account_id WHERE s.token_hash=%s AND s.audience=%s
        AND s.revoked_at IS NULL AND s.expires_at>now() FOR SHARE OF a,s""", (token_hash, audience)).fetchone()
    if not row or row["status"] != "active":
        raise DomainError(401, "SESSION_INVALID", "会话无效、已过期或账号已停用")
    roles = frozenset(r["role_code"] for r in conn.execute(
        "SELECT role_code FROM opc.account_roles WHERE account_id=%s AND revoked_at IS NULL FOR SHARE", (row["id"],)))
    if audience == "admin" and not (roles & ADMIN_ROLES):
        raise DomainError(403, "ADMIN_FORBIDDEN", "当前账号没有管理权限")
    conn.execute("SELECT set_config('opc.actor_id', %s, true)", (str(row["id"]),))
    return Actor(row["id"], audience, roles, row["session_id"])


ActorDep = Annotated[Actor, Depends(get_actor)]


def ensure_admin(actor: Actor, *roles: str):
    allowed = frozenset(roles) if roles else ADMIN_ROLES
    if actor.audience != "admin" or not (actor.roles & (allowed | {"administrator"})):
        raise DomainError(403, "ROLE_FORBIDDEN", "当前管理角色无权执行此操作")


def ensure_mobile(actor: Actor):
    if actor.audience != "mobile":
        raise DomainError(403, "AUDIENCE_FORBIDDEN", "此操作需要手机端会话")


def ensure_provider(conn: Connection, actor: Actor):
    ensure_mobile(actor)
    grant = conn.execute("""SELECT id FROM opc.provider_authorizations
        WHERE account_id=%s AND revoked_at IS NULL FOR SHARE""", (actor.id,)).fetchone()
    if "provider" not in actor.roles or not grant:
        raise DomainError(403, "PROVIDER_FORBIDDEN", "需要有效内部接单授权；此授权不代表 OPC 认证")
