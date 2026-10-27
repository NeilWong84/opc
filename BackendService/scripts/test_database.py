"""Run real integration tests in an isolated, disposable PostgreSQL 18 cluster.

Never connects to the developer's port 5432 or adopts an existing database.
The application role is deliberately not the cluster owner/superuser.
"""
from __future__ import annotations

import argparse
import hashlib
import os
from pathlib import Path
import secrets
import shutil
import socket
import subprocess
import sys
import uuid


BACKEND = Path(__file__).resolve().parents[1]
PROJECT = BACKEND.parent
TEST_ROOT = BACKEND / ".test-postgres"
MARKER = "opc.disposable-integration-tests.v1"


def available_port(preferred: int) -> int:
    with socket.socket() as listener:
        try:
            listener.bind(("127.0.0.1", preferred))
        except OSError:
            listener.bind(("127.0.0.1", 0))
        port = listener.getsockname()[1]
    if port == 5432:
        raise RuntimeError("The integration harness must never use port 5432")
    return port


def run_postgres(binary: Path, *args: str, log: Path) -> None:
    # Windows postgres descendants can retain PIPE handles after pg_ctl exits;
    # a real log file avoids waiting forever for inherited pipe EOF.
    with log.open("ab") as stream:
        result = subprocess.run(
            [str(binary), *map(str, args)], stdout=stream, stderr=subprocess.STDOUT,
            stdin=subprocess.DEVNULL,
            creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0,
            timeout=90,
        )
    if result.returncode:
        raise RuntimeError(f"{binary.name} failed; diagnostics: {log}")


def initialize_database(admin_url: str, database_name: str, app_password: str) -> None:
    import psycopg
    from psycopg import sql

    with psycopg.connect(admin_url, autocommit=True) as connection:
        connection.execute(sql.SQL("CREATE DATABASE {} WITH TEMPLATE template0 ENCODING 'UTF8'").format(sql.Identifier(database_name)))
        connection.execute(sql.SQL("COMMENT ON DATABASE {} IS {}").format(sql.Identifier(database_name), sql.Literal(MARKER)))
        connection.execute(sql.SQL("ALTER DATABASE {} SET timezone TO 'UTC'").format(sql.Identifier(database_name)))
        connection.execute(sql.SQL("REVOKE ALL ON DATABASE {} FROM PUBLIC").format(sql.Identifier(database_name)))
        connection.execute(sql.SQL("CREATE ROLE opc_test_app LOGIN PASSWORD {} NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION").format(sql.Literal(app_password)))
        connection.execute(sql.SQL("GRANT CONNECT ON DATABASE {} TO opc_test_app").format(sql.Identifier(database_name)))

    target_url = admin_url.rsplit("/", 1)[0] + "/" + database_name
    with psycopg.connect(target_url) as connection:
        connection.execute("REVOKE ALL ON SCHEMA public FROM PUBLIC")
        connection.execute("CREATE SCHEMA opc AUTHORIZATION postgres")
        connection.execute("REVOKE ALL ON SCHEMA opc FROM PUBLIC")
        # Same bootstrap schema_migrations definition as DB/bootstrap.sql.
        connection.execute("""CREATE TABLE opc.schema_migrations (
            version text PRIMARY KEY,
            checksum text NOT NULL CHECK (checksum ~ '^[0-9a-f]{64}$'),
            applied_at timestamptz NOT NULL DEFAULT now())""")
        for migration in sorted((PROJECT / "DB" / "migrations").glob("*.sql")):
            source = migration.read_bytes()
            connection.execute(source.decode("utf-8-sig"))
            connection.execute(
                "INSERT INTO opc.schema_migrations(version, checksum) VALUES (%s,%s)",
                (migration.stem, hashlib.sha256(source).hexdigest()),
            )
        connection.execute("REVOKE ALL ON ALL TABLES IN SCHEMA opc FROM PUBLIC")
        connection.execute("REVOKE ALL ON ALL SEQUENCES IN SCHEMA opc FROM PUBLIC")
        connection.execute("REVOKE ALL ON ALL FUNCTIONS IN SCHEMA opc FROM PUBLIC")
        connection.execute("GRANT USAGE ON SCHEMA opc TO opc_test_app")
        connection.execute("GRANT SELECT ON ALL TABLES IN SCHEMA opc TO opc_test_app")
        connection.execute("GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA opc TO opc_test_app")
        connection.execute("GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA opc TO opc_test_app")
        tables = connection.execute("SELECT tablename FROM pg_tables WHERE schemaname='opc'").fetchall()
        immutable_catalogs = {"schema_migrations", "roles", "service_types", "development_platforms", "development_types"}
        for (table,) in tables:
            if table not in immutable_catalogs:
                connection.execute(sql.SQL("GRANT INSERT ON opc.{} TO opc_test_app").format(sql.Identifier(table)))
            # PostgreSQL row locks require UPDATE rights even on immutable evidence;
            # append-only and one-way-closure triggers still reject illegal updates.
            if table not in immutable_catalogs | {"audit_events"}:
                connection.execute(sql.SQL("GRANT UPDATE ON opc.{} TO opc_test_app").format(sql.Identifier(table)))
        for table in ("request_drafts", "draft_files", "scope_files", "delivery_files", "idempotency_keys"):
            connection.execute(sql.SQL("GRANT DELETE ON opc.{} TO opc_test_app").format(sql.Identifier(table)))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--postgres-bin", default=os.environ.get("OPC_POSTGRES_BIN", r"C:\Program Files\PostgreSQL\18\bin"))
    parser.add_argument("--port", type=int, default=55439)
    parser.add_argument("--keep-cluster", action="store_true", help="Keep the stopped cluster for diagnostics")
    args, pytest_args = parser.parse_known_args()
    if pytest_args and pytest_args[0] == "--":
        pytest_args.pop(0)
    postgres_bin = Path(args.postgres_bin).resolve()
    extension = ".exe" if os.name == "nt" else ""
    initdb = postgres_bin / ("initdb" + extension)
    pg_ctl = postgres_bin / ("pg_ctl" + extension)
    if not initdb.is_file() or not pg_ctl.is_file():
        parser.error("PostgreSQL 18 initdb/pg_ctl are required; set --postgres-bin")
    version = subprocess.run([str(initdb), "--version"], capture_output=True, text=True, check=True).stdout
    if " 18." not in version:
        parser.error("This project requires PostgreSQL 18")
    port = available_port(args.port)
    unique = uuid.uuid4().hex
    cluster_root = (TEST_ROOT / unique).resolve()
    cluster_root.mkdir(parents=True)
    marker_path = cluster_root / "disposable.marker"
    marker_path.write_text(MARKER, encoding="utf-8")
    data_dir = cluster_root / "data"
    diagnostics = cluster_root / "harness.log"
    password_path = cluster_root / "initial-password"
    admin_password = secrets.token_hex(24)
    app_password = secrets.token_hex(24)
    password_path.write_text(admin_password, encoding="ascii")
    started = False
    stopped = False
    try:
        run_postgres(initdb, "-D", data_dir, "-U", "postgres", "-A", "scram-sha-256", "--pwfile", password_path,
                     "--encoding=UTF8", "--locale-provider=builtin", "--builtin-locale=C.UTF-8", log=diagnostics)
        password_path.unlink()
        with (data_dir / "postgresql.conf").open("a", encoding="utf-8") as config:
            config.write(f"\nlisten_addresses='127.0.0.1'\nport={port}\nmax_connections=40\nfsync=off\nsynchronous_commit=off\n")
        run_postgres(pg_ctl, "-D", data_dir, "-l", cluster_root / "postgres.log", "-w", "start", log=diagnostics)
        started = True
        database_name = "opc_test_" + unique[:16]
        admin_base = f"postgresql://postgres:{admin_password}@127.0.0.1:{port}"
        initialize_database(admin_base + "/postgres", database_name, app_password)
        environment = os.environ.copy()
        environment["PYTHONIOENCODING"] = "utf-8"
        environment["PYTHONUTF8"] = "1"
        environment["OPC_TEST_DATABASE_URL"] = f"postgresql://opc_test_app:{app_password}@127.0.0.1:{port}/{database_name}"
        environment["OPC_TEST_ADMIN_DATABASE_URL"] = admin_base + "/" + database_name
        environment["OPC_TEST_DATABASE_MARKER"] = MARKER
        print(f"Isolated PostgreSQL 18 integration target: 127.0.0.1:{port}/{database_name}", flush=True)
        command = [sys.executable, "-m", "pytest", *(pytest_args or ["-q"])]
        return subprocess.run(command, cwd=BACKEND, env=environment).returncode
    finally:
        if password_path.exists():
            password_path.unlink()
        if started:
            try:
                run_postgres(pg_ctl, "-D", data_dir, "-m", "fast", "-w", "stop", log=diagnostics)
                stopped = True
            except RuntimeError:
                print(f"Cluster stop failed; retained for inspection: {cluster_root}", file=sys.stderr)
        else:
            stopped = not (data_dir / "postmaster.pid").exists()
        if stopped and not args.keep_cluster:
            # Refuse recursive removal unless both the exact workspace child and marker match.
            if cluster_root.parent != TEST_ROOT.resolve() or marker_path.read_text(encoding="utf-8") != MARKER:
                raise RuntimeError("Refusing cleanup of an unverified test cluster path")
            shutil.rmtree(cluster_root)
        elif stopped:
            print(f"Stopped cluster retained: {cluster_root}")


if __name__ == "__main__":
    raise SystemExit(main())
