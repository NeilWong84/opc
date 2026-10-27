"""Explicit local provisioning and first administrator creation. No default credentials."""
import argparse
from getpass import getpass
from pathlib import Path
import secrets

import psycopg
from psycopg import sql
from psycopg.conninfo import make_conninfo
from psycopg.rows import dict_row

from .auth import hash_password, RegisterInput
from .config import Settings
from .database import Database


def configure():
    target = Path(".env")
    if target.exists():
        raise SystemExit(".env 已存在；为避免覆盖现有凭据，本命令拒绝覆盖，请按 README 手动配置。")
    password = getpass("本机 PostgreSQL postgres 密码（不显示、不保存维护密码）：")
    url = make_conninfo(host="127.0.0.1", port=5432, dbname="opc_dev", user="postgres", password=password)
    app_password = secrets.token_urlsafe(36)
    with psycopg.connect(url, row_factory=dict_row) as conn:
        marker = conn.execute("SELECT shobj_description(oid,'pg_database') AS marker FROM pg_database WHERE datname=current_database()").fetchone()
        if marker["marker"] != "opc.local-development.v1":
            raise SystemExit("目标 opc_dev 不具备项目本地数据库标记，已拒绝操作。")
        if conn.execute("SELECT 1 FROM pg_roles WHERE rolname='opc_app'").fetchone():
            raise SystemExit("opc_app 角色已存在，不重设既有密码；请手动将该角色连接配置到 .env。")
        if conn.execute("SELECT count(*) AS count FROM opc.schema_migrations").fetchone()["count"] < 6:
            raise SystemExit("数据库迁移不足，请先执行 DB/scripts/Initialize-Database.ps1。")
        conn.execute(sql.SQL("CREATE ROLE opc_app LOGIN PASSWORD {} NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION").format(sql.Literal(app_password)))
        conn.execute("GRANT CONNECT ON DATABASE opc_dev TO opc_app")
        conn.execute("GRANT USAGE ON SCHEMA opc TO opc_app")
        conn.execute("GRANT SELECT ON ALL TABLES IN SCHEMA opc TO opc_app")
        conn.execute("GRANT USAGE,SELECT ON ALL SEQUENCES IN SCHEMA opc TO opc_app")
        tables = conn.execute("SELECT tablename FROM pg_tables WHERE schemaname='opc' AND tablename NOT IN ('schema_migrations','roles','service_types','development_platforms','development_types','audit_events')").fetchall()
        for row in tables:
            conn.execute(sql.SQL("GRANT INSERT,UPDATE ON opc.{} TO opc_app").format(sql.Identifier(row["tablename"])))
        conn.execute("GRANT INSERT ON opc.audit_events TO opc_app")
        conn.execute("GRANT DELETE ON opc.request_drafts,opc.draft_files TO opc_app")
        conn.execute("GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA opc TO opc_app")
        # Write before commit so a filesystem failure rolls back the role as well.
        with target.open("x", encoding="utf-8") as config:
            config.write(f"OPC_DATABASE_URL=postgresql://opc_app:{app_password}@127.0.0.1:5432/opc_dev\n")
            config.write("OPC_HALL_AUDIENCE=internal\nOPC_ASSIGNMENT_MODE=disabled\nOPC_DOCS_ENABLED=true\n")
    print("已为 opc_dev 创建受限 opc_app 角色并写入忽略的 .env。未创建业务账号，未触及 Accounts。")


def bootstrap_admin():
    settings = Settings()
    email = input("首个管理员邮箱：").strip()
    name = input("显示名：").strip()
    password = getpass("管理员密码（至少12字符）：")
    if password != getpass("再次输入管理员密码："):
        raise SystemExit("两次密码不一致。")
    body = RegisterInput(email=email, display_name=name, password=password)
    with Database(settings.database_url).transaction("bootstrap-administrator") as conn:
        conn.execute("SELECT pg_advisory_xact_lock(184920,10)")
        if conn.execute("SELECT 1 FROM opc.account_roles WHERE role_code='administrator' AND revoked_at IS NULL").fetchone():
            raise SystemExit("已有管理员；后续账号请由现有管理员通过管理 API 创建。")
        row = conn.execute("INSERT INTO opc.accounts(email,display_name) VALUES (%s,%s) RETURNING id", (str(body.email), name)).fetchone()
        conn.execute("SELECT set_config('opc.actor_id',%s,true)", (str(row["id"]),))
        conn.execute("INSERT INTO opc.password_credentials(account_id,password_hash) VALUES (%s,%s)", (row["id"], hash_password(password)))
        conn.execute("INSERT INTO opc.account_roles(account_id,role_code,granted_by,reason) VALUES (%s,'administrator',%s,'本地显式初始化首个管理员')", (row["id"], row["id"]))
    print("管理员已建立。请使用 /api/v1/admin/auth/login 登录；没有默认密码。")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["configure-local-db", "bootstrap-admin"])
    args = parser.parse_args()
    try:
        configure() if args.command == "configure-local-db" else bootstrap_admin()
    except psycopg.Error as exc:
        raise SystemExit(f"数据库操作失败（SQLSTATE {exc.sqlstate or 'connection'}）；未输出密码或连接串。") from None


if __name__ == "__main__":
    main()
