import secrets
import threading
import time
from collections import OrderedDict
from datetime import datetime, timedelta, timezone
from hashlib import sha256
from typing import Literal
from uuid import UUID

from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerificationError
from fastapi import APIRouter, Query, Request
from pydantic import EmailStr, Field, SecretStr, field_validator

from .common import check_version
from .deps import ADMIN_ROLES, ActorDep, TxDep, ensure_admin
from .errors import DomainError
from .models import Input, Text, VersionInput

router = APIRouter(tags=["身份与账号"])
hasher = PasswordHasher(time_cost=3, memory_cost=65536, parallelism=2)


def hash_password(password: str):
    return hasher.hash(password)


def verify_password(encoded: str, password: str):
    try:
        return hasher.verify(encoded, password)
    except (VerificationError, InvalidHashError):
        return False


DUMMY_HASH = hash_password(secrets.token_urlsafe(32))


class LoginInput(Input):
    email: EmailStr
    password: SecretStr = Field(min_length=1, max_length=128)


class RegisterInput(LoginInput):
    password: SecretStr = Field(min_length=12, max_length=128)
    display_name: str = Field(min_length=1, max_length=80)
    ui_locale: Literal["ja", "zh"] = "ja"

    @field_validator("display_name")
    @classmethod
    def name_not_blank(cls, value):
        if not value.strip():
            raise ValueError("显示名不能为空")
        return value.strip()


class ProfileInput(VersionInput):
    display_name: str = Field(min_length=1, max_length=80, pattern=r"\S")
    ui_locale: Literal["ja", "zh"]


class PasswordInput(Input):
    current_password: SecretStr = Field(min_length=1, max_length=128)
    new_password: SecretStr = Field(min_length=12, max_length=128)


class RoleInput(Input):
    role: Literal["customer", "provider", "compliance_reviewer", "technical_reviewer", "quality_reviewer", "operator", "administrator"]
    reason: Text


class GrantInput(Input):
    reason: Text


class StatusInput(VersionInput):
    status: Literal["active", "disabled"]
    reason: Text


class LoginLimiter:
    """Bounded per-process limiter; use a shared gateway limit for multi-worker deployments."""

    def __init__(self):
        self.entries = OrderedDict()
        self.lock = threading.Lock()

    def check(self, key, limit=10, window=60):
        now = time.monotonic()
        with self.lock:
            attempts = [t for t in self.entries.pop(key, []) if t > now-window]
            attempts.append(now)
            self.entries[key] = attempts[-limit-1:]
            while len(self.entries) > 10000:
                self.entries.popitem(last=False)
            if len(attempts) > limit:
                raise DomainError(429, "RATE_LIMITED", "尝试过于频繁，请稍后重试")


def public_account(conn, account_id):
    row = conn.execute("""SELECT id,email,display_name,status,ui_locale,row_version,created_at
        FROM opc.accounts WHERE id=%s""", (account_id,)).fetchone()
    row["roles"] = [r["role_code"] for r in conn.execute(
        "SELECT role_code FROM opc.account_roles WHERE account_id=%s AND revoked_at IS NULL ORDER BY role_code", (account_id,))]
    row["internally_authorized"] = bool(conn.execute(
        "SELECT id FROM opc.provider_authorizations WHERE account_id=%s AND revoked_at IS NULL", (account_id,)).fetchone())
    row["opc_certified"] = False
    return row


def create_customer(conn, body):
    row = conn.execute("""INSERT INTO opc.accounts(email,display_name,ui_locale) VALUES (%s,%s,%s)
        RETURNING id""", (str(body.email), body.display_name, body.ui_locale)).fetchone()
    conn.execute("SELECT set_config('opc.actor_id',%s,true)", (str(row["id"]),))
    conn.execute("INSERT INTO opc.password_credentials(account_id,password_hash) VALUES (%s,%s)",
                 (row["id"], hash_password(body.password.get_secret_value())))
    conn.execute("""INSERT INTO opc.account_roles(account_id,role_code,granted_by,reason)
        VALUES (%s,'customer',%s,'客户自行注册')""", (row["id"], row["id"]))
    return public_account(conn, row["id"])


@router.post("/api/v1/mobile/auth/register", status_code=201, summary="客户注册（不授予承接或管理权限）")
def register(body: RegisterInput, request: Request, conn: TxDep):
    request.app.state.login_limiter.check((request.client.host, "register"), limit=10)
    return create_customer(conn, body)


@router.post("/api/v1/mobile/auth/login", summary="手机端登录")
@router.post("/api/v1/admin/auth/login", summary="管理端独立会话登录")
def login(body: LoginInput, request: Request, conn: TxDep):
    audience = "admin" if "/admin/" in request.url.path else "mobile"
    request.app.state.login_limiter.check((request.client.host, "login"), limit=30)
    request.app.state.login_limiter.check((str(body.email).lower(), audience), limit=10)
    row = conn.execute("""SELECT a.id,a.status,p.password_hash,p.must_change FROM opc.accounts a
        JOIN opc.password_credentials p ON p.account_id=a.id WHERE a.email_normalized=%s FOR SHARE OF a,p""",
                       (str(body.email).lower(),)).fetchone()
    valid = verify_password(row["password_hash"] if row else DUMMY_HASH, body.password.get_secret_value())
    if not row or not valid or row["status"] != "active":
        raise DomainError(401, "INVALID_CREDENTIALS", "邮箱或密码错误，或账号不可用")
    roles = {r["role_code"] for r in conn.execute(
        "SELECT role_code FROM opc.account_roles WHERE account_id=%s AND revoked_at IS NULL FOR SHARE", (row["id"],))}
    if audience == "admin" and not roles & ADMIN_ROLES:
        raise DomainError(403, "ADMIN_FORBIDDEN", "当前账号没有管理权限")
    if row["must_change"]:
        raise DomainError(403, "CREDENTIAL_ACTIVATION_REQUIRED", "请由管理员完成账号激活与凭证更新")
    token = secrets.token_urlsafe(48)
    expiry = datetime.now(timezone.utc) + timedelta(hours=request.app.state.settings.session_hours)
    conn.execute("SELECT set_config('opc.actor_id',%s,true)", (str(row["id"]),))
    conn.execute("""INSERT INTO opc.auth_sessions(account_id,token_hash,audience,expires_at)
        VALUES (%s,%s,%s,%s)""", (row["id"], sha256(token.encode()).hexdigest(), audience, expiry))
    return {"access_token": token, "token_type": "bearer", "audience": audience, "expires_at": expiry}


@router.get("/api/v1/mobile/auth/me", summary="当前手机账号")
@router.get("/api/v1/admin/auth/me", summary="当前管理账号")
def me(actor: ActorDep, conn: TxDep):
    return public_account(conn, actor.id)


@router.patch("/api/v1/mobile/auth/me", summary="更新显示名与中日界面偏好")
@router.patch("/api/v1/admin/auth/me", summary="更新管理账号显示名与界面偏好")
def update_me(body: ProfileInput, actor: ActorDep, conn: TxDep):
    row = conn.execute("SELECT row_version FROM opc.accounts WHERE id=%s FOR UPDATE", (actor.id,)).fetchone()
    check_version(row, body.expected_version)
    conn.execute("UPDATE opc.accounts SET display_name=%s,ui_locale=%s WHERE id=%s",
                 (body.display_name.strip(), body.ui_locale, actor.id))
    return public_account(conn, actor.id)


@router.post("/api/v1/mobile/auth/logout", summary="撤销当前手机会话")
@router.post("/api/v1/admin/auth/logout", summary="撤销当前管理会话")
def logout(actor: ActorDep, conn: TxDep):
    conn.execute("UPDATE opc.auth_sessions SET revoked_at=now() WHERE id=%s", (actor.session_id,))
    return {"revoked": True}


@router.post("/api/v1/mobile/auth/password", summary="修改密码并撤销所有会话")
@router.post("/api/v1/admin/auth/password", summary="修改密码并撤销所有会话")
def password(body: PasswordInput, actor: ActorDep, conn: TxDep):
    conn.execute("SELECT id FROM opc.accounts WHERE id=%s FOR UPDATE", (actor.id,))
    credential = conn.execute("SELECT password_hash FROM opc.password_credentials WHERE account_id=%s FOR UPDATE", (actor.id,)).fetchone()
    if not credential or not verify_password(credential["password_hash"], body.current_password.get_secret_value()):
        raise DomainError(403, "PASSWORD_MISMATCH", "原密码不正确")
    conn.execute("UPDATE opc.password_credentials SET password_hash=%s,changed_at=now(),must_change=false WHERE account_id=%s",
                 (hash_password(body.new_password.get_secret_value()), actor.id))
    conn.execute("UPDATE opc.auth_sessions SET revoked_at=now() WHERE account_id=%s AND revoked_at IS NULL", (actor.id,))
    return {"reauthentication_required": True}


@router.get("/api/v1/admin/accounts", summary="管理账号列表")
def accounts(actor: ActorDep, conn: TxDep, limit: int = Query(30, ge=1, le=100), offset: int = Query(0, ge=0)):
    ensure_admin(actor, "administrator")
    rows = conn.execute("SELECT id FROM opc.accounts ORDER BY created_at DESC,id LIMIT %s OFFSET %s", (limit, offset)).fetchall()
    return {"items": [public_account(conn, r["id"]) for r in rows], "limit": limit, "offset": offset}


@router.post("/api/v1/admin/accounts", status_code=201, summary="创建指定内部账号（权限另行授权）")
def create_account(body: RegisterInput, actor: ActorDep, conn: TxDep):
    ensure_admin(actor, "administrator")
    row = conn.execute("INSERT INTO opc.accounts(email,display_name,ui_locale) VALUES (%s,%s,%s) RETURNING id",
                       (str(body.email), body.display_name, body.ui_locale)).fetchone()
    conn.execute("INSERT INTO opc.password_credentials(account_id,password_hash) VALUES (%s,%s)",
                 (row["id"], hash_password(body.password.get_secret_value())))
    return public_account(conn, row["id"])


def lock_target(conn, account_id):
    row = conn.execute("SELECT * FROM opc.accounts WHERE id=%s FOR UPDATE", (account_id,)).fetchone()
    if not row:
        raise DomainError(404, "NOT_FOUND", "账号不存在")
    return row


def protect_self(actor, account_id):
    if actor.id == account_id:
        raise DomainError(409, "SELF_ADMIN_CHANGE_FORBIDDEN", "管理权限与状态不能由本人撤销")


@router.put("/api/v1/admin/accounts/{account_id}/status", summary="启停账号并撤销全部会话")
def status(account_id: UUID, body: StatusInput, actor: ActorDep, conn: TxDep):
    ensure_admin(actor, "administrator")
    protect_self(actor, account_id)
    row = lock_target(conn, account_id)
    check_version(row, body.expected_version)
    conn.execute("UPDATE opc.accounts SET status=%s WHERE id=%s", (body.status, account_id))
    if body.status == "disabled":
        conn.execute("UPDATE opc.auth_sessions SET revoked_at=now() WHERE account_id=%s AND revoked_at IS NULL", (account_id,))
        conn.execute("""UPDATE opc.provider_authorizations SET revoked_by=%s,revoked_at=now()
            WHERE account_id=%s AND revoked_at IS NULL""", (actor.id, account_id))
    business_audit(conn, "accounts", account_id, body.reason)
    return public_account(conn, account_id)


def business_audit(conn, table, entity_id, reason):
    from psycopg.types.json import Jsonb
    conn.execute("""INSERT INTO opc.audit_events(table_name,operation,entity_key,details,application_actor_id,correlation_id)
        VALUES (%s,'BUSINESS',%s,%s,nullif(current_setting('opc.actor_id',true),'')::uuid,
        current_setting('opc.correlation_id',true))""", (table, Jsonb({"id": str(entity_id)}), Jsonb({"reason": reason})))


@router.post("/api/v1/admin/accounts/{account_id}/roles", summary="授予角色（不自动授予内部接单授权）")
def grant_role(account_id: UUID, body: RoleInput, actor: ActorDep, conn: TxDep):
    ensure_admin(actor, "administrator")
    lock_target(conn, account_id)
    return conn.execute("""INSERT INTO opc.account_roles(account_id,role_code,granted_by,reason)
        VALUES (%s,%s,%s,%s) RETURNING id,role_code,granted_at""", (account_id, body.role, actor.id, body.reason)).fetchone()


@router.post("/api/v1/admin/accounts/{account_id}/roles/revoke", summary="撤销角色")
def revoke_role(account_id: UUID, body: RoleInput, actor: ActorDep, conn: TxDep):
    ensure_admin(actor, "administrator")
    protect_self(actor, account_id)
    lock_target(conn, account_id)
    row = conn.execute("""UPDATE opc.account_roles SET revoked_by=%s,revoked_at=now()
        WHERE account_id=%s AND role_code=%s AND revoked_at IS NULL RETURNING id""", (actor.id, account_id, body.role)).fetchone()
    if not row:
        raise DomainError(404, "NOT_FOUND", "有效角色不存在")
    business_audit(conn, "account_roles", row["id"], body.reason)
    return {"revoked": True}


@router.post("/api/v1/admin/accounts/{account_id}/provider-authorization", summary="授予内部接单授权（不是正式认证）")
def grant_provider(account_id: UUID, body: GrantInput, actor: ActorDep, conn: TxDep):
    ensure_admin(actor, "administrator")
    account = lock_target(conn, account_id)
    if account["status"] != "active" or not conn.execute("SELECT id FROM opc.account_roles WHERE account_id=%s AND role_code='provider' AND revoked_at IS NULL", (account_id,)).fetchone():
        raise DomainError(409, "PROVIDER_ROLE_REQUIRED", "需先启用账号并授予 provider 角色")
    return conn.execute("""INSERT INTO opc.provider_authorizations(account_id,granted_by,reason)
        VALUES (%s,%s,%s) RETURNING id,granted_at""", (account_id, actor.id, body.reason)).fetchone()


@router.post("/api/v1/admin/accounts/{account_id}/provider-authorization/revoke", summary="撤销内部接单授权")
def revoke_provider(account_id: UUID, body: GrantInput, actor: ActorDep, conn: TxDep):
    ensure_admin(actor, "administrator")
    lock_target(conn, account_id)
    row = conn.execute("""UPDATE opc.provider_authorizations SET revoked_by=%s,revoked_at=now()
        WHERE account_id=%s AND revoked_at IS NULL RETURNING id""", (actor.id, account_id)).fetchone()
    if not row:
        raise DomainError(404, "NOT_FOUND", "有效授权不存在")
    business_audit(conn, "provider_authorizations", row["id"], body.reason)
    return {"revoked": True}
