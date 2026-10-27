# OPC Service Monitor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and package a Windows PySide6 desktop tool that safely controls the OPC PostgreSQL, BackendService, and FrontendAdmin development services and provides searchable runtime and business-audit logs, with Flutter fully excluded.

**Architecture:** Keep service definitions, logging, HTTP clients, process ownership, and orchestration as pure Python modules behind injectable protocols. The Qt Widgets layer consumes those modules through signals and background workers; local runtime logs are redacted before a single-writer SQLite FTS5 index, while business audit data stays in the authenticated in-memory session.

**Tech Stack:** Python 3.12.7 x64, PySide6 6.10.3, httpx 0.28.1, psutil 7.2.2, SQLite/FTS5, pytest 9.1.1, pytest-qt 4.5.0, Ruff 0.17.1, PyInstaller 6.22.3, PowerShell.

**Spec:** `Docs/planning/opc-service-monitor-design-2026-10-22.md`

## Global Constraints

- Create the internal tool under `Tools/ServiceMonitor`; it is not a third OPC product endpoint.
- Use `py -3.12` to create the tool venv; the machine default Python is 3.14 and must not be used implicitly.
- Manage only PostgreSQL `127.0.0.1:55440`, BackendService `127.0.0.1:8001`, and FrontendAdmin `127.0.0.1:5180`.
- Do not add Flutter, ADB, device, mobile-log, or Flutter build functionality anywhere in this tool.
- Do not run `seed-demo.py`, read `.env` or `.local/demo-credentials.json`, or expose database credentials, passwords, tokens, private files, or full SQL parameters.
- Never take ownership of a listener that existed before the current monitor session; validate PID, creation time, executable, and expected command/data path immediately before stopping an owned process.
- PostgreSQL `start` is an explicit mutation that may initialize/migrate; health polling must never call it. PostgreSQL stop must use the existing marked helper and retain data.
- Runtime log content must be redacted before UI display, SQLite persistence, or export. Business-audit response bodies are session-only and are not written to SQLite.
- Store non-sensitive settings and runtime-log data only below `%LOCALAPPDATA%\OPC\ServiceMonitor`, with a test-only override.
- The UI is Simplified Chinese, has exactly the five approved tabs, and does not claim business integration success from process status alone.
- Build `onedir + windowed`; never bundle the repository, BackendService venv, Node.js, PostgreSQL, `.env`, `.local`, or business data.
- `D:\OPC` has no `.git`; do not claim commits. Each task ends with recorded passing verification instead of a Git commit.

## Review Focus

- A listener can disappear and its PID can be reused between observation and stop; Task 4 must reject any identity mismatch at the final stop boundary.
- A child can emit a UTF-8 character across chunks or a line larger than memory-friendly UI limits; Task 2 must decode incrementally and truncate a single displayed/indexed line at 65,536 characters with an explicit marker.
- Rapid repeated start/stop clicks can race; Tasks 5 and 6 must serialize one lifecycle operation and disable conflicting controls until final observation.
- Audit rows can be inserted while older pages are fetched; Tasks 3 and 7 must page strictly with `before_id=min(id)` and de-duplicate rows by integer id.
- The packaged app can run with global Qt environment variables or from a non-source working directory; Task 8 must resolve resources independently, ignore repository-relative cwd assumptions, and perform a real Windows platform-plugin smoke test.

---

## File Map

`Tools/ServiceMonitor/src/opc_service_monitor` contains one responsibility per module:

- `models.py`: immutable service, process, health, log, audit, and operation value types.
- `paths.py`: OPC-root validation/discovery and `%LOCALAPPDATA%` runtime paths.
- `catalog.py`: fixed safe commands, ports, URLs, allowed log paths, and dependency order.
- `log_pipeline.py`: stream decoding, ANSI cleanup, level detection, truncation, and redaction.
- `log_store.py`: SQLite schema, FTS5 search, retention, corruption recovery, and source cursors.
- `file_tail.py`: incremental tracking of the two explicitly allowed PostgreSQL log files.
- `health.py`: port, BackendService, FrontendAdmin, and PostgreSQL status probes.
- `audit.py`: admin login/me/logout and cursor-based audit reads.
- `processes.py`: command execution, streaming, process identity, listener discovery, validation, and tree stop.
- `postgres.py`: guarded PostgreSQL helper/status/ownership behavior.
- `supervisor.py`: serialized individual/all lifecycle operations and state transitions.
- `workers.py`: Qt-safe background execution and signal bridge.
- `diagnostics.py`: redacted rotating monitor self-log for the windowed executable.
- `ui/service_card.py`, `ui/log_panel.py`, `ui/audit_panel.py`, `ui/main_window.py`: focused widgets.
- `app.py`, `__main__.py`: composition root and CLI/smoke entry.

## Task 1: Project foundation, paths, models, and safe catalog

**Files:**
- Create: `Tools/ServiceMonitor/pyproject.toml`
- Create: `Tools/ServiceMonitor/{requirements.lock.txt,requirements-dev.lock.txt}`
- Create: `Tools/ServiceMonitor/src/opc_service_monitor/{__init__.py,models.py,paths.py,catalog.py}`
- Create: `Tools/ServiceMonitor/tests/{conftest.py,test_paths.py,test_catalog.py}`
- Create: `Tools/ServiceMonitor/.gitignore`

**Interfaces:**
- Produces `ServiceId`, `ServiceState`, `LogSource`, `LogLevel`, `CommandSpec`, `ServiceDefinition`, `ProjectLayout`, and `RuntimePaths`.
- Produces `ProjectLayout.validate(root: Path) -> ProjectLayout`, `discover_project_root(saved: Path | None, source_anchor: Path, packaged: bool) -> ProjectLayout | None`, `build_catalog(layout: ProjectLayout) -> dict[ServiceId, ServiceDefinition]`.

- [x] **Step 1: Create package metadata.** Pin runtime dependencies to `PySide6==6.10.3`, `httpx==0.28.1`, `psutil==7.2.2`; pin `pytest==9.1.1`, `pytest-qt==4.5.0`, `ruff==0.17.1`, `PyInstaller==6.22.3`, and `pip-tools==7.6.2`; set `requires-python = ">=3.12,<3.13"`, `qt_api = "pyside6"`, Ruff py312/120 columns, setuptools src discovery, and a console entry point.
- [x] **Step 2: Create the isolated tool environment.** Use `py -3.12` for `.venv`, generate Windows x64 hash-locked runtime/dev files, install the dev lock, install the package editable with `--no-deps`, and require `pip check` to pass.
- [x] **Step 3: Write failing path and catalog tests.** Assert deterministic root discovery order; reject a root missing any required marker; assert fixed cwd, executable/argument lists, ports, health URLs, PostgreSQL helper arguments, and exactly two allowed PG log files. Assert no command contains Flutter/ADB or secrets.
- [x] **Step 4: Run `.\.venv\Scripts\python.exe -m pytest tests/test_paths.py tests/test_catalog.py -q` from `Tools/ServiceMonitor` and confirm import/contract failures.**
- [x] **Step 5: Implement the minimal types, project paths, runtime paths, and catalog.**
- [x] **Step 6: Re-run the two tests and `.\.venv\Scripts\python.exe -m compileall -q src`; expect PASS and no output.**
- [x] **Step 7: Record the passing command/output in the implementation log; no Git commit is possible in this workspace.**

## Task 2: Redacted log ingestion, SQLite search, and PostgreSQL file tailing

**Files:**
- Create: `Tools/ServiceMonitor/src/opc_service_monitor/{log_pipeline.py,log_store.py,file_tail.py}`
- Modify: `Tools/ServiceMonitor/src/opc_service_monitor/models.py`
- Create: `Tools/ServiceMonitor/tests/{test_log_pipeline.py,test_log_store.py,test_file_tail.py}`

**Interfaces:**
- Produces `IncrementalLineDecoder.feed(chunk: bytes) -> list[str]`, `flush() -> list[str]`, `redact_log_text(text: str) -> str`, and `make_log_entry(...) -> LogEntry`.
- Produces `LogQuery`, `LogSearchResult`, and `LogStore.open(path)`, `append(entries)`, `search(query)`, `purge(now_utc, retention_days=7)`, `get_cursor(source_path)`, `set_cursor(...)`, `recover_if_corrupt(path)`.
- Produces `AllowedFileTailer.poll() -> list[LogEntry]`; first observation imports only the final 2 MiB on a line boundary, then resumes by stored file identity/size/offset.

- [x] **Step 1: Write failing pipeline tests.** Cover split UTF-8, CRLF/LF, ANSI removal, invalid bytes, stdout/stderr levels, UTC timestamps, 65,536-character truncation, and redaction of Bearer tokens, password/secret/token assignments, command-line credentials, and PostgreSQL URLs before any sink sees them.
- [x] **Step 2: Run `.\.venv\Scripts\python.exe -m pytest tests/test_log_pipeline.py -q`; confirm expected missing behavior failures.**
- [x] **Step 3: Implement the decoder/redactor/entry factory minimally.**
- [x] **Step 4: Re-run the pipeline tests; expect PASS.**
- [x] **Step 5: Write failing store/tailer tests.** Cover FTS/plain/regex/case/time/level/source filtering, invalid regex as a validation result, seven-day boundary, WAL use, corrupt-database quarantine/rebuild, first-read 2 MiB bound, resume cursor, truncation/rotation, and rejection of any path outside the two catalog entries.
- [x] **Step 6: Run the store/tailer tests and confirm feature-missing failures.**
- [x] **Step 7: Implement SQLite FTS5 storage with a single writer queue and the allowed file tailer; keep audit rows out of this schema.**
- [x] **Step 8: Run all Task 2 tests; expect PASS with no unhandled thread/SQLite warnings.**
- [x] **Step 9: Record the milestone; no Git commit is possible.**

## Task 3: Health probes and in-memory admin audit client

**Files:**
- Create: `Tools/ServiceMonitor/src/opc_service_monitor/{health.py,audit.py}`
- Modify: `Tools/ServiceMonitor/src/opc_service_monitor/models.py`
- Create: `Tools/ServiceMonitor/tests/{test_health.py,test_audit.py}`

**Interfaces:**
- Produces `HealthProbe.probe_port(host, port)`, `probe_backend()`, and `probe_frontend()` returning `HealthResult` with process/port/live/ready evidence kept distinct.
- Produces `AuditClient.login(email: str, password: str) -> AdminSession`, `me() -> AdminProfile`, `list_events(limit: int = 50, before_id: int | None = None) -> AuditPage`, and `logout() -> None`.
- `AuditPage.next_before_id` is the minimum returned id or `None`; it de-duplicates by id when combined with earlier pages.

- [x] **Step 1: Write failing `httpx.MockTransport` health tests.** Assert exact `/health/live`, `/health/ready`, and `/` title contracts; distinguish live/not-ready/timeout/wrong frontend; ensure a probe never logs headers or response secrets.
- [x] **Step 2: Run health tests and confirm missing implementation failures.**
- [x] **Step 3: Implement health probes with a 3-second default timeout.**
- [x] **Step 4: Re-run health tests; expect PASS.**
- [x] **Step 5: Write failing audit tests.** Assert login JSON and response validation, Bearer header, administrator-only 403 mapping, 401 token clearing, 429/422/503 error mapping, `before_id=min(id)` pagination, duplicate removal, explicit logout revocation, password argument lifetime, and no token/password persistence.
- [x] **Step 6: Run audit tests and confirm missing behavior failures.**
- [x] **Step 7: Implement the in-memory audit client.**
- [x] **Step 8: Re-run all Task 3 tests plus `ruff check`; expect PASS.**
- [x] **Step 9: Record the milestone; no Git commit is possible.**

## Task 4: Owned process execution and guarded PostgreSQL control

**Files:**
- Create: `Tools/ServiceMonitor/src/opc_service_monitor/{processes.py,postgres.py}`
- Modify: `Tools/ServiceMonitor/src/opc_service_monitor/models.py`
- Create: `Tools/ServiceMonitor/tests/{fixtures/dummy_service.py,test_processes.py,test_postgres.py}`

**Interfaces:**
- Produces `ProcessIdentity(pid, create_time_ns, executable, command_line)`, `OwnedProcess`, `SpawnedProcess`, `OwnershipCheck`, and a `ProcessAdapter` protocol with `listener`, `spawn`, `inspect`, `validate_owned`, `request_stop`, and `force_stop`.
- `SubprocessProcessAdapter` accepts only `CommandSpec`, streams redacted stdout/stderr through a callback, creates a Windows process group, validates identity again before signaling, waits a bounded interval, and force-stops only the still-matching owned tree.
- Produces `PostgresController.status()`, `start(timeout_s)`, and `stop(owned, timeout_s)`; ownership includes the verified listener identity and fixed `.local/integration/data` path, not the short-lived helper PID.

- [x] **Step 1: Write failing pure/fake adapter ownership tests.** Cover fixed args/cwd/environment, listener present before spawn as external, PID reuse, creation-time mismatch, executable mismatch, command/data-path mismatch, and final-boundary revalidation.
- [x] **Step 2: Run ownership tests and confirm feature-missing failures.**
- [x] **Step 3: Implement identity inspection, safe spawning, incremental callbacks, bounded stop escalation, and descendant leaf-first force cleanup using psutil.** Never build a shell command string from user input.
- [x] **Step 4: Write failing PostgreSQL tests.** Assert `start` is called only after a closed 55440 precheck, helper output is captured without waiting on postgres log handles, runtime PID is separately identified, status never invokes `start`, unverified ownership blocks `stop`, and verified stop calls the existing helper with data retained.
- [x] **Step 5: Implement `PostgresController`.**
- [x] **Step 6: Run all Task 4 tests and confirm dummy child processes are gone after every test.**
- [x] **Step 7: Record the milestone; no Git commit is possible.**

## Task 5: Serialized service lifecycle orchestration

**Files:**
- Create: `Tools/ServiceMonitor/src/opc_service_monitor/supervisor.py`
- Create: `Tools/ServiceMonitor/tests/test_supervisor.py`

**Interfaces:**
- Produces `CancelToken`, `ServiceObservation`, `OperationStep`, `OperationReport`, and `ServiceSupervisor.start(service)`, `start_all()`, `stop(service)`, `stop_all()`, `refresh()`.
- Consumes catalog, `ProcessAdapter`, `PostgresController`, `HealthProbe`, monotonic clock/waiter, and log callback by dependency injection.
- Emits state changes through a callback without importing PySide6.

- [x] **Step 1: Write failing state-machine tests.** Assert PG→backend→frontend, frontend→backend→PG, 30-second defaults and configurable 5–120 second bounds, per-step readiness waits, partial-start report without rollback, failed stop preventing dependency shutdown, external instances never stopped, duplicate lifecycle calls rejected, and cancellation only ending the wait before refreshing real state.
- [x] **Step 2: Run `test_supervisor.py` and confirm missing behavior failures.**
- [x] **Step 3: Implement the minimal serialized supervisor and state transitions.** Keep process-running, port, live, ready, ownership, and error evidence separate in each observation.
- [x] **Step 4: Run Task 5 tests plus Tasks 1–4; expect all PASS. Record the milestone.**

## Task 6: Qt composition, main window, service cards, and operation workers

**Files:**
- Create: `Tools/ServiceMonitor/src/opc_service_monitor/{workers.py,diagnostics.py,app.py,__main__.py}`
- Create: `Tools/ServiceMonitor/src/opc_service_monitor/ui/{__init__.py,service_card.py,main_window.py,theme.qss}`
- Create: `Tools/ServiceMonitor/tests/{test_workers.py,test_diagnostics.py,test_main_window.py}`

**Interfaces:**
- Produces `TaskWorker`/`WorkerSignals` for one bounded background call, and a `MonitorController` that marshals supervisor/log events onto the Qt thread.
- Produces `ServiceCard.set_observation(ServiceObservation)` and `MainWindow` actions for all/individual start-stop, refresh, browser URLs, settings, and close confirmation.
- `app.main(argv: Sequence[str] | None = None) -> int` creates the QApplication and supports a later `--smoke-test` path without starting services.

- [x] **Step 1: Write failing pytest-qt and diagnostics tests.** Assert three cards and Chinese labels, exact state rendering, PID only when reliable, conflicting buttons disabled during one operation, rapid double-click starts one task, two-second single-flight refresh, operation errors remain actionable/redacted, browser targets are fixed, redacted rotating self-logging below the runtime path, and no Flutter/ADB text or action exists.
- [x] **Step 2: Run Qt tests with `QT_QPA_PLATFORM=offscreen`; confirm missing widget failures.**
- [x] **Step 3: Implement workers, diagnostics, composition root, service cards, main layout, theme, dependency check/settings dialog, and close behavior.** Keep every network/process wait off the GUI thread.
- [x] **Step 4: Re-run Qt tests and the full suite; expect PASS without Qt thread-destroyed warnings. Record the milestone.**

## Task 7: Log tabs, search/export, and business-audit UI

**Files:**
- Create: `Tools/ServiceMonitor/src/opc_service_monitor/ui/{log_panel.py,audit_panel.py}`
- Modify: `Tools/ServiceMonitor/src/opc_service_monitor/ui/main_window.py`
- Modify: `Tools/ServiceMonitor/src/opc_service_monitor/app.py`
- Create: `Tools/ServiceMonitor/tests/{test_log_panel.py,test_audit_panel.py,test_ui_integration.py}`

**Interfaces:**
- Produces `LogPanel.set_query`, `append_live`, `reload_history`, `pause_auto_scroll`, `clear_view`, and `export_filtered(path)`; visible rows are capped at the latest 5,000 while SQLite remains authoritative for seven days.
- Produces `AuditPanel` login/logout/refresh/load-more/filter behavior. Filters operate over loaded de-duplicated pages; “加载更多” advances with `before_id` until an empty page.
- MainWindow exposes exactly `全部日志`, `前端`, `后端`, `PostgreSQL`, `业务审计`.

- [x] **Step 1: Write failing log-panel tests.** Assert exact tabs, source isolation/all merge, time/level/source/keyword/case/regex filters, invalid regex feedback, pause/jump-latest, 5,000-row cap, clear-view without deletion, copy, and redacted export.
- [x] **Step 2: Run log-panel tests and confirm missing behavior failures.**
- [x] **Step 3: Implement the log panel and re-run its tests; expect PASS.**
- [x] **Step 4: Write failing audit-panel tests.** Assert password field clearing, in-memory-only token, login error mapping, page cursor/de-duplication, loaded-row time/actor/table/operation/keyword filters, 401 relogin, 403 administrator guidance, logout revocation, and cache clearing on close.
- [x] **Step 5: Run audit-panel tests and confirm missing behavior failures.**
- [x] **Step 6: Implement audit UI and wire all collectors through the redaction/store boundary.**
- [x] **Step 7: Run Task 7 and full-suite tests; expect PASS.**
- [x] **Step 8: Record the milestone; no Git commit is possible.**

## Task 8: Dependency locks, Windows package, documentation, and real smoke verification

**Files:**
- Create: `Tools/ServiceMonitor/{README.md,build.ps1,run.ps1}`
- Create: `Tools/ServiceMonitor/packaging/{entrypoint.py,OPCServiceMonitor.spec}`
- Create: `Tools/ServiceMonitor/scripts/smoke-package.ps1`
- Modify: `Tools/ServiceMonitor/src/opc_service_monitor/app.py`
- Modify: `README.md`
- Modify: `Docs/README.md`
- Modify: `Docs/project-context.md`
- Modify: `Docs/planning/opc-service-monitor-design-2026-10-22.md`
- Create: `Docs/testing/opc-service-monitor-2026-10-22.md`
- Test: `Tools/ServiceMonitor/tests/test_smoke_mode.py`

**Interfaces:**
- Produces `--smoke-test --report <path>`: create QApplication/MainWindow, load resources/config without starting services, process events, write a redacted JSON report, and exit nonzero on any failure.
- Produces `build.ps1` using the module venv and committed spec, and `smoke-package.ps1` with a bounded hidden-process wait.

- [x] **Step 1: Write the failing smoke-mode test.** Assert no service adapter start/stop call, report contains app/Qt/Python/platform/resource results but no environment values or tokens, and path resolution works with an unrelated cwd.
- [x] **Step 2: Run the smoke test and confirm missing behavior failure.**
- [x] **Step 3: Implement smoke mode and re-run its test; expect PASS.**
- [x] **Step 4: Create a clean `.verify-venv` with `py -3.12` and install the committed hash-locked dev requirements plus the package editable with `--no-deps`.** Do not reuse BackendService `.venv`.
- [x] **Step 5: Run `.verify-venv` `pip check` and record the exact resolved versions.**
- [x] **Step 6: Run `.verify-venv` `pytest -q`, `ruff check src tests packaging`, and `python -m compileall -q src`; all must pass cleanly.**
- [x] **Step 7: Build `dist/OPCServiceMonitor/OPCServiceMonitor.exe` with PyInstaller `onedir + windowed + noupx`.**
- [x] **Step 8: Verify `qwindows.dll` exists and run the packaged `--smoke-test` from a non-source cwd.**
- [x] **Step 9: Perform visual Windows QA of the actual desktop app.** Verify Chinese text, three status cards, five tabs, resize behavior, disabled controls, search validation, audit login layout, and close confirmation; save a screenshot only if it contains no credentials or private records.
- [x] **Step 10: Perform the guarded real OPC smoke.** Snapshot service/listener state and a non-sensitive PG data-presence fact; if all target ports are free, use the packaged app to start PG→backend→frontend, verify 55440/8001/5180, exercise runtime log search, then stop frontend→backend→PG and verify the data-presence fact is unchanged. If any target is external, do read-only health checks and document why lifecycle mutation was skipped.
- [x] **Step 11: Update README/context/index/design status and write the dated verification record with commands, counts, package path, actual smoke result, and remaining capability boundaries.** Do not claim production readiness, browser-console capture, Flutter coverage, or tests not actually run.
- [x] **Step 12: Re-run the full verification commands after documentation/build-script changes and record final evidence; no Git commit is possible.**

