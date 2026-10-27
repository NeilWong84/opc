from __future__ import annotations

import json
from pathlib import Path

import pytest

from opc_service_monitor.settings import MonitorSettings, SettingsStore
from opc_service_monitor.supervisor import SupervisorTimeouts


@pytest.mark.parametrize("theme", ["dark", "light"])
def test_settings_round_trip_only_non_sensitive_values(tmp_path: Path, theme: str) -> None:
    path = tmp_path / "settings.json"
    store = SettingsStore(path)
    settings = MonitorSettings(
        project_root=tmp_path / "OPC",
        timeouts=SupervisorTimeouts(postgres=45, backend=50, frontend=55),
        theme=theme,
    )

    store.save(settings)

    assert store.load() == settings
    payload = json.loads(path.read_text(encoding="utf-8"))
    assert payload == {
        "project_root": str((tmp_path / "OPC").resolve()),
        "timeouts": {"postgresql": 45, "backend": 50, "frontend": 55},
        "theme": theme,
    }
    serialized = path.read_text(encoding="utf-8").casefold()
    assert "password" not in serialized
    assert "token" not in serialized


def test_settings_load_recovers_from_invalid_values(tmp_path: Path) -> None:
    path = tmp_path / "settings.json"
    path.write_text(
        '{"project_root": 123, "timeouts": {"postgresql": 1, "backend": "bad", "frontend": 999}}',
        encoding="utf-8",
    )

    loaded = SettingsStore(path).load()

    assert loaded == MonitorSettings()


def test_settings_save_preserves_no_unknown_or_secret_fields(tmp_path: Path) -> None:
    path = tmp_path / "settings.json"
    path.write_text('{"access_token": "secret", "unknown": true}', encoding="utf-8")

    SettingsStore(path).save(MonitorSettings(project_root=Path("D:/OPC")))

    payload = json.loads(path.read_text(encoding="utf-8"))
    assert set(payload) == {"project_root", "timeouts", "theme"}


@pytest.mark.parametrize("include_timeouts", [False, True])
def test_legacy_settings_without_theme_default_to_dark(tmp_path: Path, include_timeouts: bool) -> None:
    path = tmp_path / "settings.json"
    project_root = (tmp_path / "OPC").resolve()
    payload = {"project_root": str(project_root)}
    if include_timeouts:
        payload["timeouts"] = {"postgresql": 45, "backend": 50, "frontend": 55}
    path.write_text(json.dumps(payload), encoding="utf-8")

    loaded = SettingsStore(path).load()

    assert loaded.project_root == project_root
    assert loaded.theme == "dark"
    assert loaded.timeouts == (
        SupervisorTimeouts(postgres=45, backend=50, frontend=55)
        if include_timeouts else SupervisorTimeouts()
    )


@pytest.mark.parametrize("theme", [None, "", "system", "Dark", 1, True, [], {}, ["light"]])
def test_invalid_saved_theme_falls_back_without_resetting_other_settings(tmp_path: Path, theme: object) -> None:
    path = tmp_path / "settings.json"
    project_root = (tmp_path / "OPC").resolve()
    path.write_text(json.dumps({
        "project_root": str(project_root),
        "timeouts": {"postgresql": 45, "backend": 50, "frontend": 55},
        "theme": theme,
    }), encoding="utf-8")

    assert SettingsStore(path).load() == MonitorSettings(
        project_root=project_root,
        timeouts=SupervisorTimeouts(postgres=45, backend=50, frontend=55),
        theme="dark",
    )


@pytest.mark.parametrize("theme", ["system", "", None, 1, [], {}])
def test_save_rejects_invalid_theme_before_changing_file(tmp_path: Path, theme: object) -> None:
    store = SettingsStore(tmp_path / "settings.json")
    store.save(MonitorSettings(theme="light"))
    original = store.path.read_bytes()

    with pytest.raises(ValueError, match="theme"):
        store.save(MonitorSettings(theme=theme))

    assert store.path.read_bytes() == original


def test_missing_settings_default_to_dark(tmp_path: Path) -> None:
    assert SettingsStore(tmp_path / "missing.json").load().theme == "dark"


def test_invalid_timeouts_keep_original_reset_policy_and_valid_theme(tmp_path: Path) -> None:
    path = tmp_path / "settings.json"
    path.write_text(json.dumps({
        "project_root": str(tmp_path / "OPC"),
        "timeouts": {"postgresql": True, "backend": 50, "frontend": 55},
        "theme": "light",
    }), encoding="utf-8")

    assert SettingsStore(path).load() == MonitorSettings(theme="light")
