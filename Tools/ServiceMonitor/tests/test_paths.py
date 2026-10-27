from __future__ import annotations

from pathlib import Path

import pytest

from opc_service_monitor.paths import ProjectLayout, RuntimePaths, discover_project_root


def test_validates_expected_opc_root(opc_root: Path) -> None:
    layout = ProjectLayout.validate(opc_root)

    assert layout.root == opc_root.resolve()
    assert layout.backend == (opc_root / "BackendService").resolve()
    assert layout.frontend == (opc_root / "FrontendAdmin").resolve()
    assert layout.database == (opc_root / "DB").resolve()
    assert layout.backend_start_script.name == "start.ps1"
    assert layout.postgres_helper.name == "provision-local-integration.py"


@pytest.mark.parametrize(
    "missing",
    [
        "README.md",
        "BackendService/scripts/start.ps1",
        "BackendService/scripts/provision-local-integration.py",
        "FrontendAdmin/package.json",
        "DB/README.md",
    ],
)
def test_rejects_missing_required_module(opc_root: Path, missing: str) -> None:
    target = opc_root / Path(missing)
    target.unlink()

    with pytest.raises(ValueError, match="OPC"):
        ProjectLayout.validate(opc_root)


def test_discovers_saved_before_source_and_default(opc_root: Path, tmp_path: Path) -> None:
    source_root = tmp_path / "source-root"
    default_root = tmp_path / "default-root"
    _copy_markers(opc_root, source_root)
    _copy_markers(opc_root, default_root)
    source_anchor = source_root / "Tools" / "ServiceMonitor" / "src" / "opc_service_monitor" / "paths.py"
    source_anchor.parent.mkdir(parents=True)
    source_anchor.write_text("", encoding="utf-8")

    found = discover_project_root(
        saved=opc_root,
        source_anchor=source_anchor,
        packaged=False,
        default_root=default_root,
    )

    assert found is not None
    assert found.root == opc_root.resolve()


def test_packaged_discovery_skips_executable_ancestry_and_uses_default(opc_root: Path, tmp_path: Path) -> None:
    source_root = tmp_path / "source-root"
    default_root = tmp_path / "default-root"
    invalid = tmp_path / "not-opc"
    invalid.mkdir()
    _copy_markers(opc_root, source_root)
    _copy_markers(opc_root, default_root)
    source_anchor = source_root / "Tools" / "ServiceMonitor" / "monitor.exe"
    source_anchor.parent.mkdir(parents=True)
    source_anchor.write_bytes(b"")

    found = discover_project_root(
        saved=invalid,
        source_anchor=source_anchor,
        packaged=True,
        default_root=default_root,
    )

    assert found is not None
    assert found.root == default_root.resolve()


def test_source_discovery_uses_source_ancestry_before_default(opc_root: Path, tmp_path: Path) -> None:
    source_root = tmp_path / "source-root"
    default_root = tmp_path / "default-root"
    _copy_markers(opc_root, source_root)
    _copy_markers(opc_root, default_root)
    source_anchor = source_root / "Tools" / "ServiceMonitor" / "src" / "opc_service_monitor" / "paths.py"
    source_anchor.parent.mkdir(parents=True)
    source_anchor.write_text("", encoding="utf-8")

    found = discover_project_root(
        saved=None,
        source_anchor=source_anchor,
        packaged=False,
        default_root=default_root,
    )

    assert found is not None
    assert found.root == source_root.resolve()


def test_returns_none_when_no_candidate_is_valid(tmp_path: Path) -> None:
    assert (
        discover_project_root(
            saved=tmp_path / "saved",
            source_anchor=tmp_path / "package" / "monitor.exe",
            packaged=True,
            default_root=tmp_path / "default",
        )
        is None
    )


def test_runtime_paths_stay_under_localappdata(tmp_path: Path) -> None:
    local_app_data = tmp_path / "LocalAppData"
    paths = RuntimePaths.from_environment({"LOCALAPPDATA": str(local_app_data)})

    expected_root = local_app_data / "OPC" / "ServiceMonitor"
    assert paths.root == expected_root.resolve()
    assert paths.settings.parent == paths.root
    assert paths.log_database.parent == paths.root
    assert paths.diagnostics.parent == paths.root
    assert all(path.is_relative_to(paths.root) for path in paths.all_paths())


def test_runtime_paths_allow_explicit_test_override(tmp_path: Path) -> None:
    override = tmp_path / "isolated-test-data"
    paths = RuntimePaths.from_environment(
        {"LOCALAPPDATA": str(tmp_path / "ignored"), "OPC_SERVICE_MONITOR_DATA_DIR": str(override)}
    )

    assert paths.root == override.resolve()


def test_runtime_paths_require_localappdata() -> None:
    with pytest.raises(ValueError, match="LOCALAPPDATA"):
        RuntimePaths.from_environment({})


def _copy_markers(source: Path, target: Path) -> None:
    (target / "BackendService" / "scripts").mkdir(parents=True)
    (target / "FrontendAdmin").mkdir()
    (target / "DB").mkdir()
    for relative in (
        "README.md",
        "BackendService/scripts/start.ps1",
        "BackendService/scripts/provision-local-integration.py",
        "FrontendAdmin/package.json",
        "DB/README.md",
    ):
        destination = target / relative
        destination.write_bytes((source / relative).read_bytes())

