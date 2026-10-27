from __future__ import annotations

import socket
from collections.abc import Callable
from datetime import UTC, datetime

import httpx

from opc_service_monitor.models import HealthResult


PortProbe = Callable[[str, int, float], bool]


class HealthProbe:
    def __init__(
        self,
        *,
        backend_base_url: str = "http://127.0.0.1:8001",
        frontend_url: str = "http://127.0.0.1:5180/",
        timeout_s: float = 3.0,
        transport: httpx.BaseTransport | None = None,
        port_probe: PortProbe | None = None,
    ) -> None:
        self._backend_base_url = backend_base_url.rstrip("/")
        self._frontend_url = frontend_url
        self._timeout_s = timeout_s
        self._client = httpx.Client(timeout=timeout_s, transport=transport, follow_redirects=False)
        self._port_probe = port_probe or _default_port_probe

    def close(self) -> None:
        self._client.close()

    def probe_port(self, host: str, port: int) -> HealthResult:
        try:
            is_open = bool(self._port_probe(host, port, self._timeout_s))
        except OSError:
            is_open = False
        return HealthResult(
            checked_at=datetime.now(UTC),
            reachable=is_open,
            port_open=is_open,
            summary="端口可连接" if is_open else "端口未监听",
            error_code=None if is_open else "PORT_CLOSED",
        )

    def probe_backend(self) -> HealthResult:
        try:
            live_response = self._client.get(f"{self._backend_base_url}/health/live")
        except httpx.TimeoutException:
            return self._backend_failure("TIMEOUT", "后端健康检查超时")
        except httpx.HTTPError:
            return self._backend_failure("CONNECTION_ERROR", "后端健康检查无法连接")

        live = _matches_json_status(live_response, "ok")
        if not live:
            return HealthResult(
                checked_at=datetime.now(UTC),
                reachable=True,
                live=False,
                ready=False,
                status_code=live_response.status_code,
                error_code=_response_error_code(live_response) or "LIVE_CHECK_FAILED",
                summary="后端已响应，但存活检查未通过",
            )

        try:
            ready_response = self._client.get(f"{self._backend_base_url}/health/ready")
        except httpx.TimeoutException:
            return HealthResult(
                checked_at=datetime.now(UTC),
                reachable=True,
                live=True,
                ready=False,
                error_code="TIMEOUT",
                summary="后端进程存活，但就绪检查超时",
            )
        except httpx.HTTPError:
            return HealthResult(
                checked_at=datetime.now(UTC),
                reachable=True,
                live=True,
                ready=False,
                error_code="CONNECTION_ERROR",
                summary="后端进程存活，但就绪检查无法连接",
            )

        ready = _matches_json_status(ready_response, "ready")
        return HealthResult(
            checked_at=datetime.now(UTC),
            reachable=True,
            live=True,
            ready=ready,
            status_code=ready_response.status_code,
            error_code=None if ready else (_response_error_code(ready_response) or "NOT_READY"),
            summary="后端已就绪" if ready else "后端存活，但数据库或迁移尚未就绪",
        )

    def probe_frontend(self) -> HealthResult:
        try:
            response = self._client.get(self._frontend_url)
        except httpx.TimeoutException:
            return HealthResult(
                checked_at=datetime.now(UTC),
                reachable=False,
                ready=False,
                error_code="TIMEOUT",
                summary="前端健康检查超时",
            )
        except httpx.HTTPError:
            return HealthResult(
                checked_at=datetime.now(UTC),
                reachable=False,
                ready=False,
                error_code="CONNECTION_ERROR",
                summary="前端健康检查无法连接",
            )
        ready = response.status_code == 200 and "<title>OPC Admin</title>" in response.text
        return HealthResult(
            checked_at=datetime.now(UTC),
            reachable=True,
            ready=ready,
            status_code=response.status_code,
            error_code=None if ready else "WRONG_FRONTEND",
            summary="后台管理前端已就绪" if ready else "端口有响应，但不是预期的 OPC Admin 页面",
        )

    @staticmethod
    def _backend_failure(code: str, summary: str) -> HealthResult:
        return HealthResult(
            checked_at=datetime.now(UTC),
            reachable=False,
            live=False,
            ready=False,
            error_code=code,
            summary=summary,
        )


def _default_port_probe(host: str, port: int, timeout: float) -> bool:
    try:
        with socket.create_connection((host, port), timeout=timeout):
            return True
    except OSError:
        return False


def _matches_json_status(response: httpx.Response, expected: str) -> bool:
    if response.status_code != 200:
        return False
    try:
        payload = response.json()
    except ValueError:
        return False
    return isinstance(payload, dict) and payload.get("status") == expected


def _response_error_code(response: httpx.Response) -> str | None:
    try:
        payload = response.json()
    except ValueError:
        return None
    if not isinstance(payload, dict) or not isinstance(payload.get("error"), dict):
        return None
    code = payload["error"].get("code")
    return code if isinstance(code, str) and code else None

