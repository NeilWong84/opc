from __future__ import annotations

import codecs
import locale
import os
import re
from datetime import UTC, datetime

from opc_service_monitor.models import LogEntry, LogLevel, LogSource


MAX_LOG_LINE_CHARS = 65_536
_TRUNCATION_MARKER = "…[已截断]"
_ANSI_ESCAPE = re.compile(r"\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])")
_POSTGRES_URL = re.compile(r"(?i)\b(postgresql(?:\+[a-z0-9_]+)?://)([^@\s/]+)@")
_AUTHORIZATION = re.compile(
    r"(?ix)\b(authorization\s*[:=]\s*)"
    r"(?:\"[^\"]*\"|'[^']*'|(?:basic|bearer)\s+[^\s,;]+|[^\s,;]+)"
)
_BEARER = re.compile(r"(?i)\b(Bearer\s+)[A-Za-z0-9._~+/=-]+")
_SECRET_VALUE = r'(?:"[^"]*"|\'[^\']*\'|[^\s,;&]+)'
_SECRET_SUFFIX = r"(?:password|passwd|pwd|secret|token|access[-_]token|refresh[-_]token|api[-_]key)"
_SECRET_KEY = rf"(?:[a-z0-9]+[-_.])*{_SECRET_SUFFIX}"
_CLI_SECRET = re.compile(
    rf"(?ix)(?<![a-z0-9_.-])(--{_SECRET_KEY}"
    rf"(?:\s*=\s*|\s+)){_SECRET_VALUE}"
)
_ASSIGNED_SECRET = re.compile(
    rf"(?ix)(?<![a-z0-9_.-])([\"']?{_SECRET_KEY}[\"']?\s*[:=]\s*){_SECRET_VALUE}"
)


def windows_log_encodings() -> tuple[str, ...]:
    """Windows tools can emit the native ANSI/OEM code page even into a pipe."""
    if os.name != "nt":
        return ()
    candidates = [locale.getencoding()]
    try:
        import ctypes
        kernel = ctypes.WinDLL("kernel32", use_last_error=True)
        candidates.extend(f"cp{page}" for page in (kernel.GetACP(), kernel.GetOEMCP()) if page)
    except (AttributeError, OSError):
        pass
    result: list[str] = []
    for name in candidates:
        try:
            canonical = codecs.lookup(name).name
        except LookupError:
            continue
        if canonical in {"gbk", "gb2312"}:
            canonical = "gb18030"
        if canonical not in {"utf-8", "utf-8-sig"} and canonical not in result:
            result.append(canonical)
    return tuple(result)


def decode_log_bytes(data: bytes, *, fallback_encodings: tuple[str, ...] = (), final: bool = True) -> str:
    """Try lossless UTF-8 first, then explicitly allowed native code pages."""
    for encoding in ("utf-8-sig", *fallback_encodings):
        try:
            return codecs.getincrementaldecoder(encoding)(errors="strict").decode(data, final=final)
        except UnicodeDecodeError:
            continue
    return data.decode("utf-8-sig", errors="replace")


class IncrementalLineDecoder:
    """Buffer bounded raw lines before decoding, preserving split multibyte data."""

    def __init__(self, *, fallback_encodings: tuple[str, ...] = ()) -> None:
        self._fallback_encodings = fallback_encodings
        self._buffer = bytearray()
        self._line_truncated = False

    def feed(self, chunk: bytes) -> list[str]:
        if not chunk:
            return []
        return self._consume(chunk)

    def flush(self) -> list[str]:
        lines: list[str] = []
        if self._buffer or self._line_truncated:
            lines.append(self._finish_line())
        return lines

    def _consume(self, chunk: bytes) -> list[str]:
        lines: list[str] = []
        parts = chunk.split(b"\n")
        for part in parts[:-1]:
            self._append_fragment(part)
            lines.append(self._finish_line())
        self._append_fragment(parts[-1])
        return lines

    def _append_fragment(self, fragment: bytes) -> None:
        if not fragment or self._line_truncated:
            return
        capacity = MAX_LOG_LINE_CHARS * 4 - len(self._buffer)
        if len(fragment) <= capacity:
            self._buffer.extend(fragment)
            return
        self._buffer.extend(fragment[: max(0, capacity)])
        self._line_truncated = True

    def _finish_line(self) -> str:
        line = decode_log_bytes(
            bytes(self._buffer), fallback_encodings=self._fallback_encodings, final=not self._line_truncated,
        ).removesuffix("\r")
        if self._line_truncated or len(line) > MAX_LOG_LINE_CHARS:
            line = line[: MAX_LOG_LINE_CHARS - len(_TRUNCATION_MARKER)] + _TRUNCATION_MARKER
        self._buffer.clear()
        self._line_truncated = False
        return line


def redact_log_text(text: str) -> str:
    """Remove common credentials before text can reach any UI or persistence sink."""

    redacted = _POSTGRES_URL.sub(r"\1[REDACTED]@", text)
    redacted = _AUTHORIZATION.sub(r"\1[REDACTED]", redacted)
    redacted = _BEARER.sub(r"\1[REDACTED]", redacted)
    redacted = _CLI_SECRET.sub(r"\1[REDACTED]", redacted)
    return _ASSIGNED_SECRET.sub(r"\1[REDACTED]", redacted)


def make_log_entry(
    *,
    source: LogSource,
    stream: str,
    text: str,
    occurred_at: datetime | None = None,
    pid: int | None = None,
) -> LogEntry:
    cleaned = _ANSI_ESCAPE.sub("", text)
    safe = redact_log_text(cleaned)
    level = _detect_level(safe, stream)
    truncated = safe.endswith(_TRUNCATION_MARKER) or len(safe) > MAX_LOG_LINE_CHARS
    if len(safe) > MAX_LOG_LINE_CHARS:
        safe = safe[: MAX_LOG_LINE_CHARS - len(_TRUNCATION_MARKER)] + _TRUNCATION_MARKER
    timestamp = occurred_at or datetime.now(UTC)
    if timestamp.tzinfo is None:
        timestamp = timestamp.replace(tzinfo=UTC)
    else:
        timestamp = timestamp.astimezone(UTC)
    return LogEntry(
        occurred_at=timestamp,
        source=source,
        level=level,
        stream=stream,
        message=safe,
        truncated=truncated,
        pid=pid,
    )


def _detect_level(text: str, stream: str) -> LogLevel:
    normalized = text.upper()
    if re.search(r"\b(?:CRITICAL|FATAL|PANIC)\b", normalized):
        return LogLevel.CRITICAL
    if "TRACEBACK" in normalized or re.search(r"\b(?:ERROR|EXCEPTION)\b", normalized):
        return LogLevel.ERROR
    if re.search(r"\b(?:WARNING|WARN)\b", normalized):
        return LogLevel.WARNING
    if re.search(r"\bDEBUG\b", normalized):
        return LogLevel.DEBUG
    if stream.casefold() == "stderr":
        return LogLevel.ERROR
    return LogLevel.INFO

