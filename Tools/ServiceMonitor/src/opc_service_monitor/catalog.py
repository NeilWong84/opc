from __future__ import annotations

from opc_service_monitor.models import CommandSpec, ServiceDefinition, ServiceId
from opc_service_monitor.paths import ProjectLayout


_PYTHON_ENVIRONMENT = (
    ("PYTHONUTF8", "1"),
    ("PYTHONIOENCODING", "utf-8"),
    ("PYTHONUNBUFFERED", "1"),
)


def build_catalog(layout: ProjectLayout) -> dict[ServiceId, ServiceDefinition]:
    postgres = ServiceDefinition(
        service_id=ServiceId.POSTGRES,
        display_name="PostgreSQL",
        host="127.0.0.1",
        port=55440,
        start_command=CommandSpec(
            executable=str(layout.backend_python),
            arguments=(str(layout.postgres_helper), "start"),
            cwd=layout.backend,
            environment=_PYTHON_ENVIRONMENT,
        ),
        stop_command=CommandSpec(
            executable=str(layout.backend_python),
            arguments=(str(layout.postgres_helper), "stop"),
            cwd=layout.backend,
            environment=_PYTHON_ENVIRONMENT,
        ),
        log_files=(
            layout.integration_dir / "postgres.log",
            layout.integration_dir / "provision.log",
        ),
    )
    backend = ServiceDefinition(
        service_id=ServiceId.BACKEND,
        display_name="后端服务",
        host="127.0.0.1",
        port=8001,
        start_command=CommandSpec(
            executable="powershell.exe",
            arguments=(
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
                str(layout.backend_start_script),
                "-Port",
                "8001",
            ),
            cwd=layout.backend,
            environment=_PYTHON_ENVIRONMENT,
        ),
        health_urls=(
            "http://127.0.0.1:8001/health/live",
            "http://127.0.0.1:8001/health/ready",
        ),
        dependencies=(ServiceId.POSTGRES,),
    )
    frontend = ServiceDefinition(
        service_id=ServiceId.FRONTEND,
        display_name="后台管理前端",
        host="127.0.0.1",
        port=5180,
        start_command=CommandSpec(
            executable="npm.cmd",
            arguments=("run", "dev", "--", "--port", "5180", "--strictPort"),
            cwd=layout.frontend,
        ),
        health_urls=("http://127.0.0.1:5180/",),
        dependencies=(ServiceId.BACKEND,),
    )
    return {
        ServiceId.POSTGRES: postgres,
        ServiceId.BACKEND: backend,
        ServiceId.FRONTEND: frontend,
    }

