"""Explicit initializer for a marked cloud test database. No local/demo data import."""
import json
from hashlib import sha256
import os
from pathlib import Path

import psycopg
from app.auth import RegisterInput, hash_password
from psycopg import sql

MARKER = 'opc.cloud-test.v1'
NAME = os.environ.get('OPC_PG_DATABASE', 'opc_test')
admin_password = Path('/run/secrets/pg-admin').read_text().strip()
app_password = Path('/run/secrets/pg-app').read_text().strip()
bootstrap = json.loads(Path('/run/secrets/bootstrap-admin').read_text())
paths = sorted(Path('/app/migrations').glob('*.sql'))
manifest = {path.stem: sha256(path.read_bytes()).hexdigest() for path in paths}
if not manifest or '008_request_classifications' not in manifest:
    raise SystemExit('Incomplete migration manifest')


def connect(database):
    return psycopg.connect(host='postgres', dbname=database, user='postgres', password=admin_password, autocommit=True)


try:
    with connect('postgres') as conn:
        if conn.info.server_version // 10000 != 18:
            raise RuntimeError('PostgreSQL 18 required')
        conn.execute('SELECT pg_advisory_lock(184920,21)')
        existing = conn.execute("SELECT shobj_description(oid,'pg_database') FROM pg_database WHERE datname=%s", (NAME,)).fetchone()
        if existing and existing[0] != MARKER:
            raise RuntimeError('Refusing an unmarked database')
        if not existing:
            conn.execute(sql.SQL("CREATE DATABASE {} OWNER postgres TEMPLATE template0 ENCODING 'UTF8' LOCALE_PROVIDER builtin BUILTIN_LOCALE 'C.UTF-8'").format(sql.Identifier(NAME)))
            conn.execute(sql.SQL('COMMENT ON DATABASE {} IS {}').format(sql.Identifier(NAME), sql.Literal(MARKER)))
        with conn.transaction():
            if not conn.execute("SELECT 1 FROM pg_roles WHERE rolname='opc_app'").fetchone():
                conn.execute(sql.SQL('CREATE ROLE opc_app LOGIN PASSWORD {} NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION').format(sql.Literal(app_password)))
            conn.execute(sql.SQL('REVOKE ALL ON DATABASE {} FROM PUBLIC').format(sql.Identifier(NAME)))
            conn.execute(sql.SQL('GRANT CONNECT ON DATABASE {} TO opc_app').format(sql.Identifier(NAME)))
            conn.execute(sql.SQL("ALTER DATABASE {} SET timezone TO 'UTC'").format(sql.Identifier(NAME)))

    with connect(NAME) as conn:
        conn.execute('SELECT pg_advisory_lock(184920,22)')
        with conn.transaction():
            conn.execute('REVOKE ALL ON SCHEMA public FROM PUBLIC')
            conn.execute('CREATE SCHEMA IF NOT EXISTS opc AUTHORIZATION postgres')
            conn.execute('REVOKE ALL ON SCHEMA opc FROM PUBLIC')
            conn.execute("CREATE TABLE IF NOT EXISTS opc.schema_migrations(version text PRIMARY KEY, checksum text NOT NULL CHECK(checksum ~ '^[0-9a-f]{64}$'), applied_at timestamptz NOT NULL DEFAULT now())")
            conn.execute('REVOKE ALL ON opc.schema_migrations FROM PUBLIC')
            conn.execute('ALTER DEFAULT PRIVILEGES IN SCHEMA opc REVOKE ALL ON TABLES FROM PUBLIC')
            conn.execute('ALTER DEFAULT PRIVILEGES IN SCHEMA opc REVOKE ALL ON SEQUENCES FROM PUBLIC')
        applied = dict(conn.execute('SELECT version,checksum FROM opc.schema_migrations').fetchall())
        if any(manifest.get(version) != digest for version, digest in applied.items()):
            raise RuntimeError('Migration history checksum mismatch or unknown migration')
        for path in paths:
            if path.stem in applied:
                continue
            if any(version > path.stem for version in applied):
                raise RuntimeError('Refusing an out-of-order migration')
            with conn.transaction():
                conn.execute(path.read_text(encoding='utf-8-sig'))
                conn.execute('REVOKE ALL ON ALL TABLES IN SCHEMA opc FROM PUBLIC')
                conn.execute('REVOKE ALL ON ALL SEQUENCES IN SCHEMA opc FROM PUBLIC')
                conn.execute('REVOKE ALL ON ALL FUNCTIONS IN SCHEMA opc FROM PUBLIC')
                conn.execute('INSERT INTO opc.schema_migrations(version,checksum) VALUES (%s,%s)', (path.stem, manifest[path.stem]))
            print(f'Applied {path.stem}', flush=True)
        with conn.transaction():
            conn.execute('GRANT USAGE ON SCHEMA opc TO opc_app')
            conn.execute('GRANT SELECT ON ALL TABLES IN SCHEMA opc TO opc_app')
            conn.execute('GRANT USAGE,SELECT ON ALL SEQUENCES IN SCHEMA opc TO opc_app')
            conn.execute('GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA opc TO opc_app')
            excluded = {'schema_migrations', 'roles', 'service_types', 'development_platforms', 'development_types', 'audit_events'}
            for (table,) in conn.execute("SELECT tablename FROM pg_tables WHERE schemaname='opc'"):
                if table not in excluded:
                    conn.execute(sql.SQL('GRANT INSERT,UPDATE ON opc.{} TO opc_app').format(sql.Identifier(table)))
            conn.execute('GRANT INSERT ON opc.audit_events TO opc_app')
            conn.execute('GRANT DELETE ON opc.request_drafts,opc.draft_files TO opc_app')
            conn.execute('SELECT pg_advisory_xact_lock(184920,10)')
            if not conn.execute("SELECT 1 FROM opc.account_roles WHERE role_code='administrator' AND revoked_at IS NULL").fetchone():
                body = RegisterInput(email=bootstrap['email'], display_name=bootstrap['display_name'], password=bootstrap['password'])
                account_id = conn.execute('INSERT INTO opc.accounts(email,display_name) VALUES (%s,%s) RETURNING id', (str(body.email), body.display_name)).fetchone()[0]
                conn.execute("SELECT set_config('opc.actor_id',%s,true)", (str(account_id),))
                conn.execute('INSERT INTO opc.password_credentials(account_id,password_hash) VALUES (%s,%s)', (account_id, hash_password(body.password.get_secret_value())))
                conn.execute("INSERT INTO opc.account_roles(account_id,role_code,granted_by,reason) VALUES (%s,'administrator',%s,'云测试环境显式初始化首个管理员')", (account_id, account_id))
                print('Initial administrator created; credentials retained in private secret file.')
    with psycopg.connect(host='postgres', dbname=NAME, user='opc_app', password=app_password) as conn:
        flags = conn.execute('SELECT rolsuper,rolcreatedb,rolcreaterole FROM pg_roles WHERE rolname=current_user').fetchone()
        if flags != (False, False, False):
            raise RuntimeError('Application role is not restricted')
        if conn.execute('SELECT count(*) FROM opc.schema_migrations').fetchone()[0] != len(manifest):
            raise RuntimeError('Incomplete migrations')
    print('Cloud test database ready; restricted application role verified.')
except psycopg.Error as error:
    raise SystemExit(f'Database initialization failed: SQLSTATE {error.sqlstate or "connection"}; credentials omitted') from None
