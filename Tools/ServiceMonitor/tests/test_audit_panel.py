from __future__ import annotations

import threading
import time
from datetime import UTC, datetime

from opc_service_monitor.audit import AdminProfile, AdminSession, AuditClientError, AuditPage
from opc_service_monitor.ui.audit_panel import AuditPanel


def _payload(ids: list[int]) -> dict[str, object]:
    return {
        "items": [
            {
                "id": event_id,
                "occurred_at": "2026-10-22T12:00:00+00:00",
                "application_actor_id": "actor-a" if event_id % 2 == 0 else "actor-b",
                "correlation_id": f"correlation-{event_id}",
                "table_name": "requests" if event_id % 2 == 0 else "accounts",
                "operation": "UPDATE" if event_id % 2 == 0 else "INSERT",
                "entity_key": {"id": event_id},
                "changed_fields": ["status"],
                "details": {"note": f"event-{event_id}"},
            }
            for event_id in ids
        ]
    }


class FakeAuditClient:
    def __init__(self) -> None:
        self.session = None
        self.login_error: AuditClientError | None = None
        self.list_error: AuditClientError | None = None
        self.pages = [AuditPage.from_payload(_payload([10, 9])), AuditPage.from_payload(_payload([9, 8])), AuditPage((), None)]
        self.list_calls: list[int | None] = []
        self.logout_calls = 0
        self.close_calls = 0

    def login(self, email: str, password: str) -> AdminSession:
        if self.login_error is not None:
            raise self.login_error
        assert email == "admin@example.jp"
        assert password == "manual-password"
        self.session = AdminSession("memory-token", "bearer", "admin", datetime(2026, 10, 23, tzinfo=UTC))
        return self.session

    def me(self) -> AdminProfile:
        return AdminProfile(
            "id",
            "admin@example.jp",
            "Admin",
            "active",
            "zh",
            1,
            datetime(2026, 10, 1, tzinfo=UTC),
            ("administrator",),
            False,
            False,
        )

    def list_events(self, limit: int = 50, before_id: int | None = None) -> AuditPage:
        assert limit == 50
        self.list_calls.append(before_id)
        if self.list_error is not None:
            raise self.list_error
        return self.pages.pop(0)

    def logout(self) -> None:
        self.logout_calls += 1
        self.session = None

    def close(self) -> None:
        self.close_calls += 1
        self.session = None


def _sync_runner(function, success, error) -> None:
    try:
        result = function()
    except Exception as exc:
        error(str(exc), exc)
    else:
        success(result)


def _logged_panel(qtbot):
    client = FakeAuditClient()
    panel = AuditPanel(client, task_runner=_sync_runner)
    qtbot.addWidget(panel)
    panel.email_edit.setText("admin@example.jp")
    panel.password_edit.setText("manual-password")
    panel.login()
    return panel, client


def test_login_clears_password_and_keeps_token_only_in_client_memory(qtbot) -> None:
    panel, client = _logged_panel(qtbot)

    assert panel.password_edit.text() == ""
    assert panel.is_logged_in is True
    assert client.session is not None
    assert "memory-token" not in repr(panel.__dict__)
    assert [event.id for event in panel.loaded_events] == [10, 9]


def test_load_more_uses_min_cursor_and_deduplicates(qtbot) -> None:
    panel, client = _logged_panel(qtbot)

    panel.load_more()
    assert client.list_calls == [None, 9]
    assert [event.id for event in panel.loaded_events] == [10, 9, 8]
    panel.load_more()
    assert panel.load_more_button.isEnabled() is False


def test_loaded_rows_filter_by_actor_table_operation_and_keyword(qtbot) -> None:
    panel, _client = _logged_panel(qtbot)
    panel.load_more()

    panel.set_filters(actor="actor-a", table="requests", operation="UPDATE", keyword="event-8")

    assert [event.id for event in panel.visible_events] == [8]


def test_401_returns_to_login_and_clears_cache(qtbot) -> None:
    panel, client = _logged_panel(qtbot)
    client.list_error = AuditClientError("SESSION_INVALID", "会话已失效", status_code=401, relogin_required=True)
    client.session = None

    panel.refresh_events()

    assert panel.is_logged_in is False
    assert panel.loaded_events == ()
    assert "重新登录" in panel.error_label.text() or "失效" in panel.error_label.text()


def test_403_keeps_login_and_shows_administrator_guidance(qtbot) -> None:
    panel, client = _logged_panel(qtbot)
    client.list_error = AuditClientError("ROLE_FORBIDDEN", "查看业务审计需要 administrator 角色", status_code=403)

    panel.refresh_events()

    assert panel.is_logged_in is True
    assert "administrator" in panel.error_label.text()


def test_logout_revokes_and_clears_cache_and_close_clears_client(qtbot) -> None:
    panel, client = _logged_panel(qtbot)

    panel.logout()
    assert client.logout_calls == 1
    assert panel.loaded_events == ()
    assert panel.is_logged_in is False

    panel.shutdown()
    qtbot.waitUntil(lambda: client.close_calls == 1)


def test_login_error_mapping_is_visible_and_password_not_retained(qtbot) -> None:
    client = FakeAuditClient()
    client.login_error = AuditClientError("ADMIN_FORBIDDEN", "该账号没有后台管理权限", status_code=403)
    panel = AuditPanel(client, task_runner=_sync_runner)
    qtbot.addWidget(panel)
    panel.email_edit.setText("admin@example.jp")
    panel.password_edit.setText("manual-password")

    panel.login()

    assert panel.password_edit.text() == ""
    assert panel.is_logged_in is False
    assert "管理权限" in panel.error_label.text()


def test_shutdown_revokes_session_off_the_gui_thread(qtbot) -> None:
    class BlockingAuditClient(FakeAuditClient):
        def __init__(self) -> None:
            super().__init__()
            self.session = AdminSession("memory-token", "bearer", "admin", datetime(2026, 10, 23, tzinfo=UTC))
            self.logout_entered = threading.Event()
            self.logout_release = threading.Event()

        def logout(self) -> None:
            self.logout_entered.set()
            assert self.logout_release.wait(2)
            super().logout()

    client = BlockingAuditClient()
    panel = AuditPanel(client)
    qtbot.addWidget(panel)

    started = time.monotonic()
    panel.shutdown()

    assert time.monotonic() - started < 0.2
    assert client.logout_entered.wait(1)
    assert client.close_calls == 0
    client.logout_release.set()
    qtbot.waitUntil(lambda: client.close_calls == 1)

