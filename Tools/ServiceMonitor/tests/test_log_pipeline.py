from __future__ import annotations

from datetime import UTC, datetime

import pytest

from opc_service_monitor.log_pipeline import (
    MAX_LOG_LINE_CHARS,
    IncrementalLineDecoder,
    decode_log_bytes,
    make_log_entry,
    redact_log_text,
)
from opc_service_monitor.models import LogLevel, LogSource


def test_decoder_preserves_utf8_character_split_across_chunks() -> None:
    decoder = IncrementalLineDecoder()
    encoded = "服务已启动\n".encode()

    assert decoder.feed(encoded[:2]) == []
    assert decoder.feed(encoded[2:5]) == []
    assert decoder.feed(encoded[5:]) == ["服务已启动"]
    assert decoder.flush() == []


def test_decoder_accepts_crlf_lf_and_flushes_unterminated_line() -> None:
    decoder = IncrementalLineDecoder()

    assert decoder.feed(b"first\r") == []
    assert decoder.feed(b"\nsecond\nthird") == ["first", "second"]
    assert decoder.flush() == ["third"]
    assert decoder.flush() == []


def test_decoder_replaces_invalid_utf8_without_crashing() -> None:
    decoder = IncrementalLineDecoder()

    assert decoder.feed(b"bad:\xff\n") == ["bad:\ufffd"]


def test_decoder_bounds_unterminated_line_across_many_chunks() -> None:
    decoder = IncrementalLineDecoder()

    for _ in range(40):
        assert decoder.feed(b"x" * 4096) == []
    lines = decoder.flush()

    assert len(lines) == 1
    assert len(lines[0]) == MAX_LOG_LINE_CHARS
    assert lines[0].endswith("…[已截断]")
    entry = make_log_entry(source=LogSource.BACKEND, stream="stdout", text=lines[0])
    assert entry.truncated is True


@pytest.mark.parametrize("encoding", ["utf-8", "gb18030", "cp936"])
def test_decoder_preserves_chinese_bytes_at_every_split(encoding: str) -> None:
    text = "日志：数据库系统已就绪，服务启动失败。"
    raw = (text + "\r\n").encode(encoding)
    for boundary in range(len(raw) + 1):
        decoder = IncrementalLineDecoder(fallback_encodings=("gb18030",))
        lines = decoder.feed(raw[:boundary]) + decoder.feed(raw[boundary:]) + decoder.flush()
        assert lines == [text]


def test_decoder_accepts_mixed_utf8_and_native_lines_in_one_pipe() -> None:
    decoder = IncrementalLineDecoder(fallback_encodings=("gb18030",))
    raw = "服务 UTF-8 🙂\n".encode() + "日志：数据库系统已关闭\n".encode("cp936")
    assert decoder.feed(raw) == ["服务 UTF-8 🙂", "日志：数据库系统已关闭"]


def test_decoder_handles_native_unterminated_line_and_utf8_bom() -> None:
    decoder = IncrementalLineDecoder(fallback_encodings=("gb18030",))
    assert decoder.feed("后端启动失败。".encode("cp936")) == []
    assert decoder.flush() == ["后端启动失败。"]
    assert decoder.feed(b"\xef\xbb\xbf" + "日志正常\n".encode()) == ["日志正常"]
    assert decode_log_bytes(b"bad:\xff", fallback_encodings=("gb18030",)) == "bad:\ufffd"


def test_native_decoding_still_redacts_before_persistence() -> None:
    decoder = IncrementalLineDecoder(fallback_encodings=("gb18030",))
    line = decoder.feed("日志：password=encoding-secret 数据库\n".encode("cp936"))[0]
    entry = make_log_entry(source=LogSource.POSTGRES, stream="file", text=line)
    assert entry.message == "日志：password=[REDACTED] 数据库"


def test_truncated_utf8_prefix_does_not_fall_back_because_final_character_is_split() -> None:
    text = "x" + "中文🙂" * MAX_LOG_LINE_CHARS
    decoder = IncrementalLineDecoder(fallback_encodings=("gb18030",))
    line = decoder.feed((text + "\n").encode())[0]
    assert line == text[: MAX_LOG_LINE_CHARS - len("…[已截断]")] + "…[已截断]"


@pytest.mark.parametrize(
    ("text", "forbidden"),
    [
        ("Authorization: Bearer abc.def.ghi", "abc.def.ghi"),
        ("Authorization: Basic dXNlcjpwYXNz", "dXNlcjpwYXNz"),
        ("Authorization=opaque-secret", "opaque-secret"),
        ('Authorization: "quoted-secret"', "quoted-secret"),
        ("password=hunter2 next=yes", "hunter2"),
        ('{"secret": "private-value"}', "private-value"),
        ("token='session-token'", "session-token"),
        ("command --password swordfish --host localhost", "swordfish"),
        ("command --token=cli-token", "cli-token"),
        ("postgresql://opc:db-pass@127.0.0.1:55440/opc", "db-pass"),
        ("https://example.test/?access_token=query-token&ok=1", "query-token"),
    ],
)
def test_redacts_common_secret_forms(text: str, forbidden: str) -> None:
    redacted = redact_log_text(text)

    assert forbidden not in redacted
    assert "[REDACTED]" in redacted


@pytest.mark.parametrize(
    ("text", "expected"),
    [
        ("command --api-key=hyphen-secret --verbose", "command --api-key=[REDACTED] --verbose"),
        ("command --api_key=underscore-secret --verbose", "command --api_key=[REDACTED] --verbose"),
        ("command --API-Key whitespace-secret --verbose", "command --API-Key [REDACTED] --verbose"),
        ("command --API_KEY 'quoted secret' --verbose", "command --API_KEY [REDACTED] --verbose"),
    ],
)
def test_redacts_api_key_cli_options_with_equals_or_whitespace(text: str, expected: str) -> None:
    assert redact_log_text(text) == expected


@pytest.mark.parametrize(
    ("text", "expected"),
    [
        ("api-key=config-secret next=yes", "api-key=[REDACTED] next=yes"),
        ('api_key = "underscore secret"', "api_key = [REDACTED]"),
        ("X-API-Key: header-secret", "X-API-Key: [REDACTED]"),
        ("x_api_key = case-insensitive-secret", "x_api_key = [REDACTED]"),
    ],
)
def test_redacts_api_key_assignments_and_headers_case_insensitively(text: str, expected: str) -> None:
    assert redact_log_text(text) == expected


@pytest.mark.parametrize(
    ("text", "expected"),
    [
        ("OPENAI_API_KEY=openai-secret", "OPENAI_API_KEY=[REDACTED]"),
        ('"DATABASE_PASSWORD": "database secret"', '"DATABASE_PASSWORD": [REDACTED]'),
        ("VITE_API_TOKEN: vite-secret", "VITE_API_TOKEN: [REDACTED]"),
        ("service.auth.refresh_token=refresh-secret", "service.auth.refresh_token=[REDACTED]"),
        ("command --openai-api-key=cli-secret --verbose", "command --openai-api-key=[REDACTED] --verbose"),
        ("command --database_password db-secret --verbose", "command --database_password [REDACTED] --verbose"),
        ("command --vite-api-token 'vite cli secret'", "command --vite-api-token [REDACTED]"),
    ],
)
def test_redacts_prefixed_keys_that_end_in_a_sensitive_suffix(text: str, expected: str) -> None:
    assert redact_log_text(text) == expected


@pytest.mark.parametrize(
    "text",
    [
        "API key authentication is enabled",
        "the variable is named api_key and the header is X-API-Key",
        "api-keyboard=enabled",
        "ordinary prose mentions --api-key.",
        "OPENAI_API_KEY",
        "DATABASE_PASSWORD is configured outside the monitor",
        "NOTAPITOKEN=ordinary-value",
        "--vite-api-tokenizer=enabled",
    ],
)
def test_api_key_words_without_a_secret_delimiter_are_not_redacted(text: str) -> None:
    assert redact_log_text(text) == text


def test_make_entry_removes_ansi_before_every_sink() -> None:
    entry = make_log_entry(
        source=LogSource.BACKEND,
        stream="stdout",
        text="\x1b[31mERROR\x1b[0m password=do-not-store",
    )

    assert "\x1b" not in entry.message
    assert "do-not-store" not in entry.message
    assert entry.level is LogLevel.ERROR


@pytest.mark.parametrize(
    ("stream", "text", "level"),
    [
        ("stdout", "DEBUG database probe", LogLevel.DEBUG),
        ("stdout", "service ready", LogLevel.INFO),
        ("stdout", "WARNING retry", LogLevel.WARNING),
        ("stderr", "plain diagnostic", LogLevel.ERROR),
        ("stdout", "FATAL startup failed", LogLevel.CRITICAL),
        ("stdout", "Traceback (most recent call last)", LogLevel.ERROR),
    ],
)
def test_level_detection_uses_content_then_stream(stream: str, text: str, level: LogLevel) -> None:
    entry = make_log_entry(source=LogSource.FRONTEND, stream=stream, text=text)

    assert entry.level is level


def test_make_entry_normalizes_timestamp_to_utc() -> None:
    naive = datetime(2026, 10, 22, 12, 30, 0)
    entry = make_log_entry(
        source=LogSource.POSTGRES,
        stream="file",
        text="ready",
        occurred_at=naive,
    )

    assert entry.occurred_at.tzinfo is UTC
    assert entry.occurred_at == naive.replace(tzinfo=UTC)


def test_make_entry_truncates_one_line_to_fixed_limit_with_marker() -> None:
    entry = make_log_entry(
        source=LogSource.BACKEND,
        stream="stdout",
        text="x" * (MAX_LOG_LINE_CHARS + 100),
    )

    assert len(entry.message) == MAX_LOG_LINE_CHARS
    assert entry.message.endswith("…[已截断]")
    assert entry.truncated is True


def test_make_entry_never_returns_unredacted_text() -> None:
    entry = make_log_entry(
        source=LogSource.MONITOR,
        stream="internal",
        text="launch --password top-secret with Bearer access-value",
    )

    assert "top-secret" not in entry.message
    assert "access-value" not in entry.message
    assert entry.message.count("[REDACTED]") == 2

