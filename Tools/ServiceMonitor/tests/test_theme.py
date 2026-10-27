from __future__ import annotations

from datetime import UTC, datetime

import pytest
from PySide6.QtCore import QObject, QPoint, QRect, Qt, Signal
from PySide6.QtGui import QColor, QPalette
from PySide6.QtWidgets import QDialog, QScrollArea

from opc_service_monitor.audit import AdminProfile, AdminSession, AuditPage
from opc_service_monitor.catalog import build_catalog
from opc_service_monitor.log_pipeline import make_log_entry
from opc_service_monitor.log_store import LogQuery, LogStore
from opc_service_monitor.models import LogSource
from opc_service_monitor.paths import ProjectLayout
from opc_service_monitor.settings import MonitorSettings, SettingsStore
from opc_service_monitor.supervisor import SupervisorTimeouts
from opc_service_monitor.ui.components import ConsoleButton, ConsoleTabs
from opc_service_monitor.ui.main_window import MainWindow
from opc_service_monitor.ui.theme import PALETTES, apply_theme, theme_stylesheet


class ThemeController(QObject):
    observation_changed = Signal(object)
    operation_started = Signal(str)
    operation_finished = Signal(object)
    operation_error = Signal(str)
    refresh_finished = Signal(object)
    busy = False
    owned_services = ()

    def __init__(self):
        super().__init__()
        self.calls = []
        self.timeouts = SupervisorTimeouts()

    def refresh(self):
        self.calls.append("refresh")
        return True

    def start_all(self):
        self.calls.append("start_all")
        return True

    def stop_all(self):
        self.calls.append("stop_all")
        return True

    def start(self, service):
        self.calls.append(("start", service))
        return True

    def stop(self, service):
        self.calls.append(("stop", service))
        return True

    def update_timeouts(self, timeouts):
        self.timeouts = timeouts


class ThemeAuditClient:
    session = None
    closed = False

    def login(self, _email, _password):
        self.session = AdminSession("synthetic-memory-session", "bearer", "admin", datetime(2030, 1, 1, tzinfo=UTC))
        return self.session

    def me(self):
        return AdminProfile(
            "ui-test", "ui-acceptance@example.invalid", "UI 验收账号", "active", "zh", 1,
            datetime(2026, 10, 25, tzinfo=UTC), ("administrator",), False, False,
        )

    def list_events(self, **_kwargs):
        return AuditPage((), None)

    def logout(self):
        self.session = None

    def close(self):
        self.closed = True


def _sync_task(function, success, error):
    try:
        result = function()
    except Exception as exc:
        error(str(exc), exc)
    else:
        success(result)


@pytest.fixture
def themed_window(opc_root, tmp_path, qtbot, qapp):
    created = []

    def create(*, settings_store=None, settings=None):
        store = LogStore.open(tmp_path / f"theme-logs-{len(created)}.sqlite3")
        store.append([make_log_entry(source=LogSource.BACKEND, stream="stdout", text="UI acceptance synthetic log")])
        controller = ThemeController()
        client = ThemeAuditClient()
        layout = ProjectLayout.validate(opc_root)
        window = MainWindow(
            controller, build_catalog(layout), log_store=store, audit_client=client,
            audit_task_runner=_sync_task, project_layout=layout,
            settings_store=settings_store, settings=settings, url_opener=lambda _url: False,
        )
        qtbot.addWidget(window)
        window.refresh_timer.stop()
        window.show()
        qapp.processEvents()
        qtbot.waitUntil(lambda: all(not panel._active_searches for panel in window.log_panels.values()))
        controller.calls.clear()
        created.append((window, store, client))
        return window, controller, client

    yield create

    for window, store, client in created:
        window.refresh_timer.stop()
        for panel in window.log_panels.values():
            panel.shutdown()
        window.close()
        qtbot.waitUntil(lambda: client.closed)
        store.close()
    apply_theme(qapp, "dark")


def test_light_and_dark_have_complete_valid_palettes(qapp):
    assert set(PALETTES) == {"dark", "light"}
    assert PALETTES["dark"].keys() == PALETTES["light"].keys()
    for mode, palette in PALETTES.items():
        assert all(QColor(value).isValid() for value in palette.values())
        stylesheet = theme_stylesheet(mode)
        assert "$background" not in stylesheet
        for key in ("background", "surface", "text", "danger", "selection", "disabled"):
            assert palette[key] in stylesheet
    assert QColor(PALETTES["dark"]["background"]).lightness() < 50
    assert QColor(PALETTES["light"]["background"]).lightness() > 220


@pytest.mark.parametrize("mode", ["dark", "light"])
def test_applying_theme_updates_palette_and_every_custom_control(themed_window, qapp, monkeypatch, mode):
    window, _controller, _client = themed_window()
    controls = window.findChildren(ConsoleButton) + window.findChildren(ConsoleTabs)
    refreshed = set()
    for control in controls:
        monkeypatch.setattr(control, "refresh_theme", lambda control=control: refreshed.add(id(control)))

    apply_theme(qapp, mode)
    qapp.processEvents()

    assert refreshed == {id(control) for control in controls}
    assert qapp.property("opcTheme") == mode
    assert qapp.palette().color(QPalette.Window).name() == PALETTES[mode]["background"]
    assert qapp.palette().color(QPalette.Disabled, QPalette.Text).name() == PALETTES[mode]["disabled"]
    assert window.log_panels["all"].keyword_edit.palette().color(QPalette.Text).name() == PALETTES[mode]["text"]
    assert window.log_panels["all"].table.palette().color(QPalette.Base).name() == PALETTES[mode]["field"]


@pytest.mark.parametrize("mode", ["light", "dark"])
def test_theme_click_persists_and_new_window_restores(themed_window, tmp_path, qtbot, mode):
    store = SettingsStore(tmp_path / "settings.json")
    opposite = "dark" if mode == "light" else "light"
    store.save(MonitorSettings(theme=opposite))
    window, controller, _client = themed_window(settings_store=store)

    qtbot.mouseClick(window.theme_switch.buttons[mode], Qt.LeftButton)

    assert window.current_theme == mode
    assert store.load().theme == mode
    restored, _other_controller, _other_client = themed_window(settings_store=store)
    assert restored.current_theme == mode
    assert restored.theme_switch.buttons[mode].isChecked()
    assert controller.calls == []


def test_theme_switch_preserves_search_selection_and_audit_session(themed_window, qtbot):
    window, controller, client = themed_window()
    panel = window.log_panels["all"]
    query = LogQuery(keyword="acceptance", case_sensitive=True)
    panel.set_query(query)
    qtbot.waitUntil(lambda: not panel._active_searches)
    panel.table.selectRow(0)
    selected = [(index.row(), index.column()) for index in panel.table.selectedIndexes()]
    assert selected
    entries = panel.visible_entries
    audit = window.audit_panel
    audit.email_edit.setText("ui-acceptance@example.invalid")
    audit.password_edit.setText("synthetic-input")
    audit.login()
    session = client.session
    window.tabs.setCurrentWidget(audit)
    controller.calls.clear()

    qtbot.mouseClick(window.theme_switch.buttons["light"], Qt.LeftButton)

    assert panel._query == query
    assert panel.keyword_edit.text() == "acceptance"
    assert panel.visible_entries == entries
    assert [(index.row(), index.column()) for index in panel.table.selectedIndexes()] == selected
    assert window.tabs.currentWidget() is audit
    assert audit.is_logged_in
    assert client.session is session
    assert controller.calls == []


def test_saving_settings_retains_current_theme(themed_window, tmp_path, monkeypatch):
    store = SettingsStore(tmp_path / "settings.json")
    window, controller, _client = themed_window(settings_store=store)
    window.set_theme("light")
    selected_timeouts = SupervisorTimeouts(postgres=45, backend=50, frontend=55)

    class AcceptedSettings:
        def __init__(self, layout, _timeouts, **_kwargs):
            self.project_layout = layout
            self.selected_timeouts = selected_timeouts

        def exec(self):
            return QDialog.Accepted

    monkeypatch.setattr("opc_service_monitor.ui.main_window.SettingsDialog", AcceptedSettings)
    window._show_settings()

    assert store.load().theme == "light"
    assert store.load().timeouts == selected_timeouts
    assert controller.timeouts == selected_timeouts


def test_failed_theme_preference_save_is_visible_and_does_not_revert_theme(themed_window, tmp_path, monkeypatch):
    store = SettingsStore(tmp_path / "settings.json")
    window, controller, _client = themed_window(settings_store=store)

    def fail_save(_settings):
        raise PermissionError("UI acceptance permission denied")

    monkeypatch.setattr(store, "save", fail_save)
    window.set_theme("light")

    assert window.current_theme == "light"
    assert window.theme_switch.buttons["light"].isChecked()
    assert window.error_banner.isVisible()
    assert "偏好保存失败" in window.error_banner.text()
    assert controller.calls == []


def test_failed_theme_application_keeps_previous_theme_and_saved_preference(themed_window, tmp_path, monkeypatch):
    store = SettingsStore(tmp_path / "settings.json")
    store.save(MonitorSettings(theme="dark"))
    window, controller, _client = themed_window(settings_store=store)
    saved = []

    def fail_apply(_application, _mode):
        raise OSError("UI acceptance theme asset unavailable")

    monkeypatch.setattr("opc_service_monitor.ui.main_window.apply_theme", fail_apply)
    monkeypatch.setattr(store, "save", lambda settings: saved.append(settings))
    window.set_theme("light")

    assert window.current_theme == "dark"
    assert window.theme_switch.buttons["dark"].isChecked()
    assert not window.theme_switch.buttons["light"].isChecked()
    assert window.error_banner.isVisible()
    assert "主题切换失败" in window.error_banner.text()
    assert store.load().theme == "dark"
    assert saved == []
    assert controller.calls == []


def _assert_inside(window, widgets):
    for widget in widgets:
        rect = QRect(widget.mapTo(window, QPoint(0, 0)), widget.size())
        assert window.rect().contains(rect), (type(widget).__name__, widget.objectName(), rect, window.rect())
        assert widget.width() > 0 and widget.height() > 0


@pytest.mark.parametrize("mode", ["dark", "light"])
@pytest.mark.parametrize("size", [(1280, 860), (1024, 740)])
def test_main_and_audit_controls_stay_inside_requested_window(themed_window, qapp, mode, size):
    window, _controller, _client = themed_window(settings=MonitorSettings(theme=mode))
    window.resize(*size)
    qapp.processEvents()
    assert (window.width(), window.height()) == size
    panel = window.log_panels["all"]
    _assert_inside(window, [
        window.theme_switch, window.start_all_button, window.stop_all_button, window.settings_button,
        *window.cards.values(), panel.keyword_edit, panel.source_combo, panel.level_combo,
        panel.start_edit, panel.end_edit, panel.search_button, panel.table, panel.pause_button,
        panel.latest_button, panel.copy_button, panel.clear_button, panel.export_button,
    ])
    assert panel.table.viewport().height() >= 2 * panel.table.verticalHeader().defaultSectionSize()
    window.tabs.setCurrentWidget(window.audit_panel)
    qapp.processEvents()
    assert (window.width(), window.height()) == size
    login_controls = [window.audit_panel.email_edit, window.audit_panel.password_edit, window.audit_panel.login_button]
    login_scroll = window.audit_panel.findChild(QScrollArea, "auditLoginScroll")
    assert login_scroll is not None
    _assert_inside(login_scroll.widget(), login_controls)
    for index, control in enumerate(login_controls):
        rect = QRect(control.mapTo(login_scroll.widget(), QPoint(0, 0)), control.size())
        for following in login_controls[index + 1:]:
            next_rect = QRect(following.mapTo(login_scroll.widget(), QPoint(0, 0)), following.size())
            assert not rect.intersects(next_rect), (rect, next_rect)
    login_scroll.ensureWidgetVisible(window.audit_panel.login_button, 0, 0)
    qapp.processEvents()
    _assert_inside(login_scroll.viewport(), [window.audit_panel.login_button])
