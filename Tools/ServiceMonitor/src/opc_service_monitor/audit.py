from __future__ import annotations

import threading
from dataclasses import dataclass, field
from datetime import UTC, datetime
from functools import wraps
from typing import Any

import httpx


@dataclass(frozen=True, slots=True)
class AdminSession:
    access_token: str = field(repr=False)
    token_type: str
    audience: str
    expires_at: datetime

    def authorization_header(self) -> str:
        return f"Bearer {self.access_token}"


@dataclass(frozen=True, slots=True)
class AdminProfile:
    id: str
    email: str
    display_name: str
    status: str
    ui_locale: str
    row_version: int
    created_at: datetime
    roles: tuple[str, ...]
    internally_authorized: bool
    opc_certified: bool


@dataclass(frozen=True, slots=True)
class AuditEvent:
    id: int
    occurred_at: datetime
    application_actor_id: str | None
    correlation_id: str | None
    table_name: str
    operation: str
    entity_key: dict[str, Any]
    changed_fields: tuple[str, ...]
    details: dict[str, Any]


@dataclass(frozen=True, slots=True)
class AuditPage:
    items: tuple[AuditEvent, ...]
    next_before_id: int | None

    @classmethod
    def from_payload(cls, payload: object) -> AuditPage:
        if not isinstance(payload, dict) or not isinstance(payload.get("items"), list):
            raise AuditClientError("PROTOCOL_ERROR", "审计接口返回格式不正确")
        events: list[AuditEvent] = []
        seen: set[int] = set()
        for raw in payload["items"]:
            event = _parse_event(raw)
            if event.id in seen:
                continue
            seen.add(event.id)
            events.append(event)
        next_before_id = min((event.id for event in events), default=None)
        return cls(tuple(events), next_before_id)

    def merged_with(self, other: AuditPage) -> AuditPage:
        by_id: dict[int, AuditEvent] = {}
        for event in (*self.items, *other.items):
            by_id.setdefault(event.id, event)
        items = tuple(sorted(by_id.values(), key=lambda event: event.id, reverse=True))
        return AuditPage(items, min(by_id, default=None))


class AuditClientError(RuntimeError):
    def __init__(
        self,
        code: str,
        message: str,
        *,
        status_code: int | None = None,
        request_id: str | None = None,
        relogin_required: bool = False,
    ) -> None:
        super().__init__(message)
        self.code = code
        self.status_code = status_code
        self.request_id = request_id
        self.relogin_required = relogin_required


def _serialized(function):
    @wraps(function)
    def wrapper(self: AuditClient, *args: Any, **kwargs: Any):
        with self._request_lock:
            return function(self, *args, **kwargs)

    return wrapper


class AuditClient:
    def __init__(
        self,
        *,
        base_url: str = "http://127.0.0.1:8001",
        timeout_s: float = 3.0,
        transport: httpx.BaseTransport | None = None,
    ) -> None:
        self._base_url = base_url.rstrip("/")
        self._client = httpx.Client(timeout=timeout_s, transport=transport, follow_redirects=False)
        self._session: AdminSession | None = None
        self._request_lock = threading.RLock()

    @property
    def session(self) -> AdminSession | None:
        with self._request_lock:
            return self._session

    @_serialized
    def login(self, email: str, password: str) -> AdminSession:
        response = self._send(
            "POST",
            "/api/v1/admin/auth/login",
            json={"email": email, "password": password},
        )
        payload = _json_object(response)
        try:
            token = payload["access_token"]
            token_type = payload["token_type"]
            audience = payload["audience"]
            expires_at = _parse_datetime(payload["expires_at"])
        except (KeyError, TypeError, ValueError) as exc:
            raise AuditClientError("PROTOCOL_ERROR", "登录接口返回格式不正确") from exc
        if (
            not isinstance(token, str)
            or not token
            or not isinstance(token_type, str)
            or token_type.casefold() != "bearer"
            or audience != "admin"
        ):
            raise AuditClientError("PROTOCOL_ERROR", "登录接口返回格式不正确")
        session = AdminSession(token, "bearer", "admin", expires_at)
        self._session = session
        return session

    @_serialized
    def me(self) -> AdminProfile:
        response = self._send("GET", "/api/v1/admin/auth/me", headers=self._auth_headers())
        payload = _json_object(response)
        try:
            roles = payload["roles"]
            if not isinstance(roles, list) or not all(isinstance(role, str) for role in roles):
                raise TypeError("roles")
            return AdminProfile(
                id=str(payload["id"]),
                email=str(payload["email"]),
                display_name=str(payload["display_name"]),
                status=str(payload["status"]),
                ui_locale=str(payload["ui_locale"]),
                row_version=int(payload["row_version"]),
                created_at=_parse_datetime(payload["created_at"]),
                roles=tuple(roles),
                internally_authorized=bool(payload["internally_authorized"]),
                opc_certified=bool(payload["opc_certified"]),
            )
        except (KeyError, TypeError, ValueError) as exc:
            raise AuditClientError("PROTOCOL_ERROR", "账号接口返回格式不正确") from exc

    @_serialized
    def list_events(self, limit: int = 50, before_id: int | None = None) -> AuditPage:
        if not 1 <= limit <= 100:
            raise ValueError("审计分页数量必须在 1 到 100 之间")
        if before_id is not None and before_id < 1:
            raise ValueError("审计游标必须为正整数")
        params: dict[str, int] = {"limit": limit}
        if before_id is not None:
            params["before_id"] = before_id
        response = self._send(
            "GET",
            "/api/v1/admin/audit-events",
            headers=self._auth_headers(),
            params=params,
        )
        return AuditPage.from_payload(_json_object(response))

    @_serialized
    def logout(self) -> None:
        session = self._session
        if session is None:
            return
        try:
            self._send(
                "POST",
                "/api/v1/admin/auth/logout",
                headers={"Authorization": session.authorization_header()},
            )
        finally:
            self._session = None

    @_serialized
    def close(self) -> None:
        self._session = None
        self._client.close()

    def _auth_headers(self) -> dict[str, str]:
        if self._session is None:
            raise AuditClientError("AUTH_REQUIRED", "请先使用管理员账号登录", relogin_required=True)
        return {"Authorization": self._session.authorization_header()}

    def _send(self, method: str, path: str, **kwargs: Any) -> httpx.Response:
        try:
            response = self._client.request(method, f"{self._base_url}{path}", **kwargs)
        except httpx.TimeoutException as exc:
            raise AuditClientError("TIMEOUT", "后台接口请求超时") from exc
        except httpx.HTTPError as exc:
            raise AuditClientError("CONNECTION_ERROR", "无法连接后台接口") from exc
        if response.is_error:
            self._raise_response_error(response)
        return response

    def _raise_response_error(self, response: httpx.Response) -> None:
        code = "HTTP_ERROR"
        request_id: str | None = None
        try:
            payload = response.json()
            if isinstance(payload, dict):
                error = payload.get("error")
                if isinstance(error, dict) and isinstance(error.get("code"), str):
                    code = error["code"]
                if isinstance(payload.get("request_id"), str):
                    request_id = payload["request_id"]
        except ValueError:
            pass
        relogin = response.status_code == 401 or code in {"AUTH_REQUIRED", "SESSION_INVALID"}
        if relogin:
            self._session = None
        message = _ERROR_MESSAGES.get(code, _status_message(response.status_code))
        raise AuditClientError(
            code,
            message,
            status_code=response.status_code,
            request_id=request_id,
            relogin_required=relogin,
        )


_ERROR_MESSAGES = {
    "INVALID_CREDENTIALS": "邮箱或密码错误，或账号不可用",
    "ADMIN_FORBIDDEN": "该账号没有后台管理权限",
    "CREDENTIAL_ACTIVATION_REQUIRED": "该账号需要先完成激活与凭证更新",
    "RATE_LIMITED": "登录尝试过于频繁，请稍后重试",
    "VALIDATION_ERROR": "输入格式不符合后台接口要求",
    "DATABASE_UNAVAILABLE": "后台数据库不可用，请先检查服务状态",
    "AUTH_REQUIRED": "请先使用管理员账号登录",
    "SESSION_INVALID": "管理员会话已失效，请重新登录",
    "ROLE_FORBIDDEN": "查看业务审计需要 administrator 角色",
}


def _status_message(status_code: int) -> str:
    if status_code == 401:
        return "管理员会话已失效，请重新登录"
    if status_code == 403:
        return "当前管理员权限不足"
    if status_code == 429:
        return "请求过于频繁，请稍后重试"
    if status_code == 503:
        return "后台服务暂时不可用"
    return f"后台接口请求失败（HTTP {status_code}）"


def _json_object(response: httpx.Response) -> dict[str, Any]:
    try:
        payload = response.json()
    except ValueError as exc:
        raise AuditClientError("PROTOCOL_ERROR", "后台接口返回了无效 JSON") from exc
    if not isinstance(payload, dict):
        raise AuditClientError("PROTOCOL_ERROR", "后台接口返回格式不正确")
    return payload


def _parse_datetime(value: object) -> datetime:
    if not isinstance(value, str):
        raise TypeError("datetime")
    parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if parsed.tzinfo is None:
        raise ValueError("timezone required")
    return parsed.astimezone(UTC)


def _parse_event(raw: object) -> AuditEvent:
    if not isinstance(raw, dict):
        raise AuditClientError("PROTOCOL_ERROR", "审计记录格式不正确")
    try:
        entity_key = raw["entity_key"]
        changed_fields = raw["changed_fields"]
        details = raw["details"]
        if not isinstance(entity_key, dict) or not isinstance(details, dict):
            raise TypeError("object fields")
        if not isinstance(changed_fields, list) or not all(isinstance(item, str) for item in changed_fields):
            raise TypeError("changed_fields")
        return AuditEvent(
            id=int(raw["id"]),
            occurred_at=_parse_datetime(raw["occurred_at"]),
            application_actor_id=None
            if raw.get("application_actor_id") is None
            else str(raw["application_actor_id"]),
            correlation_id=None if raw.get("correlation_id") is None else str(raw["correlation_id"]),
            table_name=str(raw["table_name"]),
            operation=str(raw["operation"]),
            entity_key=dict(entity_key),
            changed_fields=tuple(changed_fields),
            details=dict(details),
        )
    except (KeyError, TypeError, ValueError) as exc:
        raise AuditClientError("PROTOCOL_ERROR", "审计记录格式不正确") from exc

