from __future__ import annotations

import os
import queue
import re
import sqlite3
import threading
import time
from contextlib import closing
from dataclasses import dataclass, replace
from datetime import UTC, datetime, timedelta
from enum import StrEnum
from pathlib import Path
from typing import Any

import regex as safe_regex

from opc_service_monitor.log_pipeline import make_log_entry
from opc_service_monitor.models import LogEntry, LogLevel, LogSource


MAX_REGEX_QUANTIFIER_BOUND = 10_000


class LogMatchMode(StrEnum):
    PLAIN = "plain"
    FTS = "fts"
    REGEX = "regex"


@dataclass(frozen=True, slots=True)
class LogQuery:
    keyword: str = ""
    sources: tuple[LogSource, ...] = ()
    levels: tuple[LogLevel, ...] = ()
    started_at: datetime | None = None
    ended_at: datetime | None = None
    case_sensitive: bool = False
    match_mode: LogMatchMode = LogMatchMode.PLAIN
    limit: int = 5_000
    scan_limit: int = 100_000
    timeout_seconds: float = 5.0
    result_text_limit: int = 8 * 1024 * 1024

    def __post_init__(self) -> None:
        if not 1 <= self.limit <= 50_000:
            raise ValueError("日志查询数量必须在 1 到 50000 之间")
        if not 1 <= self.scan_limit <= 500_000:
            raise ValueError("日志扫描数量必须在 1 到 500000 之间")
        if not 0.05 <= self.timeout_seconds <= 30.0:
            raise ValueError("日志查询超时必须在 0.05 到 30 秒之间")
        if not 1 <= self.result_text_limit <= 64 * 1024 * 1024:
            raise ValueError("日志查询结果文本上限必须在 1 到 67108864 字符之间")


@dataclass(frozen=True, slots=True)
class LogSearchResult:
    entries: tuple[LogEntry, ...]
    validation_error: str | None = None
    scanned_rows: int = 0
    scan_limited: bool = False
    cancelled: bool = False
    timed_out: bool = False
    result_limited: bool = False


@dataclass(frozen=True, slots=True)
class SafeLogRegex:
    """Compiled third-party regex with a mandatory per-match time bound."""

    _compiled: Any

    def matches(self, text: str, *, timeout_seconds: float) -> bool:
        return self._compiled.search(text, timeout=timeout_seconds) is not None


def compile_log_regex(pattern: str, *, case_sensitive: bool) -> tuple[SafeLogRegex | None, str | None]:
    """Validate and compile a log regex for both persisted and live matching."""

    unsafe_reason = _unsafe_regex_reason(pattern)
    if unsafe_reason is not None:
        return None, f"正则表达式过于复杂: {unsafe_reason}"
    try:
        compiled = safe_regex.compile(pattern, 0 if case_sensitive else safe_regex.IGNORECASE)
    except safe_regex.error as exc:
        return None, f"正则表达式无效: {exc}"
    return SafeLogRegex(compiled), None


@dataclass(frozen=True, slots=True)
class FileCursor:
    source_path: Path
    file_identity: str
    offset: int
    size: int
    boundary_digest: str = ""
    boundary_length: int = 0
    discard_until_newline: bool = False


@dataclass(slots=True)
class _WriteRequest:
    action: str
    arguments: tuple[Any, ...]
    completed: threading.Event
    result: Any = None
    error: BaseException | None = None


class LogStore:
    """SQLite log store with one dedicated writer and independent readers."""

    def __init__(self, path: Path) -> None:
        self.path = path
        self._requests: queue.Queue[_WriteRequest | None] = queue.Queue()
        self._closed = False
        self._close_lock = threading.Lock()
        self._writer = threading.Thread(target=self._writer_loop, name="opc-log-writer", daemon=True)
        self._writer.start()

    @classmethod
    def open(cls, path: Path) -> LogStore:
        resolved = Path(path).expanduser().resolve()
        resolved.parent.mkdir(parents=True, exist_ok=True)
        cls.recover_if_corrupt(resolved)
        cls._initialize_database(resolved)
        return cls(resolved)

    @staticmethod
    def recover_if_corrupt(path: Path) -> Path | None:
        path = Path(path)
        if not path.exists():
            return None
        try:
            with closing(sqlite3.connect(path)) as connection:
                result = connection.execute("PRAGMA quick_check").fetchone()
                if result and result[0] == "ok":
                    return None
                raise sqlite3.DatabaseError("quick_check failed")
        except sqlite3.DatabaseError:
            stamp = datetime.now(UTC).strftime("%Y%m%dT%H%M%S%fZ")
            quarantine = path.with_name(f"{path.name}.corrupt-{stamp}")
            counter = 1
            while quarantine.exists():
                quarantine = path.with_name(f"{path.name}.corrupt-{stamp}-{counter}")
                counter += 1
            os.replace(path, quarantine)
            for suffix in ("-wal", "-shm"):
                sidecar = Path(f"{path}{suffix}")
                if sidecar.exists():
                    os.replace(sidecar, Path(f"{quarantine}{suffix}"))
            return quarantine

    @staticmethod
    def _initialize_database(path: Path) -> None:
        with closing(sqlite3.connect(path, timeout=5)) as connection:
            connection.execute("PRAGMA journal_mode=WAL")
            connection.execute("PRAGMA synchronous=NORMAL")
            connection.execute("PRAGMA busy_timeout=5000")
            connection.executescript(
                """
                CREATE TABLE IF NOT EXISTS logs (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    occurred_at TEXT NOT NULL,
                    source TEXT NOT NULL,
                    level TEXT NOT NULL,
                    stream TEXT NOT NULL,
                    message TEXT NOT NULL,
                    truncated INTEGER NOT NULL DEFAULT 0,
                    pid INTEGER
                );
                CREATE INDEX IF NOT EXISTS idx_logs_occurred_at ON logs(occurred_at DESC);
                CREATE INDEX IF NOT EXISTS idx_logs_source_level ON logs(source, level);
                CREATE VIRTUAL TABLE IF NOT EXISTS logs_fts USING fts5(
                    message,
                    content='logs',
                    content_rowid='id'
                );
                CREATE TRIGGER IF NOT EXISTS logs_ai AFTER INSERT ON logs BEGIN
                    INSERT INTO logs_fts(rowid, message) VALUES (new.id, new.message);
                END;
                CREATE TRIGGER IF NOT EXISTS logs_ad AFTER DELETE ON logs BEGIN
                    INSERT INTO logs_fts(logs_fts, rowid, message) VALUES ('delete', old.id, old.message);
                END;
                CREATE TRIGGER IF NOT EXISTS logs_au AFTER UPDATE ON logs BEGIN
                    INSERT INTO logs_fts(logs_fts, rowid, message) VALUES ('delete', old.id, old.message);
                    INSERT INTO logs_fts(rowid, message) VALUES (new.id, new.message);
                END;
                CREATE TABLE IF NOT EXISTS source_cursors (
                    source_path TEXT PRIMARY KEY,
                    file_identity TEXT NOT NULL,
                    offset INTEGER NOT NULL,
                    size INTEGER NOT NULL,
                    boundary_digest TEXT NOT NULL DEFAULT '',
                    boundary_length INTEGER NOT NULL DEFAULT 0,
                    discard_until_newline INTEGER NOT NULL DEFAULT 0,
                    updated_at TEXT NOT NULL
                );
                """
            )
            columns = {row[1] for row in connection.execute("PRAGMA table_info(source_cursors)")}
            if "boundary_digest" not in columns:
                connection.execute("ALTER TABLE source_cursors ADD COLUMN boundary_digest TEXT NOT NULL DEFAULT ''")
            if "boundary_length" not in columns:
                connection.execute("ALTER TABLE source_cursors ADD COLUMN boundary_length INTEGER NOT NULL DEFAULT 0")
            if "discard_until_newline" not in columns:
                connection.execute(
                    "ALTER TABLE source_cursors ADD COLUMN discard_until_newline INTEGER NOT NULL DEFAULT 0"
                )

    def append(self, entries: list[LogEntry] | tuple[LogEntry, ...]) -> int:
        safe_entries = tuple(self._sanitize_entry(entry) for entry in entries)
        if not safe_entries:
            return 0
        return int(self._submit("append", safe_entries))

    def repair_file_messages(self, source: LogSource, replacements: dict[str, LogEntry]) -> int:
        """Replace proven legacy decode errors without replaying file records."""

        safe_replacements: list[tuple[str, LogEntry]] = []
        for previous, replacement in replacements.items():
            previous = make_log_entry(source=source, stream="file", text=previous).message
            safe = self._sanitize_entry(replacement)
            if (
                "\ufffd" not in previous
                or "\ufffd" in safe.message
                or previous == safe.message
                or safe.source is not source
                or safe.stream != "file"
            ):
                continue
            safe_replacements.append((previous, safe))
        if not safe_replacements:
            return 0
        return int(self._submit("repair_file_messages", source, tuple(safe_replacements)))

    def search(self, query: LogQuery, *, cancel_event: threading.Event | None = None) -> LogSearchResult:
        self._ensure_open()
        if cancel_event is not None and cancel_event.is_set():
            return LogSearchResult((), cancelled=True)
        regex: SafeLogRegex | None = None
        if query.keyword and query.match_mode is LogMatchMode.REGEX:
            regex, validation_error = compile_log_regex(query.keyword, case_sensitive=query.case_sensitive)
            if validation_error is not None:
                return LogSearchResult((), validation_error)

        where: list[str] = []
        parameters: list[Any] = []
        join = ""
        if query.sources:
            where.append(f"l.source IN ({','.join('?' for _ in query.sources)})")
            parameters.extend(source.value for source in query.sources)
        if query.levels:
            where.append(f"l.level IN ({','.join('?' for _ in query.levels)})")
            parameters.extend(level.value for level in query.levels)
        if query.started_at is not None:
            where.append("l.occurred_at >= ?")
            parameters.append(_as_utc(query.started_at).isoformat())
        if query.ended_at is not None:
            where.append("l.occurred_at <= ?")
            parameters.append(_as_utc(query.ended_at).isoformat())
        if query.keyword and query.match_mode is LogMatchMode.FTS:
            join = " JOIN logs_fts ON logs_fts.rowid = l.id"
            where.append("logs_fts MATCH ?")
            parameters.append(_fts_phrase(query.keyword))

        predicate = f" WHERE {' AND '.join(where)}" if where else ""
        sql = (
            "SELECT l.id, l.occurred_at, l.source, l.level, l.stream, l.message, l.truncated, l.pid "
            f"FROM logs AS l{join}{predicate} ORDER BY l.occurred_at DESC, l.id DESC"
        )
        sql_limited = not query.keyword or query.match_mode is LogMatchMode.FTS
        if sql_limited:
            sql += " LIMIT ?"
            parameters.append(query.limit)
        else:
            sql += " LIMIT ?"
            parameters.append(query.scan_limit + 1)

        entries: list[LogEntry] = []
        result_text_size = 0
        scanned_rows = 0
        deadline = time.monotonic() + query.timeout_seconds
        keyword = query.keyword if query.case_sensitive else query.keyword.casefold()

        def interrupted() -> bool:
            return (cancel_event is not None and cancel_event.is_set()) or time.monotonic() >= deadline

        try:
            with closing(self._reader()) as connection:
                connection.set_progress_handler(lambda: int(interrupted()), 1_000)
                cursor = connection.execute(sql, parameters)
                while rows := cursor.fetchmany(512):
                    for row in rows:
                        if interrupted():
                            return LogSearchResult(
                                tuple(entries),
                                scanned_rows=scanned_rows,
                                cancelled=cancel_event is not None and cancel_event.is_set(),
                                timed_out=time.monotonic() >= deadline,
                            )
                        if not sql_limited and scanned_rows >= query.scan_limit:
                            return LogSearchResult(tuple(entries), scanned_rows=scanned_rows, scan_limited=True)
                        scanned_rows += 1
                        entry = _row_to_entry(row)
                        if query.keyword and query.match_mode is LogMatchMode.PLAIN:
                            message = entry.message if query.case_sensitive else entry.message.casefold()
                            if keyword not in message:
                                continue
                        elif regex is not None:
                            remaining = deadline - time.monotonic()
                            if remaining <= 0:
                                return LogSearchResult(
                                    tuple(entries),
                                    scanned_rows=scanned_rows,
                                    timed_out=True,
                                )
                            try:
                                matched = regex.matches(entry.message, timeout_seconds=remaining)
                            except TimeoutError:
                                return LogSearchResult(
                                    tuple(entries),
                                    scanned_rows=scanned_rows,
                                    timed_out=True,
                                )
                            if not matched:
                                continue
                        if result_text_size + len(entry.message) > query.result_text_limit:
                            return LogSearchResult(
                                tuple(entries),
                                scanned_rows=scanned_rows,
                                result_limited=True,
                            )
                        entries.append(entry)
                        result_text_size += len(entry.message)
                        if len(entries) >= query.limit:
                            return LogSearchResult(tuple(entries), scanned_rows=scanned_rows)
        except sqlite3.OperationalError as exc:
            if interrupted() and "interrupted" in str(exc).casefold():
                return LogSearchResult(
                    tuple(entries),
                    scanned_rows=scanned_rows,
                    cancelled=cancel_event is not None and cancel_event.is_set(),
                    timed_out=time.monotonic() >= deadline,
                )
            return LogSearchResult((), f"全文检索条件无效: {exc}")
        return LogSearchResult(tuple(entries), scanned_rows=scanned_rows)

    def purge(self, now_utc: datetime, retention_days: int = 7) -> int:
        self._ensure_open()
        if retention_days < 1:
            raise ValueError("日志保留天数必须大于零")
        threshold = _as_utc(now_utc) - timedelta(days=retention_days)
        return int(self._submit("purge", threshold.isoformat()))

    def get_cursor(self, source_path: Path) -> FileCursor | None:
        self._ensure_open()
        normalized = str(Path(source_path).expanduser().resolve())
        with closing(self._reader()) as connection:
            row = connection.execute(
                """
                SELECT source_path, file_identity, offset, size, boundary_digest, boundary_length,
                       discard_until_newline
                FROM source_cursors WHERE source_path = ?
                """,
                (normalized,),
            ).fetchone()
        if row is None:
            return None
        return FileCursor(Path(row[0]), row[1], int(row[2]), int(row[3]), row[4], int(row[5]), bool(row[6]))

    def set_cursor(
        self,
        source_path: Path,
        *,
        file_identity: str,
        offset: int,
        size: int,
        boundary_digest: str = "",
        boundary_length: int = 0,
        discard_until_newline: bool = False,
    ) -> None:
        self._ensure_open()
        if offset < 0 or size < 0 or boundary_length < 0:
            raise ValueError("文件游标不能为负数")
        normalized = str(Path(source_path).expanduser().resolve())
        self._submit(
            "set_cursor",
            normalized,
            file_identity,
            offset,
            size,
            boundary_digest,
            boundary_length,
            int(discard_until_newline),
        )

    def close(self) -> None:
        with self._close_lock:
            if self._closed:
                return
            self._closed = True
            self._requests.put(None)
        self._writer.join(timeout=5)
        if self._writer.is_alive():
            raise RuntimeError("日志写入线程未能及时结束")

    def __enter__(self) -> LogStore:
        return self

    def __exit__(self, *_args: object) -> None:
        self.close()

    def _submit(self, action: str, *arguments: Any) -> Any:
        request = _WriteRequest(action, arguments, threading.Event())
        with self._close_lock:
            if self._closed:
                raise RuntimeError("日志存储已关闭")
            if not self._writer.is_alive():
                raise RuntimeError("日志写入线程不可用")
            self._requests.put(request)
        while not request.completed.wait(timeout=0.1):
            if not self._writer.is_alive():
                raise RuntimeError("日志写入线程意外退出")
        if request.error is not None:
            raise request.error
        return request.result

    def _writer_loop(self) -> None:
        with closing(sqlite3.connect(self.path, timeout=5)) as connection:
            connection.execute("PRAGMA busy_timeout=5000")
            while True:
                request = self._requests.get()
                if request is None:
                    return
                try:
                    if request.action == "append":
                        request.result = self._write_entries(connection, request.arguments[0])
                    elif request.action == "repair_file_messages":
                        repaired = 0
                        source, replacements = request.arguments
                        for previous, replacement in replacements:
                            cursor = connection.execute(
                                """
                                UPDATE logs SET message=?, level=?, truncated=?
                                WHERE source=? AND stream='file' AND message=?
                                    AND instr(message, char(65533)) > 0
                                """,
                                (
                                    replacement.message,
                                    replacement.level.value,
                                    int(replacement.truncated),
                                    source.value,
                                    previous,
                                ),
                            )
                            repaired += cursor.rowcount
                        connection.commit()
                        request.result = repaired
                    elif request.action == "purge":
                        cursor = connection.execute("DELETE FROM logs WHERE occurred_at < ?", (request.arguments[0],))
                        connection.commit()
                        request.result = cursor.rowcount
                    elif request.action == "set_cursor":
                        connection.execute(
                            """
                            INSERT INTO source_cursors(
                                source_path, file_identity, offset, size,
                                boundary_digest, boundary_length, discard_until_newline, updated_at
                            )
                            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                            ON CONFLICT(source_path) DO UPDATE SET
                                file_identity=excluded.file_identity,
                                offset=excluded.offset,
                                size=excluded.size,
                                boundary_digest=excluded.boundary_digest,
                                boundary_length=excluded.boundary_length,
                                discard_until_newline=excluded.discard_until_newline,
                                updated_at=excluded.updated_at
                            """,
                            (*request.arguments, datetime.now(UTC).isoformat()),
                        )
                        connection.commit()
                    else:
                        raise ValueError(f"未知日志写操作: {request.action}")
                except BaseException as exc:  # Propagate writer failures to the submitting thread.
                    connection.rollback()
                    request.error = exc
                finally:
                    request.completed.set()

    @staticmethod
    def _write_entries(connection: sqlite3.Connection, entries: tuple[LogEntry, ...]) -> int:
        connection.executemany(
            """
            INSERT INTO logs(occurred_at, source, level, stream, message, truncated, pid)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            (
                (
                    _as_utc(entry.occurred_at).isoformat(),
                    entry.source.value,
                    entry.level.value,
                    entry.stream,
                    entry.message,
                    int(entry.truncated),
                    entry.pid,
                )
                for entry in entries
            ),
        )
        connection.commit()
        return len(entries)

    @staticmethod
    def _sanitize_entry(entry: LogEntry) -> LogEntry:
        safe = make_log_entry(
            source=entry.source,
            stream=entry.stream,
            text=entry.message,
            occurred_at=entry.occurred_at,
            pid=entry.pid,
        )
        return replace(safe, level=entry.level)

    def _reader(self) -> sqlite3.Connection:
        self._ensure_open()
        connection = sqlite3.connect(self.path, timeout=5)
        connection.execute("PRAGMA busy_timeout=5000")
        return connection

    def _ensure_open(self) -> None:
        with self._close_lock:
            if self._closed:
                raise RuntimeError("日志存储已关闭")


def _row_to_entry(row: sqlite3.Row | tuple[Any, ...]) -> LogEntry:
    return LogEntry(
        entry_id=int(row[0]),
        occurred_at=datetime.fromisoformat(row[1]).astimezone(UTC),
        source=LogSource(row[2]),
        level=LogLevel(row[3]),
        stream=row[4],
        message=row[5],
        truncated=bool(row[6]),
        pid=row[7],
    )


def _as_utc(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value.replace(tzinfo=UTC)
    return value.astimezone(UTC)


def _fts_phrase(keyword: str) -> str:
    return f'"{keyword.replace(chr(34), chr(34) * 2)}"'


def _unsafe_regex_reason(pattern: str) -> str | None:
    if len(pattern) > 512:
        return "模式长度不能超过 512 个字符"
    if re.search(r"\(\?(?!:)", pattern):
        return "不支持前后查找、条件或命名组扩展"

    quantifiers: list[tuple[int, int]] = []
    in_class = False
    escaped = False
    index = 0
    while index < len(pattern):
        char = pattern[index]
        if escaped:
            if char.isdigit():
                return "不支持反向引用"
            escaped = False
            index += 1
            continue
        if char == "\\":
            escaped = True
            index += 1
            continue
        if char == "[":
            in_class = True
            index += 1
            continue
        if char == "]" and in_class:
            in_class = False
            index += 1
            continue
        if in_class:
            index += 1
            continue
        if char == "|":
            return "不支持可能产生高回溯的分支"
        end = index + 1
        is_quantifier = char in "*+?"
        if char == "?" and index > 0 and pattern[index - 1] == "(":
            is_quantifier = False
        elif char == "{":
            closing = pattern.find("}", index + 1)
            quantifier_body = pattern[index + 1 : closing] if closing >= 0 else ""
            if closing >= 0 and re.fullmatch(r"(?:\d+(?:,\d*)?|,\d+)", quantifier_body):
                bounds = tuple(int(value) for value in quantifier_body.split(",") if value)
                if any(value > MAX_REGEX_QUANTIFIER_BOUND for value in bounds):
                    return f"计数量词的数值或范围不能超过 {MAX_REGEX_QUANTIFIER_BOUND}"
                is_quantifier = True
                end = closing + 1
        if is_quantifier:
            atom_start = _regex_atom_start(pattern, index)
            if atom_start is None:
                return "量词缺少安全的前置表达式"
            if pattern[atom_start] == ")":
                return "不支持对分组重复匹配"
            quantifiers.append((index, atom_start))
            if len(quantifiers) > 2:
                return "量词数量不能超过 2 个"
        index = end

    if len(quantifiers) == 2:
        first_index = quantifiers[0][0]
        second_atom_start = quantifiers[1][1]
        separator = pattern[first_index + 1 : second_atom_start]
        if not _regex_has_literal_separator(separator):
            return "多个量词之间必须包含固定文本"
    return None


def _regex_atom_start(pattern: str, quantifier_index: int) -> int | None:
    previous = quantifier_index - 1
    if previous < 0:
        return None
    if pattern[previous] == ")":
        return previous
    if pattern[previous] == "]":
        opening = previous - 1
        escaped = False
        while opening >= 0:
            char = pattern[opening]
            if char == "[" and not escaped:
                return opening
            escaped = char == "\\" and not escaped
            if char != "\\":
                escaped = False
            opening -= 1
        return None
    if previous > 0 and pattern[previous - 1] == "\\":
        return previous - 1
    return previous


def _regex_has_literal_separator(fragment: str) -> bool:
    in_class = False
    escaped = False
    for char in fragment:
        if escaped:
            if char not in "AbBdDsSwWZz":
                return True
            escaped = False
            continue
        if char == "\\":
            escaped = True
        elif char == "[":
            in_class = True
        elif char == "]" and in_class:
            in_class = False
        elif not in_class and char not in ".^$()":
            return True
    return False

