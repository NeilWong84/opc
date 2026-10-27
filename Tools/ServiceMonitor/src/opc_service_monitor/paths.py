from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Mapping


_REQUIRED_MARKERS = (
    Path("README.md"),
    Path("BackendService/scripts/start.ps1"),
    Path("BackendService/scripts/provision-local-integration.py"),
    Path("FrontendAdmin/package.json"),
    Path("DB/README.md"),
)


@dataclass(frozen=True, slots=True)
class ProjectLayout:
    root: Path
    backend: Path
    frontend: Path
    database: Path
    backend_start_script: Path
    postgres_helper: Path
    backend_python: Path
    integration_dir: Path

    @classmethod
    def validate(cls, root: Path) -> ProjectLayout:
        resolved = Path(root).expanduser().resolve()
        missing = [str(marker) for marker in _REQUIRED_MARKERS if not (resolved / marker).is_file()]
        if missing:
            joined = ", ".join(missing)
            raise ValueError(f"不是有效的 OPC 项目根目录，缺少: {joined}")
        return cls(
            root=resolved,
            backend=resolved / "BackendService",
            frontend=resolved / "FrontendAdmin",
            database=resolved / "DB",
            backend_start_script=resolved / "BackendService" / "scripts" / "start.ps1",
            postgres_helper=resolved / "BackendService" / "scripts" / "provision-local-integration.py",
            backend_python=resolved / "BackendService" / ".venv" / "Scripts" / "python.exe",
            integration_dir=resolved / "BackendService" / ".local" / "integration",
        )


@dataclass(frozen=True, slots=True)
class RuntimePaths:
    root: Path
    settings: Path
    log_database: Path
    diagnostics: Path
    exports: Path

    @classmethod
    def from_environment(cls, environment: Mapping[str, str]) -> RuntimePaths:
        override = environment.get("OPC_SERVICE_MONITOR_DATA_DIR")
        if override:
            root = Path(override).expanduser().resolve()
        else:
            local_app_data = environment.get("LOCALAPPDATA")
            if not local_app_data:
                raise ValueError("LOCALAPPDATA 未设置，无法确定监控器数据目录")
            root = (Path(local_app_data).expanduser() / "OPC" / "ServiceMonitor").resolve()
        return cls(
            root=root,
            settings=root / "settings.json",
            log_database=root / "runtime-logs.sqlite3",
            diagnostics=root / "monitor.log",
            exports=root / "exports",
        )

    def all_paths(self) -> tuple[Path, ...]:
        return (self.root, self.settings, self.log_database, self.diagnostics, self.exports)

    def ensure_directories(self) -> None:
        self.root.mkdir(parents=True, exist_ok=True)
        self.exports.mkdir(parents=True, exist_ok=True)


def discover_project_root(
    saved: Path | None,
    source_anchor: Path,
    packaged: bool,
    default_root: Path | None = None,
) -> ProjectLayout | None:
    """Return the first valid root in saved, source ancestry, then D:\\OPC order."""

    candidates: list[Path] = []
    if saved is not None:
        candidates.append(Path(saved))

    if not packaged:
        anchor = Path(source_anchor).expanduser().resolve()
        start = anchor if anchor.is_dir() else anchor.parent
        candidates.extend((start, *start.parents))
    candidates.append(Path("D:/OPC") if default_root is None else Path(default_root))

    seen: set[Path] = set()
    for candidate in candidates:
        resolved = candidate.expanduser().resolve()
        if resolved in seen:
            continue
        seen.add(resolved)
        try:
            return ProjectLayout.validate(resolved)
        except (OSError, ValueError):
            continue
    return None

