"""Real PostgreSQL fixtures; every test rolls back all of its business data."""
from __future__ import annotations

from contextlib import contextmanager
from dataclasses import dataclass, field
import os
from typing import Any
from uuid import uuid4

import psycopg
from psycopg.conninfo import conninfo_to_dict, make_conninfo
from psycopg.rows import dict_row
import pytest


TEST_MARKER = "opc.disposable-integration-tests.v1"
TEST_PASSWORD = "Integration-only-password-2026!"


@pytest.fixture(scope="session")
def integration_database_url() -> str:
    url = os.environ.get("OPC_TEST_DATABASE_URL")
    if not url:
        pytest.skip("Real PostgreSQL integration tests: run scripts/test-postgres.ps1")
    settings = conninfo_to_dict(url)
    if (settings.get("host") != "127.0.0.1" or settings.get("port", "5432") == "5432"
            or not settings.get("dbname", "").startswith("opc_test_")):
        pytest.fail("Refusing an integration database outside the isolated opc_test_ cluster")
    with psycopg.connect(url, row_factory=dict_row) as connection:
        identity = connection.execute("""SELECT current_database() AS database,
            shobj_description(d.oid,'pg_database') AS marker, r.rolsuper AS superuser,
            r.rolcreatedb AS createdb, r.rolcreaterole AS createrole
            FROM pg_database d JOIN pg_roles r ON r.rolname=current_user
            WHERE d.datname=current_database()""").fetchone()
        if identity["marker"] != TEST_MARKER:
            pytest.fail("Refusing a database without the disposable integration-test marker")
        if identity["superuser"] or identity["createdb"] or identity["createrole"]:
            pytest.fail("HTTP integration tests must use the restricted application role")
        assert connection.info.server_version // 10000 == 18
    return url


class RollbackDatabase:
    """Use real non-owner SQL, with request savepoints inside one test transaction."""

    def __init__(self, connection: psycopg.Connection, url: str):
        self.connection = connection
        self.url = url

    @contextmanager
    def transaction(self, correlation_id: str = ""):
        with self.connection.transaction():
            self.connection.execute("SET LOCAL statement_timeout = '15s'")
            self.connection.execute("SET LOCAL lock_timeout = '5s'")
            self.connection.execute("SET LOCAL timezone = 'UTC'")
            self.connection.execute("SELECT set_config('opc.correlation_id', %s, true)", (correlation_id,))
            self.connection.execute("SELECT set_config('opc.actor_id', '', true)")
            yield self.connection
            # A real request commits here. Force deferred foreign keys/constraint
            # triggers now rather than hiding violations in the final rollback.
            self.connection.execute("SET CONSTRAINTS ALL IMMEDIATE")
            self.connection.execute("SET CONSTRAINTS ALL DEFERRED")


@dataclass
class IntegrationContext:
    client: Any
    connection: psycopg.Connection
    actors: dict[str, dict]
    headers: dict[str, dict[str, str]] = field(repr=False)


def seed_actors(connection):
    from argon2 import PasswordHasher

    actors = {name: {"id": str(uuid4()), "email": f"{name}-{uuid4().hex}@example.com"}
              for name in ("admin", "customer", "stranger", "provider")}
    encoded = PasswordHasher().hash(TEST_PASSWORD)
    for name, actor in actors.items():
        connection.execute("INSERT INTO opc.accounts(id,email,display_name) VALUES (%s,%s,%s)",
                           (actor["id"], actor["email"], name))
        connection.execute("INSERT INTO opc.password_credentials(account_id,password_hash) VALUES (%s,%s)",
                           (actor["id"], encoded))
    for name, actor in actors.items():
        roles = (["administrator", "operator", "compliance_reviewer", "technical_reviewer", "quality_reviewer"]
                 if name == "admin" else ["provider"] if name == "provider" else ["customer"])
        for role in roles:
            connection.execute("""INSERT INTO opc.account_roles(account_id,role_code,granted_by,reason)
                VALUES (%s,%s,%s,'isolated integration fixture')""", (actor["id"], role, actors["admin"]["id"]))
    connection.execute("""INSERT INTO opc.provider_authorizations(account_id,granted_by,reason)
        VALUES (%s,%s,'isolated integration fixture')""", (actors["provider"]["id"], actors["admin"]["id"]))
    return actors


def login_headers(client, actors):
    headers = {}
    for name, actor in actors.items():
        audience = "admin" if name == "admin" else "mobile"
        response = client.post(f"/api/v1/{audience}/auth/login", json={"email": actor["email"], "password": TEST_PASSWORD})
        assert response.status_code == 200, response.text
        token = response.json()["access_token"]
        headers[name] = {"Authorization": f"Bearer {token}"}
    return headers


@pytest.fixture
def integration_context(integration_database_url, tmp_path):
    from fastapi.testclient import TestClient
    from app.config import Settings
    from app.main import create_app

    connection = psycopg.connect(integration_database_url, row_factory=dict_row)
    connection.execute("BEGIN")
    try:
        actors = seed_actors(connection)
        settings = Settings(_env_file=None, database_url=integration_database_url, storage_root=tmp_path / "files", preview_root=tmp_path / "previews",
                            hall_audience="internal", assignment_mode="record_confirmed")
        app = create_app(settings=settings, database=RollbackDatabase(connection, integration_database_url))
        with TestClient(app) as client:
            yield IntegrationContext(client, connection, actors, login_headers(client, actors))
    finally:
        connection.rollback()
        connection.close()


@pytest.fixture
def durable_context(integration_database_url, tmp_path):
    """A separately marked clone allows committed requests on concurrent connections."""
    from fastapi.testclient import TestClient
    from psycopg import sql
    from app.config import Settings
    from app.main import create_app

    admin_url = os.environ.get("OPC_TEST_ADMIN_DATABASE_URL")
    if not admin_url:
        pytest.skip("Concurrent test database creation requires the isolated harness admin connection")
    app_options = conninfo_to_dict(integration_database_url)
    admin_options = conninfo_to_dict(admin_url)
    if any(app_options[key] != admin_options[key] for key in ("host", "port", "dbname")):
        pytest.fail("Test administrator must target exactly the verified isolated test cluster")
    template_name = app_options["dbname"]
    database_name = "opc_test_concurrent_" + uuid4().hex[:16]
    admin_maintenance_url = make_conninfo(**{**admin_options, "dbname": "postgres"})
    new_url = make_conninfo(**{**app_options, "dbname": database_name})
    with psycopg.connect(admin_maintenance_url, autocommit=True) as admin:
        admin.execute(sql.SQL("CREATE DATABASE {} WITH TEMPLATE {}").format(sql.Identifier(database_name), sql.Identifier(template_name)))
        admin.execute(sql.SQL("COMMENT ON DATABASE {} IS {}").format(sql.Identifier(database_name), sql.Literal(TEST_MARKER)))
        admin.execute(sql.SQL("REVOKE ALL ON DATABASE {} FROM PUBLIC").format(sql.Identifier(database_name)))
        admin.execute(sql.SQL("GRANT CONNECT ON DATABASE {} TO opc_test_app").format(sql.Identifier(database_name)))
    try:
        with psycopg.connect(new_url, row_factory=dict_row) as seed:
            actors = seed_actors(seed)
        settings = Settings(_env_file=None, database_url=new_url, storage_root=tmp_path / "files",
                            hall_audience="internal", assignment_mode="record_confirmed")
        # No injected database: every request uses the production Database transaction.
        app = create_app(settings=settings)
        with TestClient(app) as client, psycopg.connect(new_url, row_factory=dict_row, autocommit=True) as inspect:
            yield IntegrationContext(client, inspect, actors, login_headers(client, actors))
    finally:
        with psycopg.connect(admin_maintenance_url, autocommit=True) as admin:
            marker = admin.execute("SELECT shobj_description(oid,'pg_database') FROM pg_database WHERE datname=%s", (database_name,)).fetchone()
            if not database_name.startswith("opc_test_concurrent_") or not marker or marker[0] != TEST_MARKER:
                pytest.fail("Refusing cleanup of an unverified concurrent-test database")
            admin.execute(sql.SQL("DROP DATABASE {} WITH (FORCE)").format(sql.Identifier(database_name)))
