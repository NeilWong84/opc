from __future__ import annotations

import hashlib
import os
from pathlib import Path

from opc_service_monitor.log_pipeline import IncrementalLineDecoder, make_log_entry, windows_log_encodings
from opc_service_monitor.log_store import LogStore
from opc_service_monitor.models import LogEntry, LogSource


INITIAL_IMPORT_BYTES = 2 * 1024 * 1024
_BOUNDARY_BYTES = 64
_OVERLONG_LINE_MARKER = "日志行超过单次读取上限，原始内容已丢弃…[已截断]"


class AllowedFileTailer:
    def __init__(
        self,
        source_path: Path,
        *,
        allowed_paths: tuple[Path, ...],
        store: LogStore,
        source: LogSource = LogSource.POSTGRES,
        initial_bytes: int = INITIAL_IMPORT_BYTES,
        max_complete_lines: int = 10_000,
    ) -> None:
        resolved = Path(source_path).expanduser().resolve()
        allowed = {Path(path).expanduser().resolve() for path in allowed_paths}
        if resolved not in allowed:
            raise ValueError(f"日志文件不在白名单中: {resolved}")
        if initial_bytes < 1:
            raise ValueError("首次日志读取上限必须大于零")
        if max_complete_lines < 1:
            raise ValueError("单次日志读取行数上限必须大于零")
        self.source_path = resolved
        self._store = store
        self._source = source
        self._initial_bytes = initial_bytes
        self._max_complete_lines = max_complete_lines
        self.last_bytes_read = 0
        self.last_repair_bytes_read = 0
        self._legacy_repair_complete = False

    def repair_legacy_entries(self) -> int:
        """Repair only exact, unambiguous messages backed by allowed raw bytes."""

        if self._legacy_repair_complete:
            return 0
        self.last_repair_bytes_read = 0
        try:
            with self.source_path.open("rb") as handle:
                size = os.fstat(handle.fileno()).st_size
                start = max(0, size - self._initial_bytes)
                handle.seek(start)
                payload = handle.read(min(size - start, self._initial_bytes))
        except OSError:
            return 0
        self.last_repair_bytes_read = len(payload)
        if start > 0:
            newline = payload.find(b"\n")
            payload = payload[newline + 1 :] if newline >= 0 else b""
        complete_payload = _bounded_complete_lines(payload, self._max_complete_lines)
        decoder = IncrementalLineDecoder(fallback_encodings=windows_log_encodings())
        corrected_lines = decoder.feed(complete_payload)
        candidates: dict[str, dict[str, LogEntry]] = {}
        for raw_line, corrected in zip(complete_payload.split(b"\n")[:-1], corrected_lines, strict=True):
            previous = make_log_entry(
                source=self._source,
                stream="file",
                text=raw_line.decode("utf-8", errors="replace").removesuffix("\r"),
            )
            replacement = make_log_entry(source=self._source, stream="file", text=corrected)
            if "\ufffd" in previous.message:
                candidates.setdefault(previous.message, {})[replacement.message] = replacement
        replacements = {
            previous: next(iter(options.values()))
            for previous, options in candidates.items()
            if len(options) == 1 and "\ufffd" not in next(iter(options))
        }
        repaired = self._store.repair_file_messages(self._source, replacements)
        self._legacy_repair_complete = True
        return repaired

    def poll(self) -> list[LogEntry]:
        self.last_bytes_read = 0
        self.repair_legacy_entries()
        try:
            stat_before = self.source_path.stat()
        except (FileNotFoundError, OSError):
            return []
        if not self.source_path.is_file():
            return []

        identity = _file_identity(stat_before)
        cursor = self._store.get_cursor(self.source_path)
        resumed = (
            cursor is not None
            and cursor.file_identity == identity
            and stat_before.st_size >= cursor.offset
            and _boundary_matches(self.source_path, cursor.offset, cursor.boundary_length, cursor.boundary_digest)
        )
        start = cursor.offset if resumed and cursor is not None else max(0, stat_before.st_size - self._initial_bytes)
        discard_until_newline = (
            cursor.discard_until_newline if resumed and cursor is not None else not resumed and start > 0
        )

        try:
            with self.source_path.open("rb") as handle:
                handle.seek(start)
                maximum = min(stat_before.st_size - start, self._initial_bytes)
                payload = handle.read(maximum)
                stat_after = os.fstat(handle.fileno())
        except (FileNotFoundError, OSError):
            return []

        self.last_bytes_read = len(payload)
        payload_start = start
        emit_overlong_marker = False
        if discard_until_newline:
            newline = payload.find(b"\n")
            if newline < 0:
                offset = start + len(payload)
                payload = b""
            else:
                payload_start += newline + 1
                payload = payload[newline + 1 :]
                discard_until_newline = False

        if discard_until_newline:
            complete_payload = b""
        else:
            complete_payload = _bounded_complete_lines(payload, self._max_complete_lines)
            offset = payload_start + len(complete_payload)
            if not complete_payload and len(payload) >= self._initial_bytes:
                offset = payload_start + len(payload)
                discard_until_newline = True
                emit_overlong_marker = True
        boundary_length = min(_BOUNDARY_BYTES, offset)
        try:
            with self.source_path.open("rb") as handle:
                handle.seek(offset - boundary_length)
                boundary_digest = hashlib.sha256(handle.read(boundary_length)).hexdigest()
        except (FileNotFoundError, OSError):
            return []

        decoder = IncrementalLineDecoder(fallback_encodings=windows_log_encodings())
        lines = decoder.feed(complete_payload)
        entries = [make_log_entry(source=self._source, stream="file", text=line) for line in lines]
        if emit_overlong_marker:
            entries.append(make_log_entry(source=self._source, stream="file", text=_OVERLONG_LINE_MARKER))
        if entries:
            self._store.append(entries)
        self._store.set_cursor(
            self.source_path,
            file_identity=_file_identity(stat_after),
            offset=offset,
            size=stat_after.st_size,
            boundary_digest=boundary_digest,
            boundary_length=boundary_length,
            discard_until_newline=discard_until_newline,
        )
        return entries


def _file_identity(stat_result: os.stat_result) -> str:
    # Windows can report slightly different ctime nanoseconds for stat() and
    # fstat() on the same unchanged file. Volume + file index is stable across
    # those APIs; the boundary digest separately detects in-place rewrites.
    return f"{stat_result.st_dev}:{stat_result.st_ino}"


def _bounded_complete_lines(payload: bytes, maximum_lines: int) -> bytes:
    complete_end = 0
    search_from = 0
    for _ in range(maximum_lines):
        newline = payload.find(b"\n", search_from)
        if newline < 0:
            break
        complete_end = newline + 1
        search_from = complete_end
    return payload[:complete_end]


def _boundary_matches(path: Path, offset: int, length: int, expected_digest: str) -> bool:
    if length == 0 or not expected_digest:
        return True
    if length > offset:
        return False
    try:
        with path.open("rb") as handle:
            handle.seek(offset - length)
            actual = handle.read(length)
    except OSError:
        return False
    return len(actual) == length and hashlib.sha256(actual).hexdigest() == expected_digest

