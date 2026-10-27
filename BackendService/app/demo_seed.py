"""Explicit local synthetic demo data, committed atomically without resetting users.

This is a development operator command, never an API or production startup hook.
Passwords are random and written only to the gitignored local manifest.
"""
from contextlib import contextmanager
from hashlib import sha256
from io import BytesIO
import json
from pathlib import Path
import secrets
from uuid import uuid4
from zipfile import ZipFile

from fastapi.testclient import TestClient
import psycopg
from psycopg.conninfo import conninfo_to_dict
from psycopg.rows import dict_row

from .auth import hash_password
from .config import Settings
from .main import create_app

SCHEMA = "opc.demo.v1"
MARKERS = {"opc_dev": "opc.local-development.v1", "opc_integration": "opc.local-integration.v1"}
REASON = "本机合成演示数据；仅验证联调，不代表真实客户授权、业务审核或生产服务"


def validate_target(url, identity):
    options = conninfo_to_dict(url)
    name = options.get("dbname")
    if options.get("host") != "127.0.0.1" or name not in MARKERS:
        raise ValueError("只允许本机 opc_dev/opc_integration，禁止远程、Accounts 或其他数据库")
    if identity["marker"] != MARKERS[name] or identity["superuser"] or identity["createdb"] or identity["createrole"]:
        raise ValueError("数据库标记不匹配或连接角色不是受限应用身份")
    return {"host": "127.0.0.1", "port": int(options.get("port", "5432")), "name": name, "marker": identity["marker"]}


def write_manifest(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(".pending.json")
    temporary.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    temporary.replace(path)


class SeedDatabase:
    """HTTP service savepoints inside a single explicitly committed seed transaction."""
    def __init__(self, connection):
        self.connection = connection

    @contextmanager
    def transaction(self, correlation_id=""):
        with self.connection.transaction():
            self.connection.execute("SELECT set_config('opc.actor_id','',true)")
            self.connection.execute("SELECT set_config('opc.correlation_id',%s,true)", (correlation_id,))
            yield self.connection
            self.connection.execute("SET CONSTRAINTS ALL IMMEDIATE")
            self.connection.execute("SET CONSTRAINTS ALL DEFERRED")


class DemoAPI:
    def __init__(self, client, accounts):
        self.client, self.headers = client, {}
        for name, account in accounts.items():
            audience = "admin" if name == "admin" else "mobile"
            result = self.call("POST", f"/{audience}/auth/login", None,
                               {"email": account["email"], "password": account["password"]})
            self.headers[name] = {"Authorization": "Bearer " + result["access_token"]}

    def call(self, method, path, actor="admin", payload=None, *, key=None, files=None):
        headers = dict(self.headers.get(actor, {}))
        if key:
            headers["Idempotency-Key"] = key
        response = self.client.request(method, "/api/v1" + path, headers=headers, json=payload, files=files)
        if response.status_code not in (200, 201):
            # Only code/path/status are logged, never tokens or request bodies.
            code = response.json().get("error", {}).get("code", "unknown")
            raise ValueError(f"演示初始化失败：{method} {path}: {response.status_code} {code}")
        return response.json()

    def upload_fixture(self, name, data, owner):
        record = self.call("POST", "/mobile/files", owner, files={"file": (name, data, "application/octet-stream")})
        if record["sha256"] != sha256(data).hexdigest() or record["size_bytes"] != len(data):
            raise ValueError("已知合成字节校验失败")
        record = self.call("POST", f"/admin/files/{record['id']}/inspection", payload={
            "expected_version": record["row_version"], "decision": "clean",
            "reason": f"合成 fixture：逐字节 SHA-256={record['sha256']} 与本脚本常量一致；内容由本脚本生成，无外部输入。未运行恶意软件扫描，不适用于未知用户文件。"})
        response = self.client.get(f"/api/v1/mobile/files/{record['id']}/download", headers=self.headers[owner])
        if response.status_code != 200 or response.content != data:
            raise ValueError("合成原文件真实下载字节校验失败")
        return record["id"]

    def logout(self):
        for name in self.headers:
            self.call("POST", "/admin/auth/logout" if name == "admin" else "/mobile/auth/logout", name)


def seed_scenarios(api, accounts):
    reference = api.upload_fixture("予約管理の要件.md", "# 合成联调资料\n予約一覧・重複防止・操作説明。\n真实内容通过私有文件接口下载。\n".encode(), "customer")
    source = BytesIO()
    with ZipFile(source, "w") as archive:
        archive.writestr("reservation.py", 'def is_available(existing, slot):\n    return slot not in existing\n')
        archive.writestr("README.md", "# Synthetic reservation fixture\nPython 3; no dependencies or credentials.\n")
    source_id = api.upload_fixture("reservation-source.zip", source.getvalue(), "provider")
    scenarios = {}
    names = {
        "pending_review": "要件の確認待ち", "published": "店舗予約管理ツール",
        "awaiting_confirmation": "在庫照会の改善", "awaiting_acceptance": "予約重複チェックの納品確認",
    }
    for name, title in names.items():
        record = api.call("POST", "/mobile/requests", "customer", {
            "original_description": f"【本机合成联调】{title}。日本国内向けの開発サービスを相談したいです。",
            "timing_text": "双方確認後 2 週間", "budget_text": "JPY 100,000（見積、支払処理なし）", "file_ids": [reference]}, key="demo-v1-request-" + name)
        rid = record["id"]
        scenario = scenarios[name] = {"request_id": rid}
        if name == "pending_review":
            api.call("POST", f"/admin/requests/{rid}/clarifications", payload={
                "expected_version": record["row_version"], "question": "ご利用人数と、予約一覧に必要な項目を教えてください。"})
            continue
        record = api.call("POST", f"/admin/requests/{rid}/scopes", payload={
            "expected_version": record["row_version"], "title": title,
            "public_summary": "日本国内向けの合成開発案件。実データの永続化・権限・納品の確認用。", "category": "業務ツール",
            "goal": "二重入力を減らす", "included_scope": "予約一覧と重複確認", "excluded_scope": "決済・本番運用",
            "deliverables": ["固定ソースコード", "起動説明", "検証記録"], "acceptance_criteria": ["約定したデータを保存・取得できる"],
            "duration_text": "双方確認後 2 週間", "revision_terms": "合意範囲内の修正。保守は別途確認。", "file_ids": [reference]})
        for kind in ("compliance", "technical"):
            record = api.call("POST", f"/admin/requests/{rid}/reviews", payload={
                "expected_version": record["row_version"], "scope_version": record["current_scope_version"],
                "kind": kind, "decision": "approved", "reason": REASON})
        record = api.call("POST", f"/admin/requests/{rid}/publish", payload={
            "expected_version": record["row_version"], "scope_version": record["current_scope_version"], "reason": REASON})
        if name == "published":
            continue
        engagement = api.call("POST", "/admin/engagements", payload={
            "request_id": rid, "expected_version": record["row_version"], "provider_id": accounts["provider"]["id"],
            "terms": "合成联调合作条款。双方确认范围后执行；不代表真实订单、收费或已确定接单机制。", "quoted_amount": 100000,
            "reason": REASON}, key="demo-v1-engagement-" + name)
        eid = scenario["engagement_id"] = engagement["engagement_id"]
        threads = api.call("GET", "/mobile/threads", "customer")["items"]
        thread_id = next(t["id"] for t in threads if t["engagement_id"] == eid)
        scenario["thread_id"] = thread_id
        api.call("POST", f"/mobile/threads/{thread_id}/messages", "provider", {
            "body": "こちらは本机合成联调のメッセージです。確認事項はこの会話に記録できます。", "client_message_id": str(uuid4())})
        if name == "awaiting_confirmation":
            continue
        for actor in ("customer", "provider"):
            engagement = api.call("POST", f"/mobile/engagements/{eid}/agreements/1/confirm", actor,
                                  {"expected_version": engagement["row_version"]})
        delivery = api.call("POST", f"/mobile/engagements/{eid}/deliveries", "provider", {
            "expected_version": engagement["row_version"], "agreement_version": 1,
            "note": "合成最小ソースの納品です。添付の内容をご確認ください。", "source_file_id": source_id,
            "guide_text": "ZIP を保存して展開。reservation.py に既存予約の重複判定関数を収録。Python 3、外部依存なし。",
            "test_report_text": "本脚本生成的合成源码已做常量内容与 SHA-256 下载比对；未执行客户代码，非生产功能验收。", "files": []},
            key="demo-v1-delivery-" + name)
        did = scenario["delivery_id"] = delivery["delivery_id"]
        reviewed = api.call("POST", f"/admin/engagements/{eid}/deliveries/{did}/review", payload={
            "expected_version": delivery["row_version"], "decision": "approved", "evidence": REASON + "；已知源码常量、无外部依赖或凭据，字节校验通过；非生产质检。"})
        api.call("POST", f"/admin/engagements/{eid}/deliveries/{did}/publish", payload={"expected_version": reviewed["row_version"]})
    return scenarios


def seed_demo(settings=None, manifest_path=Path(".local/demo-credentials.json")):
    settings = settings or Settings()
    manifest_path = Path(manifest_path)
    # Connection validation happens before any manifest mutation.
    with psycopg.connect(settings.database_url, row_factory=dict_row) as conn:
        identity = conn.execute("""SELECT shobj_description(d.oid,'pg_database') AS marker,
            r.rolsuper AS superuser,r.rolcreatedb AS createdb,r.rolcreaterole AS createrole
            FROM pg_database d JOIN pg_roles r ON r.rolname=current_user WHERE d.datname=current_database()""").fetchone()
        target = validate_target(settings.database_url, identity)
        conn.execute("SELECT pg_advisory_xact_lock(184920,20)")
        if manifest_path.exists():
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            if manifest.get("schema") != SCHEMA or manifest.get("database") != target:
                raise ValueError("既有演示凭据归属不匹配；拒绝覆盖")
        else:
            manifest = {"schema": SCHEMA, "database": target, "state": "preparing", "accounts": {
                name: {"id": str(uuid4()), "email": f"opc-demo-{name}@example.com", "password": secrets.token_urlsafe(24)}
                for name in ("admin", "customer", "provider")}, "scenarios": {}}
            write_manifest(manifest_path, manifest)
        accounts = manifest["accounts"]
        existing = conn.execute("SELECT id,email FROM opc.accounts WHERE id=ANY(%s::uuid[]) OR email_normalized=ANY(%s)",
                                ([a["id"] for a in accounts.values()], [a["email"] for a in accounts.values()])).fetchall()
        if existing:
            expected = {(a["id"], a["email"]) for a in accounts.values()}
            if {(str(a["id"]), a["email"]) for a in existing} != expected or manifest.get("state") != "ready":
                raise ValueError("发现不完整或冲突演示账号；不修改既有密码、角色或业务数据")
            for scenario in manifest["scenarios"].values():
                if not conn.execute("SELECT 1 FROM opc.requests WHERE id=%s", (scenario["request_id"],)).fetchone():
                    raise ValueError("演示业务记录已缺失，拒绝重建覆盖")
            return manifest
        for name, account in accounts.items():
            conn.execute("INSERT INTO opc.accounts(id,email,display_name) VALUES (%s,%s,%s)",
                         (account["id"], account["email"], {"admin": "联调运营", "customer": "デモ顧客", "provider": "内部開発担当"}[name]))
            conn.execute("SELECT set_config('opc.actor_id',%s,true)", (account["id"],))
            conn.execute("INSERT INTO opc.password_credentials(account_id,password_hash) VALUES (%s,%s)",
                         (account["id"], hash_password(account["password"])))
        for name, account in accounts.items():
            conn.execute("SELECT set_config('opc.actor_id',%s,true)", (accounts["admin"]["id"],))
            conn.execute("INSERT INTO opc.account_roles(account_id,role_code,granted_by,reason) VALUES (%s,%s,%s,%s)",
                         (account["id"], "administrator" if name == "admin" else name, accounts["admin"]["id"], REASON))
        conn.execute("INSERT INTO opc.provider_authorizations(account_id,granted_by,reason) VALUES (%s,%s,%s)",
                     (accounts["provider"]["id"], accounts["admin"]["id"], REASON))
        # The temporary in-process seed app can record these synthetic relationships;
        # it never rewrites .env or the live service's disabled assignment policy.
        app = create_app(settings.model_copy(update={"assignment_mode": "record_confirmed"}), SeedDatabase(conn))
        old_files = {str(row["storage_key"]) for row in conn.execute("SELECT storage_key FROM opc.files")}
        try:
            with TestClient(app) as client:
                api = DemoAPI(client, accounts)
                manifest["scenarios"] = seed_scenarios(api, accounts)
                api.logout()
            manifest["state"] = "ready"
            # If this write fails the database transaction also rolls back. If the
            # eventual DB commit fails, the next run sees no accounts and retries.
            write_manifest(manifest_path, manifest)
        except Exception:
            new_keys = {str(row["storage_key"]) for row in conn.execute("SELECT storage_key FROM opc.files")} - old_files
            from .files import storage_path
            for key in new_keys:
                storage_path(settings.storage_root, key).unlink(missing_ok=True)
            raise
    return manifest


def main():
    try:
        data = seed_demo()
    except (ValueError, psycopg.Error) as exc:
        message = str(exc) if isinstance(exc, ValueError) else "数据库操作失败；请检查受限应用连接（未输出连接串）"
        raise SystemExit(message) from None
    print(f"演示数据就绪：{len(data['accounts'])} 个账号，{len(data['scenarios'])} 个场景。凭据仅见 .local/demo-credentials.json；未输出密码。")


if __name__ == "__main__":
    main()
