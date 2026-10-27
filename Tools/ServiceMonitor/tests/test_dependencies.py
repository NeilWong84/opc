from __future__ import annotations

from pathlib import Path

from opc_service_monitor.dependencies import check_dependencies
from opc_service_monitor.paths import ProjectLayout


def test_dependency_check_reports_each_required_local_tool(opc_root: Path, tmp_path: Path) -> None:
    node_modules = opc_root / "FrontendAdmin" / "node_modules"
    node_modules.mkdir()
    pg_ctl = tmp_path / "PostgreSQL" / "18" / "bin" / "pg_ctl.exe"
    pg_ctl.parent.mkdir(parents=True)
    pg_ctl.write_bytes(b"")
    npm = tmp_path / "node" / "npm.cmd"
    npm.parent.mkdir()
    npm.write_text("", encoding="utf-8")

    results = check_dependencies(
        ProjectLayout.validate(opc_root),
        executable_finder=lambda name: str(npm) if name == "npm.cmd" else None,
        postgres_binary=pg_ctl,
    )

    assert [result.key for result in results] == [
        "backend_python",
        "backend_start",
        "postgres_helper",
        "postgres_18",
        "npm",
        "frontend_dependencies",
    ]
    assert all(result.ok for result in results)
    assert all(result.display_path for result in results)
    assert all(result.message for result in results)


def test_dependency_check_is_read_only_and_actionable_when_missing(opc_root: Path, tmp_path: Path) -> None:
    (opc_root / "BackendService" / ".venv" / "Scripts" / "python.exe").unlink()
    results = check_dependencies(
        ProjectLayout.validate(opc_root),
        executable_finder=lambda _name: None,
        postgres_binary=tmp_path / "missing-pg_ctl.exe",
    )

    failed = {result.key: result for result in results if not result.ok}
    assert set(failed) == {"backend_python", "postgres_18", "npm", "frontend_dependencies"}
    assert "安装" in failed["npm"].message
    assert "npm" in failed["npm"].display_path.casefold()
    assert not (opc_root / "FrontendAdmin" / "node_modules").exists()


def test_postgres_check_matches_the_fixed_binary_used_by_existing_helper(opc_root: Path, tmp_path: Path) -> None:
    unrelated_pg_ctl = tmp_path / "PostgreSQL" / "17" / "bin" / "pg_ctl.exe"
    unrelated_pg_ctl.parent.mkdir(parents=True)
    unrelated_pg_ctl.write_bytes(b"")
    configured = tmp_path / "PostgreSQL" / "18" / "bin" / "pg_ctl.exe"

    results = check_dependencies(
        ProjectLayout.validate(opc_root),
        executable_finder=lambda name: str(unrelated_pg_ctl) if name.startswith("pg_ctl") else None,
        postgres_binary=configured,
    )

    postgres = next(result for result in results if result.key == "postgres_18")
    assert postgres.ok is False
    assert postgres.display_path == str(configured.resolve())
