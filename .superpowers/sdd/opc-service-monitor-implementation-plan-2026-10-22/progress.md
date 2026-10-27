Plan: D:\OPC\Docs\planning\opc-service-monitor-implementation-plan-2026-10-22.md

# OPC Service Monitor execution ledger

## Preflight ruling

- Workspace fact: `D:\OPC` has no Git metadata, so a worktree, task commits, and branch rollback are unavailable.
- Ruling: implement in place, strictly scoped to `Tools/ServiceMonitor` plus the already-listed OPC documentation files.
- Cost if wrong: there is no automatic Git rollback. Risk is bounded by creating a new isolated tool module, using test-first changes, and recording every verification command here.
- Environment ruling: package metadata and dependency locks may precede production code; the editable install follows the first green package implementation because an absent package cannot be installed.

## Cross-task interface check

| Producer | Consumer | Contract | Status |
| --- | --- | --- | --- |
| Task 1 | Task 2 | models, paths, catalog | clean |
| Task 1 | Task 3 | models, catalog | clean |
| Task 1 | Task 4 | CommandSpec, ProjectLayout | clean |
| Task 2 | Tasks 6-7 | LogEntry, LogStore | clean |
| Task 3 | Tasks 6-7 | HealthResult, AuditClient | clean |
| Task 4 | Task 5 | process and PostgreSQL adapters | clean |
| Task 5 | Task 6 | observations and operations | clean |
| Task 6 | Task 7 | MainWindow composition | clean |
| Task 1 | Task 8 | package metadata and locks | clean |
| Tasks 6-7 | Task 8 | app and smoke composition | clean |

## Task self-consistency

| Task | Scope/dependency check | Result |
| --- | --- | --- |
| 1 | Foundation has no prior implementation dependency | clean |
| 2 | Uses Task 1 value types and fixed allowed paths | clean |
| 3 | Uses Task 1 URLs/models; no persistence of auth data | clean |
| 4 | Uses Task 1 safe commands; ownership checked at stop boundary | clean |
| 5 | Pure orchestration over Tasks 3-4 | clean |
| 6 | Qt layer depends only on established core interfaces | clean |
| 7 | UI uses redacted store and session-only audit client | clean |
| 8 | Packaging follows implementation and clean-environment verification | clean |

## Milestones

- Task 1: complete.
  - RED: `.\.venv\Scripts\python.exe -m pytest tests\test_paths.py tests\test_catalog.py -q` failed during collection with the expected missing `opc_service_monitor.paths` and `catalog` modules.
  - GREEN: the same test command completed with `18 passed in 0.32s`.
  - Compile: `.\.venv\Scripts\python.exe -m compileall -q src` exited 0 with no output.
  - Environment: both hash locks were generated with Python 3.12; the development lock uses `--allow-unsafe` so clean venvs also pin `pip` and `setuptools`.
  - Install: editable `--no-deps` install succeeded and `pip check` reported `No broken requirements found.`
- Task 2: complete.
  - RED pipeline: missing `opc_service_monitor.log_pipeline` failed collection as expected.
  - Pipeline GREEN: `21 passed in 0.03s`.
  - RED store/tailer: missing `log_store` and `file_tail` failed collection as expected.
  - Debug ruling: SQLite connection context managers do not close handles; corruption quarantine now uses explicit closing before rename. Windows `stat()`/`fstat()` can disagree on ctime nanoseconds; file identity therefore uses stable volume/file index while a persisted SHA-256 boundary digest detects in-place truncate-and-regrow.
  - Stability check: the cursor resume regression ran 30 times with `repeat_failures=0`.
  - GREEN: `.\.venv\Scripts\python.exe -m pytest tests\test_log_pipeline.py tests\test_log_store.py tests\test_file_tail.py -q` completed with `34 passed in 0.78s`.
  - Lint: `.\.venv\Scripts\python.exe -m ruff check src tests` reported `All checks passed!`.
- Task 3: complete.
  - RED: health/audit tests failed collection with the expected missing modules.
  - Contract correction: HTTPX `QueryParams` does not compare equal to a plain mapping even when its pairs match; the test now compares `dict(request.url.params)` without changing production behavior.
  - GREEN: `.\.venv\Scripts\python.exe -m pytest tests\test_health.py tests\test_audit.py -q` completed with `18 passed in 0.48s`.
  - Lint: `.\.venv\Scripts\python.exe -m ruff check src tests` reported `All checks passed!`.
- Task 4: complete.
  - RED: process/PostgreSQL tests failed collection with the expected missing modules.
  - GREEN: focused Task 4 tests completed with `11 passed in 0.27s`; the Windows dummy service and child were both gone after force-stop verification.
  - Full through Task 4: `81 passed in 1.53s`; two Ruff-only unused names were removed, after which lint passed.
- Task 5: complete.
  - RED: supervisor test failed collection with the expected missing module.
  - GREEN: focused supervisor tests completed with `9 passed in 0.13s`.
  - Full through Task 5: `.\.venv\Scripts\python.exe -m pytest -q` completed with `90 passed in 1.58s`; Ruff passed and compileall exited 0 with no output.
- Task 6: complete.
  - RED: workers, diagnostics, and main-window tests failed collection with the expected missing modules/UI package.
  - GREEN: focused Qt/diagnostics tests completed with `10 passed in 0.25s` under `QT_QPA_PLATFORM=offscreen`.
  - Full through Task 6 reached `100 passed in 1.69s`; Ruff found only three unused imports, which were removed; focused rerun and Ruff both passed.
- Task 7: complete.
  - RED: log-panel, audit-panel, and UI-integration tests initially failed because the modules and exact five-tab composition did not yet exist.
  - GREEN: implemented incremental live rows, source-isolated/all aggregation, background search/export, regex validation, clear/copy/pause/latest behavior, 5,000 visible-row cap, and redacted CSV export.
  - Audit: implemented password clearing, memory-only sessions, serialized login/logout/queries, de-duplicated cursor pagination, loaded-row filtering, 401/403 handling, and asynchronous shutdown cleanup.
  - Hardening: removed GUI-thread network/file work, bounded no-newline decoding, fixed SQLite close/submit ordering, committed file tails only through complete newlines, and added runtime seven-day purging.
  - Focused Task 7 tests passed; later full-suite hardening reached `221 passed`.
- Task 8: complete.
  - Smoke TDD: smoke-mode tests first failed before the packaged composition existed, then passed after implementing resource-independent QApplication/MainWindow construction and redacted JSON reporting without service lifecycle calls.
  - Clean environment: `.verify-venv` uses Python 3.12.7 and the committed hash-locked development requirements; `pip check` reported no broken requirements.
  - Resolved core versions: PySide6 6.10.3, httpx 0.28.1, psutil 7.2.2, regex 2026.9.29, pytest 9.1.1, pytest-qt 4.5.0, Ruff 0.17.1, PyInstaller 6.22.3, and pip-tools 7.6.2.
  - Post-review hardening: separated listener occupancy from optional PID identity (including wildcard binds); safely recovered early-exit wrapper descendants through identity-checked parent chains; expanded prefixed secret/API-key redaction; bounded file, SQLite parameter, ingestion, Qt live, and search pipelines; added an 8 Mi-character result budget, pre-compile regex structure/count validation, history/live hard timeouts, and explicit incomplete-result warnings; kept SQLite writes off pipe readers; bounded output-thread joins; and enforced drain-before-close shutdown ordering.
  - Final automated baseline after documentation tracking updates: `221 passed in 4.82s`; Ruff reported `All checks passed!`; compileall exited 0; `pip check` found no broken requirements.
  - Final independent read-only re-review found no remaining Critical or Important findings; packaged Python modules matched current source bytecode and the Windows smoke passed.
  - Package: rebuilt `dist\OPCServiceMonitor\OPCServiceMonitor.exe` as `onedir + windowed + noupx`; EXE size 5,698,543 bytes, SHA-256 `E8EA3D33A5DC4A63253A68AC34D41C4265F5E9DCB730F2B9191C38270765D2B6`, and `qwindows.dll` size 997,688 bytes; the 229-file package totals 134,406,519 bytes.
  - Packaged smoke: passed from a non-source cwd with the real Windows Qt platform plugin, theme resource, three cards, and exact five tabs. Inventory found no `.env`, credentials, `.local`, APPClient, `node_modules`, backend venv, or foreign ICU DLL.
  - Visual QA: inspected `Docs\testing\artifacts\opc-service-monitor-main-window-2026-10-22.png` under real `qwindows`; Chinese text, status cards, tabs, controls, and table rendered correctly.
  - Guarded real check: ports 55440, 8001, and 5180 were all occupied by external ready instances, so lifecycle mutation was deliberately skipped. Read-only supervisor classification was `external/owned=false`; final temporary-store PG tail check yielded 119 redacted records and FTS query “PostgreSQL” returned 7 hits.
  - Documentation: updated root/module README, project context, AGENTS context, design status, documentation index, and dated verification record.
  - No Git commit is possible because `D:\OPC` is not a Git worktree.

