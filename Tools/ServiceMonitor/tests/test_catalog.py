from __future__ import annotations

from pathlib import Path

from opc_service_monitor.catalog import build_catalog
from opc_service_monitor.models import ServiceId
from opc_service_monitor.paths import ProjectLayout


def test_catalog_has_only_three_approved_services(opc_root: Path) -> None:
    catalog = build_catalog(ProjectLayout.validate(opc_root))

    assert set(catalog) == {ServiceId.POSTGRES, ServiceId.BACKEND, ServiceId.FRONTEND}
    assert {definition.port for definition in catalog.values()} == {55440, 8001, 5180}
    assert all(definition.host == "127.0.0.1" for definition in catalog.values())


def test_backend_command_and_health_contract_are_fixed(opc_root: Path) -> None:
    layout = ProjectLayout.validate(opc_root)
    backend = build_catalog(layout)[ServiceId.BACKEND]

    assert backend.start_command.executable.casefold() == "powershell.exe"
    assert backend.start_command.arguments == (
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        str(layout.backend_start_script),
        "-Port",
        "8001",
    )
    assert backend.start_command.cwd == layout.backend
    assert backend.health_urls == (
        "http://127.0.0.1:8001/health/live",
        "http://127.0.0.1:8001/health/ready",
    )
    assert backend.dependencies == (ServiceId.POSTGRES,)
    assert backend.start_command.environment == (
        ("PYTHONUTF8", "1"),
        ("PYTHONIOENCODING", "utf-8"),
        ("PYTHONUNBUFFERED", "1"),
    )


def test_frontend_command_and_health_contract_are_fixed(opc_root: Path) -> None:
    layout = ProjectLayout.validate(opc_root)
    frontend = build_catalog(layout)[ServiceId.FRONTEND]

    assert frontend.start_command.executable.casefold() == "npm.cmd"
    assert frontend.start_command.arguments == ("run", "dev", "--", "--port", "5180", "--strictPort")
    assert frontend.start_command.cwd == layout.frontend
    assert frontend.health_urls == ("http://127.0.0.1:5180/",)
    assert frontend.dependencies == (ServiceId.BACKEND,)


def test_postgres_uses_existing_helper_and_exact_log_allowlist(opc_root: Path) -> None:
    layout = ProjectLayout.validate(opc_root)
    postgres = build_catalog(layout)[ServiceId.POSTGRES]

    assert postgres.start_command.executable == str(layout.backend_python)
    assert postgres.start_command.arguments == (str(layout.postgres_helper), "start")
    assert postgres.stop_command is not None
    assert postgres.stop_command.executable == str(layout.backend_python)
    assert postgres.stop_command.arguments == (str(layout.postgres_helper), "stop")
    assert postgres.start_command.cwd == layout.backend
    assert postgres.start_command.environment == (
        ("PYTHONUTF8", "1"),
        ("PYTHONIOENCODING", "utf-8"),
        ("PYTHONUNBUFFERED", "1"),
    )
    assert postgres.dependencies == ()
    assert postgres.log_files == (
        layout.integration_dir / "postgres.log",
        layout.integration_dir / "provision.log",
    )


def test_catalog_contains_no_mobile_or_secret_material(opc_root: Path) -> None:
    catalog = build_catalog(ProjectLayout.validate(opc_root))
    serialized_parts: list[str] = []
    for definition in catalog.values():
        serialized_parts.extend(
            [
                definition.display_name,
                definition.start_command.executable,
                *definition.start_command.arguments,
                str(definition.start_command.cwd),
                *(str(path) for path in definition.log_files),
            ]
        )
        if definition.stop_command is not None:
            serialized_parts.extend(
                [definition.stop_command.executable, *definition.stop_command.arguments, str(definition.stop_command.cwd)]
            )

    normalized = " ".join(serialized_parts).casefold()
    for forbidden in ("flutter", "adb", "demo-credentials", ".env", "password=", "postgresql://"):
        assert forbidden not in normalized


def test_catalog_commands_have_no_shell_text_or_unapproved_environment(opc_root: Path) -> None:
    catalog = build_catalog(ProjectLayout.validate(opc_root))

    for definition in catalog.values():
        for command in (definition.start_command, definition.stop_command):
            if command is None:
                continue
            assert isinstance(command.arguments, tuple)
            assert command.shell is False
            assert set(command.environment) <= {
                ("PYTHONUTF8", "1"),
                ("PYTHONIOENCODING", "utf-8"),
                ("PYTHONUNBUFFERED", "1"),
            }
            assert not any("&" in argument or "|" in argument for argument in command.arguments)

