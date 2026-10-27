from __future__ import annotations

import gc
import json
import threading
from datetime import UTC, datetime

import httpx
import pytest

from opc_service_monitor.audit import AuditClient, AuditClientError, AuditPage


TOKEN = "admin-token-value"


def _login_response() -> dict[str, str]:
    return {
        "access_token": TOKEN,
        "token_type": "bearer",
        "audience": "admin",
        "expires_at": "2026-10-23T12:00:00+00:00",
    }


def _event(event_id: int) -> dict[str, object]:
    return {
        "id": event_id,
        "occurred_at": "2026-10-22T12:00:00+00:00",
        "application_actor_id": "actor-id",
        "correlation_id": "correlation-id",
        "table_name": "requests",
        "operation": "UPDATE",
        "entity_key": {"id": "request-id"},
        "changed_fields": ["status"],
        "details": {"source": "admin"},
    }


def test_login_me_audit_and_logout_use_exact_contracts() -> None:
    requests: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        requests.append(request)
        if request.url.path.endswith("/login"):
            assert json.loads(request.content) == {"email": "admin@example.jp", "password": "manual-password"}
            assert "authorization" not in request.headers
            return httpx.Response(200, json=_login_response())
        assert request.headers["Authorization"] == f"Bearer {TOKEN}"
        if request.url.path.endswith("/me"):
            return httpx.Response(
                200,
                json={
                    "id": "account-id",
                    "email": "admin@example.jp",
                    "display_name": "Admin",
                    "status": "active",
                    "ui_locale": "zh",
                    "row_version": 1,
                    "created_at": "2026-10-01T00:00:00+00:00",
                    "roles": ["administrator"],
                    "internally_authorized": False,
                    "opc_certified": False,
                },
            )
        if request.url.path.endswith("/audit-events"):
            assert dict(request.url.params) == {"limit": "50", "before_id": "99"}
            return httpx.Response(200, json={"items": [_event(98), _event(97)]})
        return httpx.Response(200, json={"revoked": True})

    client = AuditClient(transport=httpx.MockTransport(handler))
    session = client.login("admin@example.jp", "manual-password")
    profile = client.me()
    page = client.list_events(before_id=99)
    client.logout()
    client.close()

    assert session.audience == "admin"
    assert session.expires_at == datetime(2026, 10, 23, 12, 0, tzinfo=UTC)
    assert "administrator" in profile.roles
    assert [item.id for item in page.items] == [98, 97]
    assert page.next_before_id == 97
    assert client.session is None
    assert [request.url.path for request in requests] == [
        "/api/v1/admin/auth/login",
        "/api/v1/admin/auth/me",
        "/api/v1/admin/audit-events",
        "/api/v1/admin/auth/logout",
    ]


def test_login_response_is_strictly_validated() -> None:
    client = AuditClient(transport=httpx.MockTransport(lambda _request: httpx.Response(200, json={"token": "wrong"})))
    try:
        with pytest.raises(AuditClientError) as captured:
            client.login("admin@example.jp", "password")
        assert captured.value.code == "PROTOCOL_ERROR"
        assert client.session is None
    finally:
        client.close()


@pytest.mark.parametrize(
    ("status", "code", "message_fragment"),
    [
        (401, "INVALID_CREDENTIALS", "邮箱或密码"),
        (403, "ADMIN_FORBIDDEN", "管理权限"),
        (403, "CREDENTIAL_ACTIVATION_REQUIRED", "激活"),
        (429, "RATE_LIMITED", "频繁"),
        (422, "VALIDATION_ERROR", "格式"),
        (503, "DATABASE_UNAVAILABLE", "数据库"),
    ],
)
def test_login_maps_known_errors_without_echoing_server_body(
    status: int, code: str, message_fragment: str
) -> None:
    def handler(_request: httpx.Request) -> httpx.Response:
        return httpx.Response(
            status,
            json={"error": {"code": code, "message": "server-secret-value"}, "request_id": "req-1"},
        )

    client = AuditClient(transport=httpx.MockTransport(handler))
    try:
        with pytest.raises(AuditClientError) as captured:
            client.login("admin@example.jp", "password")
        assert captured.value.code == code
        assert message_fragment in str(captured.value)
        assert "server-secret-value" not in str(captured.value)
    finally:
        client.close()


def test_authenticated_401_clears_in_memory_session() -> None:
    calls = 0

    def handler(_request: httpx.Request) -> httpx.Response:
        nonlocal calls
        calls += 1
        if calls == 1:
            return httpx.Response(200, json=_login_response())
        return httpx.Response(
            401,
            json={"error": {"code": "SESSION_INVALID", "message": "ignored"}, "request_id": "req-2"},
        )

    client = AuditClient(transport=httpx.MockTransport(handler))
    try:
        client.login("admin@example.jp", "password")
        with pytest.raises(AuditClientError) as captured:
            client.list_events()
        assert captured.value.relogin_required is True
        assert client.session is None
    finally:
        client.close()


def test_role_forbidden_has_administrator_guidance() -> None:
    calls = 0

    def handler(_request: httpx.Request) -> httpx.Response:
        nonlocal calls
        calls += 1
        if calls == 1:
            return httpx.Response(200, json=_login_response())
        return httpx.Response(
            403,
            json={"error": {"code": "ROLE_FORBIDDEN", "message": "ignored"}, "request_id": "req-3"},
        )

    client = AuditClient(transport=httpx.MockTransport(handler))
    try:
        client.login("admin@example.jp", "password")
        with pytest.raises(AuditClientError, match="administrator"):
            client.list_events()
    finally:
        client.close()


def test_pages_use_minimum_id_and_combine_without_duplicates() -> None:
    first = AuditPage.from_payload({"items": [_event(10), _event(9)]})
    second = AuditPage.from_payload({"items": [_event(9), _event(8)]})

    combined = first.merged_with(second)

    assert [event.id for event in combined.items] == [10, 9, 8]
    assert combined.next_before_id == 8


def test_password_is_not_retained_or_exposed_by_repr() -> None:
    password = "one-time-password-value"
    client = AuditClient(transport=httpx.MockTransport(lambda _request: httpx.Response(200, json=_login_response())))
    try:
        session = client.login("admin@example.jp", password)
        password = "overwritten"
        gc.collect()

        assert "admin-token-value" not in repr(session)
        assert "one-time-password-value" not in repr(client.__dict__)
        assert not hasattr(client, "password")
    finally:
        client.close()


def test_logout_always_clears_session_when_revocation_fails() -> None:
    calls = 0

    def handler(_request: httpx.Request) -> httpx.Response:
        nonlocal calls
        calls += 1
        if calls == 1:
            return httpx.Response(200, json=_login_response())
        return httpx.Response(
            503,
            json={"error": {"code": "DATABASE_UNAVAILABLE", "message": "ignored"}, "request_id": "req-4"},
        )

    client = AuditClient(transport=httpx.MockTransport(handler))
    try:
        client.login("admin@example.jp", "password")
        with pytest.raises(AuditClientError):
            client.logout()
        assert client.session is None
    finally:
        client.close()


def test_logout_and_new_login_are_serialized_so_old_logout_cannot_clear_new_session() -> None:
    logout_entered = threading.Event()
    logout_release = threading.Event()
    login_count = 0

    def handler(request: httpx.Request) -> httpx.Response:
        nonlocal login_count
        if request.url.path.endswith("/login"):
            login_count += 1
            payload = _login_response()
            payload["access_token"] = f"token-{login_count}"
            return httpx.Response(200, json=payload)
        if request.url.path.endswith("/logout"):
            logout_entered.set()
            assert logout_release.wait(2)
            return httpx.Response(200, json={"revoked": True})
        raise AssertionError(request.url.path)

    client = AuditClient(transport=httpx.MockTransport(handler))
    client.login("admin@example.jp", "first-password")
    logout_thread = threading.Thread(target=client.logout)
    login_thread = threading.Thread(target=lambda: client.login("admin@example.jp", "second-password"))
    try:
        logout_thread.start()
        assert logout_entered.wait(1)
        login_thread.start()
        logout_release.set()
        logout_thread.join(2)
        login_thread.join(2)

        assert not logout_thread.is_alive()
        assert not login_thread.is_alive()
        assert client.session is not None
        assert client.session.authorization_header() == "Bearer token-2"
    finally:
        logout_release.set()
        logout_thread.join(2)
        login_thread.join(2)
        client.close()

