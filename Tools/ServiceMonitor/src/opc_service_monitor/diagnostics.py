from __future__ import annotations

import logging
import logging.handlers
import time
from pathlib import Path

from opc_service_monitor.log_pipeline import redact_log_text


class _RedactingFilter(logging.Filter):
    def filter(self, record: logging.LogRecord) -> bool:
        record.msg = redact_log_text(record.getMessage())
        record.args = ()
        return True


class _RedactingFormatter(logging.Formatter):
    converter = time.gmtime

    def formatException(self, exc_info) -> str:  # noqa: N802 - logging API name
        return redact_log_text(super().formatException(exc_info))


def configure_diagnostics(
    path: Path,
    *,
    max_bytes: int = 1_048_576,
    backup_count: int = 3,
) -> logging.Logger:
    resolved = Path(path).expanduser().resolve()
    resolved.parent.mkdir(parents=True, exist_ok=True)
    logger = logging.getLogger("opc_service_monitor")
    logger.setLevel(logging.INFO)
    logger.propagate = False
    for handler in list(logger.handlers):
        logger.removeHandler(handler)
        handler.close()
    handler = logging.handlers.RotatingFileHandler(
        resolved,
        maxBytes=max_bytes,
        backupCount=backup_count,
        encoding="utf-8",
    )
    handler.addFilter(_RedactingFilter())
    handler.setFormatter(_RedactingFormatter("%(asctime)sZ %(levelname)s %(name)s %(message)s"))
    logger.addHandler(handler)
    return logger

