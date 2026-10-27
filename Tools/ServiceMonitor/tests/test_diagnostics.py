from __future__ import annotations

import logging
from pathlib import Path

from opc_service_monitor.diagnostics import configure_diagnostics


def test_diagnostics_rotate_and_redact_before_disk(tmp_path: Path) -> None:
    path = tmp_path / "monitor.log"
    logger = configure_diagnostics(path, max_bytes=300, backup_count=2)

    for number in range(30):
        logger.error(
            "line=%s --api_key diagnostic-secret X-API-Key: header-secret Bearer token-value",
            number,
        )
    for handler in logger.handlers:
        handler.flush()

    files = list(tmp_path.glob("monitor.log*"))
    assert 1 <= len(files) <= 3
    content = "\n".join(file.read_text(encoding="utf-8") for file in files)
    assert "diagnostic-secret" not in content
    assert "header-secret" not in content
    assert "token-value" not in content
    assert "[REDACTED]" in content
    assert logger.propagate is False
    assert all(isinstance(handler, logging.Handler) for handler in logger.handlers)

