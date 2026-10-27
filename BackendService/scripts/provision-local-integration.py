"""Manage a durable, project-owned PostgreSQL 18 integration instance.

This opt-in helper never connects to port 5432, adopts an existing cluster,
deletes databases, changes existing passwords, or disables durability.
Credentials stay in ignored local files. Run from BackendService.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import secrets
import socket
import subprocess

import psycopg
from psycopg import sql
from psycopg.conninfo import make_conninfo


BACKEND = Path(__file__).resolve().parents[1]
ROOT = BACKEND / ".local" / "integration"
MARKER = "opc.local-integration.v1"
DBNAME = "opc_integration"


def command(binary: Path, *args: object) -> int:
    with (ROOT / "provision.log").open("ab") as output:
        result = subprocess.run(
            [str(binary), *map(str, args)], stdout=output, stderr=subprocess.STDOUT,
            stdin=subprocess.DEVNULL, timeout=90,
            creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0,
        )
    return result.returncode


def connect(state: dict, database: str = DBNAME):
    return psycopg.connect(make_conninfo(
        host="127.0.0.1", port=state["port"], dbname=database,
        user="postgres", password=state["admin_password"], connect_timeout=4,
    ), autocommit=True)


def initialize(state: dict) -> None:
    with connect(state, "postgres") as conn:
        exists = conn.execute("SELECT shobj_description(oid,'pg_database') FROM pg_database WHERE datname=%s", (DBNAME,)).fetchone()
        if exists:
            if exists[0] != MARKER:
                raise RuntimeError("Refusing an unmarked existing integration database")
        else:
            conn.execute(sql.SQL("CREATE DATABASE {} TEMPLATE template0 ENCODING 'UTF8'").format(sql.Identifier(DBNAME)))
            conn.execute(sql.SQL("COMMENT ON DATABASE {} IS {}").format(sql.Identifier(DBNAME), sql.Literal(MARKER)))
        if not conn.execute("SELECT 1 FROM pg_roles WHERE rolname='opc_app'").fetchone():
            conn.execute(sql.SQL("CREATE ROLE opc_app LOGIN PASSWORD {} NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION").format(sql.Literal(state["app_password"])))
        conn.execute(sql.SQL("REVOKE ALL ON DATABASE {} FROM PUBLIC").format(sql.Identifier(DBNAME)))
        conn.execute(sql.SQL("GRANT CONNECT ON DATABASE {} TO opc_app").format(sql.Identifier(DBNAME)))
        conn.execute(sql.SQL("ALTER DATABASE {} SET timezone TO 'UTC'").format(sql.Identifier(DBNAME)))
    with connect(state) as conn, conn.transaction():
        conn.execute("SELECT pg_advisory_xact_lock(184920,11)")
        conn.execute("REVOKE ALL ON SCHEMA public FROM PUBLIC")
        conn.execute("CREATE SCHEMA IF NOT EXISTS opc AUTHORIZATION postgres")
        conn.execute("REVOKE ALL ON SCHEMA opc FROM PUBLIC")
        conn.execute("""CREATE TABLE IF NOT EXISTS opc.schema_migrations (
            version text PRIMARY KEY, checksum text NOT NULL CHECK(checksum ~ '^[0-9a-f]{64}$'),
            applied_at timestamptz NOT NULL DEFAULT now())""")
        applied = dict(conn.execute("SELECT version,checksum FROM opc.schema_migrations").fetchall())
        migrations = sorted((BACKEND.parent / "DB" / "migrations").glob("*.sql"))
        actual = {p.stem: hashlib.sha256(p.read_bytes()).hexdigest() for p in migrations}
        if any(actual.get(version) != checksum for version, checksum in applied.items()):
            raise RuntimeError("Applied migration checksum mismatch; refusing to change history")
        for migration in migrations:
            if migration.stem not in applied:
                conn.execute(migration.read_text(encoding="utf-8-sig"))
                conn.execute("INSERT INTO opc.schema_migrations(version,checksum) VALUES (%s,%s)", (migration.stem, actual[migration.stem]))
        conn.execute("REVOKE ALL ON ALL TABLES IN SCHEMA opc FROM PUBLIC")
        conn.execute("REVOKE ALL ON ALL SEQUENCES IN SCHEMA opc FROM PUBLIC")
        conn.execute("REVOKE ALL ON ALL FUNCTIONS IN SCHEMA opc FROM PUBLIC")
        conn.execute("GRANT USAGE ON SCHEMA opc TO opc_app")
        conn.execute("GRANT SELECT ON ALL TABLES IN SCHEMA opc TO opc_app")
        conn.execute("GRANT USAGE,SELECT ON ALL SEQUENCES IN SCHEMA opc TO opc_app")
        conn.execute("GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA opc TO opc_app")
        for (table,) in conn.execute("SELECT tablename FROM pg_tables WHERE schemaname='opc'").fetchall():
            if table not in {"schema_migrations", "roles", "service_types", "development_platforms", "development_types", "audit_events"}:
                conn.execute(sql.SQL("GRANT INSERT,UPDATE ON opc.{} TO opc_app").format(sql.Identifier(table)))
        conn.execute("GRANT INSERT ON opc.audit_events TO opc_app")
        conn.execute("GRANT DELETE ON opc.request_drafts,opc.draft_files TO opc_app")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["start", "stop", "status"], default="start", nargs="?")
    parser.add_argument("--port", type=int, default=55440)
    parser.add_argument("--postgres-bin", default=r"C:\Program Files\PostgreSQL\18\bin")
    args = parser.parse_args()
    if args.port == 5432 or not 1024 <= args.port <= 65535:
        parser.error("Only a dedicated, non-5432 port is supported")
    binaries = Path(args.postgres_bin)
    extension = ".exe" if os.name == "nt" else ""
    pg_ctl = binaries / ("pg_ctl" + extension)
    initdb = binaries / ("initdb" + extension)
    if " 18." not in subprocess.check_output([str(initdb), "--version"], text=True):
        raise RuntimeError("PostgreSQL 18 is required")
    state_path = ROOT / "instance.json"
    data = ROOT / "data"
    env_path = BACKEND / ".env"
    if state_path.exists():
        state = json.loads(state_path.read_text(encoding="utf-8"))
        if state.get("marker") != MARKER or state.get("port") != args.port:
            raise RuntimeError("Instance marker/port mismatch")
    else:
        if args.action != "start":
            print("Integration instance has not been created")
            return
        if ROOT.exists() or env_path.exists():
            raise RuntimeError("Refusing to overwrite existing local directory or .env")
        with socket.socket() as probe:
            probe.bind(("127.0.0.1", args.port))
        ROOT.mkdir(parents=True)
        state = {"marker": MARKER, "port": args.port, "admin_password": secrets.token_urlsafe(36), "app_password": secrets.token_urlsafe(36)}
        state_path.write_text(json.dumps(state), encoding="utf-8")
        if os.name != "nt":
            state_path.chmod(0o600)
    if not data.exists() and args.action != "start":
        print("Integration cluster has not been initialized; no data changed")
        return
    if not data.exists():
        password_file = ROOT / "initial-password"
        password_file.write_text(state["admin_password"], encoding="ascii")
        try:
            if command(initdb, "-D", data, "-U", "postgres", "-A", "scram-sha-256", "--pwfile", password_file, "--encoding=UTF8", "--locale-provider=builtin", "--builtin-locale=C.UTF-8"):
                raise RuntimeError("initdb failed; see .local/integration/provision.log")
        finally:
            password_file.unlink(missing_ok=True)
        with (data / "postgresql.conf").open("a", encoding="utf-8") as config:
            config.write(f"\nlisten_addresses='127.0.0.1'\nport={args.port}\nmax_connections=40\n")
    running = command(pg_ctl, "-D", data, "status") == 0
    if args.action == "stop":
        if running and command(pg_ctl, "-D", data, "-m", "fast", "-w", "stop"):
            raise RuntimeError("Stop failed; see provision.log")
        print("Integration PostgreSQL stopped; all data retained")
        return
    if args.action == "status":
        print(f"Integration PostgreSQL {'running' if running else 'stopped'} at 127.0.0.1:{args.port}/{DBNAME}")
        return
    app_url = f"postgresql://opc_app:{state['app_password']}@127.0.0.1:{args.port}/{DBNAME}"
    if env_path.exists() and f"OPC_DATABASE_URL={app_url}" not in env_path.read_text(encoding="utf-8"):
        raise RuntimeError("Existing .env belongs to another configuration; refusing overwrite")
    if not running and command(pg_ctl, "-D", data, "-l", ROOT / "postgres.log", "-w", "start"):
        raise RuntimeError("Start failed; see provision.log")
    initialize(state)
    if not env_path.exists():
        with env_path.open("x", encoding="utf-8") as config:
            config.write(f"OPC_DATABASE_URL={app_url}\nOPC_STORAGE_ROOT=.local/files\nOPC_HALL_AUDIENCE=internal\nOPC_ASSIGNMENT_MODE=disabled\nOPC_DOCS_ENABLED=true\n")
        if os.name != "nt":
            env_path.chmod(0o600)
    with psycopg.connect(app_url) as conn:
        role = conn.execute("SELECT current_user,rolsuper,rolcreatedb,rolcreaterole FROM pg_roles WHERE rolname=current_user").fetchone()
        if role[1:] != (False, False, False):
            raise RuntimeError("Application role must be restricted")
    print(f"Durable PostgreSQL 18 ready at 127.0.0.1:{args.port}/{DBNAME}; restricted opc_app; credentials in ignored .env")


if __name__ == "__main__":
    try:
        main()
    except psycopg.Error as exc:
        raise SystemExit(f"Database setup failed (SQLSTATE {exc.sqlstate or 'connection'}); credentials omitted") from None
