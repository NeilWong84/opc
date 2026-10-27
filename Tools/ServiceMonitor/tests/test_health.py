from __future__ import annotations

import httpx

from opc_service_monitor.health import HealthProbe


def test_backend_uses_exact_live_and_ready_contracts() -> None:
    requested: list[str] = []

    def handler(request: httpx.Request) -> httpx.Response:
        requested.append(str(request.url))
        if request.url.path == "/health/live":
            return httpx.Response(200, json={"status": "ok", "service": "opc-backend"})
        return httpx.Response(200, json={"status": "ready", "migrations": 6})

    probe = HealthProbe(transport=httpx.MockTransport(handler))
    try:
        result = probe.probe_backend()
    finally:
        probe.close()

    assert requested == [
        "http://127.0.0.1:8001/health/live",
        "http://127.0.0.1:8001/health/ready",
    ]
    assert result.reachable is True
    assert result.live is True
    assert result.ready is True
    assert result.port_open is None


def test_backend_keeps_live_and_not_ready_evidence_distinct() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.path.endswith("/live"):
            return httpx.Response(200, json={"status": "ok", "service": "opc-backend"})
        return httpx.Response(
            503,
            json={
                "error": {"code": "DATABASE_UNAVAILABLE", "message": "secret-value"},
                "request_id": "request-id",
            },
        )

    probe = HealthProbe(transport=httpx.MockTransport(handler))
    try:
        result = probe.probe_backend()
    finally:
        probe.close()

    assert result.reachable is True
    assert result.live is True
    assert result.ready is False
    assert result.error_code == "DATABASE_UNAVAILABLE"
    assert "secret-value" not in result.summary


def test_backend_timeout_does_not_claim_process_or_readiness() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        raise httpx.ReadTimeout("contains-sensitive-response", request=request)

    probe = HealthProbe(transport=httpx.MockTransport(handler), timeout_s=3.0)
    try:
        result = probe.probe_backend()
    finally:
        probe.close()

    assert result.reachable is False
    assert result.live is False
    assert result.ready is False
    assert result.error_code == "TIMEOUT"
    assert "sensitive" not in result.summary


def test_frontend_requires_exact_opc_admin_title() -> None:
    responses = iter(
        [
            httpx.Response(200, text="<html><title>Something Else</title></html>"),
            httpx.Response(200, text="<html><head><title>OPC Admin</title></head></html>"),
        ]
    )
    requested: list[str] = []

    def handler(request: httpx.Request) -> httpx.Response:
        requested.append(str(request.url))
        return next(responses)

    probe = HealthProbe(transport=httpx.MockTransport(handler))
    try:
        wrong = probe.probe_frontend()
        ready = probe.probe_frontend()
    finally:
        probe.close()

    assert requested == ["http://127.0.0.1:5180/", "http://127.0.0.1:5180/"]
    assert wrong.reachable is True and wrong.ready is False
    assert wrong.error_code == "WRONG_FRONTEND"
    assert ready.ready is True


def test_port_probe_is_independent_from_http_evidence() -> None:
    attempts: list[tuple[str, int, float]] = []

    def port_probe(host: str, port: int, timeout: float) -> bool:
        attempts.append((host, port, timeout))
        return True

    probe = HealthProbe(port_probe=port_probe, timeout_s=3.0)
    try:
        result = probe.probe_port("127.0.0.1", 55440)
    finally:
        probe.close()

    assert attempts == [("127.0.0.1", 55440, 3.0)]
    assert result.port_open is True
    assert result.live is None
    assert result.ready is None

