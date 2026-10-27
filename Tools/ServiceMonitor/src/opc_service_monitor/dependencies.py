from __future__ import annotations

import shutil
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path

from opc_service_monitor.paths import ProjectLayout


ExecutableFinder = Callable[[str], str | None]


@dataclass(frozen=True, slots=True)
class DependencyCheck:
    key: str
    name: str
    ok: bool
    display_path: str
    message: str


def check_dependencies(
    layout: ProjectLayout,
    *,
    executable_finder: ExecutableFinder = shutil.which,
    postgres_binary: Path = Path(r"C:\Program Files\PostgreSQL\18\bin\pg_ctl.exe"),
) -> tuple[DependencyCheck, ...]:
    """Check only the approved local prerequisites without executing them."""

    npm_path = executable_finder("npm.cmd") or executable_finder("npm")
    postgres_path = Path(postgres_binary).expanduser()
    node_modules = layout.frontend / "node_modules"

    return (
        _file_check(
            "backend_python",
            "BackendService Python",
            layout.backend_python,
            "请先在 BackendService 创建并安装 Python 3.12 虚拟环境。",
        ),
        _file_check(
            "backend_start",
            "后端启动脚本",
            layout.backend_start_script,
            "请恢复 BackendService/scripts/start.ps1。",
        ),
        _file_check(
            "postgres_helper",
            "PostgreSQL 联调助手",
            layout.postgres_helper,
            "请恢复 BackendService/scripts/provision-local-integration.py。",
        ),
        _file_check(
            "postgres_18",
            "PostgreSQL 18 pg_ctl",
            postgres_path,
            "请按联调助手约定安装 PostgreSQL 18 到 C:\\Program Files\\PostgreSQL\\18。",
        ),
        DependencyCheck(
            key="npm",
            name="Node.js npm",
            ok=bool(npm_path and Path(npm_path).is_file()),
            display_path=str(Path(npm_path).resolve()) if npm_path and Path(npm_path).is_file() else "npm.cmd（PATH）",
            message="已找到 npm。" if npm_path and Path(npm_path).is_file() else "请安装 Node.js，并确保 npm.cmd 可从 PATH 访问。",
        ),
        DependencyCheck(
            key="frontend_dependencies",
            name="FrontendAdmin 依赖",
            ok=node_modules.is_dir(),
            display_path=str(node_modules),
            message="前端依赖目录存在。" if node_modules.is_dir() else "请在 FrontendAdmin 目录执行 npm install。",
        ),
    )


def _file_check(key: str, name: str, path: Path, missing_message: str) -> DependencyCheck:
    resolved = Path(path).expanduser().resolve()
    exists = resolved.is_file()
    return DependencyCheck(
        key=key,
        name=name,
        ok=exists,
        display_path=str(resolved),
        message="依赖文件存在。" if exists else missing_message,
    )
