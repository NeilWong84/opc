"""HTTP authorization and lifecycle checks against real PostgreSQL constraints."""
from __future__ import annotations

from uuid import uuid4
from pathlib import Path

import psycopg
import pytest


pytestmark = pytest.mark.integration


@pytest.mark.parametrize('name', ['requirements.docx', 'fields.xlsx', 'screens.pptx', 'sample.csv', 'workflow.pdf'])
def test_real_document_previews_recheck_original_permissions(integration_context, name):
    ctx = integration_context
    content = (Path(__file__).resolve().parents[2] / 'APPClient/assets/references' / name).read_bytes()
    file = upload(ctx, 'customer', name, content)
    url = f"/api/v1/mobile/files/{file['id']}/preview"
    assert ctx.client.get(url, headers=ctx.headers['customer']).status_code == 409
    inspect(ctx, file)
    response = ctx.client.get(url, headers=ctx.headers['customer'])
    assert response.status_code == 200, response.text[:200]
    assert response.headers['content-type'] == 'application/pdf'
    assert response.content.startswith(b'%PDF-')
    assert ctx.client.get(url, headers=ctx.headers['stranger']).status_code == 404
    # 缓存存在也不能绕过原件新的安全状态。
    metadata = call(ctx, 'GET', f"/admin/files/{file['id']}")
    call(ctx, 'POST', f"/admin/files/{file['id']}/inspection", payload={
        'expected_version': metadata['row_version'], 'decision': 'rejected',
        'reason': 'Synthetic fixture: exercise revocation after a real preview conversion.'})
    assert ctx.client.get(url, headers=ctx.headers['customer']).status_code == 409


def test_audio_preview_and_original_download_keep_actual_bytes(integration_context):
    import io
    import wave
    ctx = integration_context
    data = io.BytesIO()
    with wave.open(data, 'wb') as audio:
        audio.setparams((1, 2, 8000, 800, 'NONE', 'not compressed'))
        audio.writeframes(b'\0\0' * 800)
    content = data.getvalue()
    file = upload(ctx, 'customer', 'voice.wav', content)
    inspect(ctx, file)
    preview = ctx.client.get(f"/api/v1/mobile/files/{file['id']}/preview", headers=ctx.headers['customer'])
    assert preview.status_code == 200
    assert preview.headers['content-type'] == 'audio/wav'
    assert preview.content == content
    original = ctx.client.get(f"/api/v1/mobile/files/{file['id']}/download", headers=ctx.headers['customer'])
    assert original.content == content


def call(context, method, path, actor="admin", *, status=200, payload=None, key=None):
    headers = dict(context.headers[actor]) if actor else {}
    if key:
        headers["Idempotency-Key"] = key
    response = context.client.request(method, "/api/v1" + path, headers=headers, json=payload)
    assert response.status_code == status, f"{method} {path}: {response.status_code} {response.text}"
    return response.json() if response.content else None


def submit(context, **overrides):
    payload = {"original_description": "顧客の予約管理を行う開発システムが必要です。非公開の顧客原文。",
               "timing_text": "2026年11月中", "budget_text": "予算は要相談", "file_ids": []}
    payload.update(overrides)
    return call(context, "POST", "/mobile/requests", "customer", status=201,
                payload=payload, key=uuid4().hex)


def prepare_scope(context, request_record, **overrides):
    payload = {"expected_version": request_record["row_version"], "title": "予約管理開発",
               "public_summary": "日本国内の予約管理システムを開発します。", "category": "Web",
               "goal": "予約の重複を防ぐ", "included_scope": "一覧と登録", "excluded_scope": "決済",
               "deliverables": ["固定ソースコード", "操作説明", "テスト報告"],
               "acceptance_criteria": ["予約が保存される"], "duration_text": "2週間",
               "revision_terms": "合意範囲内の修正", "file_ids": []}
    payload.update(overrides)
    return call(context, "POST", f"/admin/requests/{request_record['id']}/scopes", status=201, payload=payload)


def approve_and_publish(context, record):
    for kind in ("compliance", "technical"):
        record = call(context, "POST", f"/admin/requests/{record['id']}/reviews", status=201, payload={
            "expected_version": record["row_version"], "scope_version": record["current_scope_version"],
            "kind": kind, "decision": "approved", "reason": f"isolated test {kind} evidence"})
    return call(context, "POST", f"/admin/requests/{record['id']}/publish", status=201, payload={
        "expected_version": record["row_version"], "scope_version": record["current_scope_version"],
        "reason": "Human-reviewed publication in disposable test database"})


def published_request(context):
    return approve_and_publish(context, prepare_scope(context, submit(context)))


def confirmed_engagement(context):
    record = published_request(context)
    engagement = call(context, "POST", "/admin/engagements", status=201, payload={
        "request_id": record["id"], "expected_version": record["row_version"],
        "provider_id": context.actors["provider"]["id"], "terms": "双方が確認する試験用合意範囲",
        "reason": "Previously confirmed relationship recorded for integration verification", "quoted_amount": 100000}, key=uuid4().hex)
    for actor in ("customer", "provider"):
        engagement = call(context, "POST", f"/mobile/engagements/{engagement['engagement_id']}/agreements/1/confirm", actor,
                          payload={"expected_version": engagement["row_version"]})
    assert engagement["status"] == "executing"
    return record, engagement


def test_project_filters_apply_before_pagination_and_preserve_permissions(integration_context):
    ctx = integration_context
    first, _ = confirmed_engagement(ctx)
    second, _ = confirmed_engagement(ctx)
    for actor in ('customer', 'provider'):
        perspective = f'perspective={actor}&'
        for path, prefix in (('/mobile/engagements', perspective), ('/mobile/threads', '')):
            rows = call(ctx, 'GET', f"{path}?{prefix}request_id={first['id']}&limit=1", actor)['items']
            assert len(rows) == 1 and rows[0]['request_id'] == first['id']
            assert call(ctx, 'GET', f"{path}?{prefix}request_id={first['id']}&limit=1&offset=1", actor)['items'] == []
            rows = call(ctx, 'GET', f"{path}?{prefix}request_id={second['id']}", actor)['items']
            assert len(rows) == 1 and rows[0]['request_id'] == second['id']
    for path in ('/mobile/engagements', '/mobile/threads'):
        assert call(ctx, 'GET', f"{path}?request_id={first['id']}", 'stranger')['items'] == []
        assert call(ctx, 'GET', f'{path}?request_id={uuid4()}', 'customer')['items'] == []
        call(ctx, 'GET', f'{path}?request_id=invalid', 'customer', status=422)


def deliver(context, engagement, key=None):
    payload = {"expected_version": engagement["row_version"], "agreement_version": 1,
               "note": "今回の固定版を提出します", "repository_url": "https://example.com/repository",
               "source_commit": "a" * 40, "source_archive_ref": "test-only archive evidence",
               "guide_text": "起動手順と環境変数サンプルを同梱", "test_report_text": "テスト証跡を確認対象として提出",
               "files": []}
    result = call(context, "POST", f"/mobile/engagements/{engagement['engagement_id']}/deliveries", "provider",
                  status=201, payload=payload, key=key or uuid4().hex)
    return result, payload


def test_restricted_database_role_and_migration_history(integration_database_url):
    with psycopg.connect(integration_database_url) as connection:
        assert connection.execute("SELECT count(*) FROM opc.schema_migrations").fetchone()[0] >= 6
        for statement in ("CREATE TABLE opc.forbidden_test(id int)",
                          "UPDATE opc.schema_migrations SET checksum=checksum",
                          "DELETE FROM opc.audit_events", "UPDATE opc.roles SET name_ja=name_ja"):
            with pytest.raises(psycopg.errors.InsufficientPrivilege), connection.transaction():
                connection.execute(statement)


def test_pending_intake_files_are_private_and_visible_in_operator_queue(integration_context):
    ctx = integration_context
    response = ctx.client.post("/api/v1/mobile/files", headers=ctx.headers["customer"],
                               files={"file": ("new-requirement.md", b"# pending private input", "text/markdown")})
    assert response.status_code == 201
    file = response.json()
    fid = file["id"]
    assert file["scan_status"] == "pending"
    mine = call(ctx, "GET", "/mobile/files?scan_status=pending", "customer")["items"]
    assert [f["id"] for f in mine] == [fid]
    assert call(ctx, "GET", "/mobile/files", "stranger")["items"] == []
    queue = call(ctx, "GET", "/admin/files?scan_status=pending")["items"]
    assert [f["id"] for f in queue] == [fid]
    assert all("storage_key" not in f for f in queue)
    call(ctx, "PUT", "/mobile/draft", "customer", payload={"expected_version": 0, "file_ids": [fid]})
    record = submit(ctx, file_ids=[fid])
    assert record["private_files"][0]["scan_status"] == "pending"
    for actor in ("customer", "admin"):
        audience = "admin" if actor == "admin" else "mobile"
        call(ctx, "GET", f"/{audience}/files/{fid}/download", actor, status=409)
    call(ctx, "GET", f"/mobile/files/{fid}", "provider", status=404)
    # Pending files cannot enter a reviewed/public scope; intake visibility is
    # deliberately different from publication/download clearance.
    scope_body = {"expected_version": record["row_version"], "title": "private upload", "public_summary": "private upload",
                  "category": "Web", "goal": "read", "included_scope": "read", "excluded_scope": "write",
                  "deliverables": ["code"], "acceptance_criteria": ["read"], "duration_text": "2w",
                  "revision_terms": "agreed", "file_ids": [fid]}
    call(ctx, "POST", f"/admin/requests/{record['id']}/scopes", status=422, payload=scope_body)
    call(ctx, "POST", f"/admin/files/{fid}/inspection", payload={
        "expected_version": file["row_version"], "decision": "rejected", "reason": "synthetic rejection fixture"})
    call(ctx, "POST", "/mobile/requests", "customer", status=422, payload={
        "original_description": "Another request with a rejected file", "timing_text": "later", "budget_text": "TBD", "file_ids": [fid]}, key=uuid4().hex)


def test_cooperation_has_shared_thread_integer_quote_and_reviewed_references(integration_context):
    ctx = integration_context
    upload = ctx.client.post("/api/v1/admin/files", headers=ctx.headers["admin"],
                             files={"file": ("agreed-scope.md", b"# agreed reference", "text/markdown")}).json()
    call(ctx, "POST", f"/admin/files/{upload['id']}/inspection", payload={
        "expected_version": upload["row_version"], "decision": "clean", "reason": "known synthetic literal checked"})
    record = approve_and_publish(ctx, prepare_scope(ctx, submit(ctx), file_ids=[upload["id"]]))
    engagement = call(ctx, "POST", "/admin/engagements", status=201, payload={
        "request_id": record["id"], "expected_version": record["row_version"], "provider_id": ctx.actors["provider"]["id"],
        "terms": "agreed synthetic scope", "reason": "fixture", "quoted_amount": 100000}, key=uuid4().hex)
    eid = engagement["engagement_id"]
    thread = call(ctx, "GET", "/mobile/threads", "customer")["items"][0]
    assert thread["engagement_id"] == eid
    assert call(ctx, "GET", "/mobile/threads", "provider")["items"][0]["id"] == thread["id"]
    assert call(ctx, "GET", "/mobile/threads", "stranger")["items"] == []
    assert call(ctx, "POST", "/admin/threads", status=201, payload={
        "request_id": record["id"], "kind": "customer_project", "engagement_id": eid})["id"] == thread["id"]
    call(ctx, "POST", f"/mobile/threads/{thread['id']}/messages", "provider", status=201,
         payload={"body": "双方共享的真实会话", "client_message_id": str(uuid4())})
    messages = call(ctx, "GET", f"/mobile/threads/{thread['id']}/messages", "customer")["items"]
    assert len(messages) == 1
    assert messages[0]["author_id"] == ctx.actors["provider"]["id"]
    assert messages[0]["author_name"] == "provider"
    assert "email" not in messages[0] and "roles" not in messages[0]
    call(ctx, "GET", f"/mobile/threads/{thread['id']}/messages", "stranger", status=404)
    # New scope withdraws the hall publication, but the immutable agreement
    # retains its reviewed reference and both parties can still fetch its bytes.
    current = call(ctx, "GET", f"/admin/requests/{record['id']}")
    prepare_scope(ctx, current)
    for actor in ("customer", "provider"):
        detail = call(ctx, "GET", f"/mobile/engagements/{eid}", actor)
        assert detail["engagement"]["customer_id"] == ctx.actors["customer"]["id"]
        assert type(detail["agreements"][0]["quoted_amount"]) is int
        assert detail["agreements"][0]["scope"]["reference_files"][0]["file_id"] == upload["id"]
        response = ctx.client.get(f"/api/v1/mobile/files/{upload['id']}/download", headers=ctx.headers[actor])
        assert response.status_code == 200 and response.content == b"# agreed reference"


def test_demo_seed_is_durable_idempotent_and_does_not_reset_changed_password(durable_context, tmp_path, monkeypatch):
    from app import demo_seed
    from app.auth import verify_password
    ctx = durable_context
    settings = ctx.client.app.state.settings
    name = ctx.connection.info.dbname
    # The test harness owns this disposable marked database; the production CLI
    # whitelist remains limited to the two explicitly named local databases.
    monkeypatch.setitem(demo_seed.MARKERS, name, "opc.disposable-integration-tests.v1")
    manifest_path = tmp_path / "demo-credentials.json"
    first = demo_seed.seed_demo(settings, manifest_path)
    customer = first["accounts"]["customer"]
    login = ctx.client.post("/api/v1/mobile/auth/login", json={"email": customer["email"], "password": customer["password"]})
    assert login.status_code == 200
    changed = "Changed-local-demo-password-2026!"
    response = ctx.client.post("/api/v1/mobile/auth/password", headers={"Authorization": "Bearer " + login.json()["access_token"]},
                               json={"current_password": customer["password"], "new_password": changed})
    assert response.status_code == 200
    def snapshot():
        return {table: ctx.connection.execute(f"SELECT count(*) AS n FROM opc.{table}").fetchone()["n"]
                for table in ("accounts", "requests", "engagements", "deliveries", "files", "auth_sessions", "audit_events")}
    before = snapshot()
    second = demo_seed.seed_demo(settings, manifest_path)
    assert second == first and snapshot() == before
    credential = ctx.connection.execute("SELECT password_hash FROM opc.password_credentials WHERE account_id=%s", (customer["id"],)).fetchone()
    assert verify_password(credential["password_hash"], changed)
    assert not verify_password(credential["password_hash"], customer["password"])
    assert len(first["scenarios"]) == 4
    assert ctx.connection.execute("SELECT status FROM opc.engagements WHERE id=%s",
                                  (first["scenarios"]["awaiting_acceptance"]["engagement_id"],)).fetchone()["status"] == "awaiting_acceptance"


def test_authentication_audience_and_immediate_authorization_revocation(integration_context):
    ctx = integration_context
    call(ctx, "GET", "/mobile/hall", None, status=401)
    call(ctx, "GET", "/admin/requests", "customer", status=401)
    call(ctx, "GET", "/mobile/hall", "admin", status=401)
    call(ctx, "GET", "/mobile/hall", "customer", status=403)
    assert call(ctx, "GET", "/mobile/hall", "provider")["items"] == []
    call(ctx, "POST", f"/admin/accounts/{ctx.actors['provider']['id']}/provider-authorization/revoke",
         payload={"reason": "Withdraw internal permission during active session"})
    call(ctx, "GET", "/mobile/hall", "provider", status=403)
    call(ctx, "POST", "/mobile/auth/logout", "customer")
    call(ctx, "GET", "/mobile/auth/me", "customer", status=401)


def test_private_intake_review_publication_and_revision_boundaries(integration_context):
    ctx = integration_context
    submitted = submit(ctx)
    rid = submitted["id"]
    call(ctx, "GET", f"/mobile/requests/{rid}", "stranger", status=404)
    call(ctx, "GET", f"/mobile/hall/{rid}", "provider", status=404)
    assert call(ctx, "GET", "/mobile/hall", "provider")["items"] == []
    scope = prepare_scope(ctx, submitted)
    call(ctx, "POST", f"/admin/requests/{rid}/publish", status=409, payload={
        "expected_version": scope["row_version"], "scope_version": scope["current_scope_version"], "reason": "premature"})
    published = approve_and_publish(ctx, scope)
    hall = call(ctx, "GET", "/mobile/hall", "provider")
    assert [item["request_id"] for item in hall["items"]] == [rid]
    assert "非公開の顧客原文" not in str(hall)
    assert "customer_id" not in hall["items"][0]
    detail = call(ctx, "GET", f"/mobile/requests/{rid}", "customer")
    assert all("reason" not in review and "reviewer_id" not in review for review in detail["reviews"])
    # A changed scope is a new immutable version and invalidates hall visibility.
    revised = prepare_scope(ctx, published, title="予約管理開発・改訂版")
    assert revised["current_scope_version"] == published["current_scope_version"] + 1
    assert call(ctx, "GET", "/mobile/hall", "provider")["items"] == []
    call(ctx, "GET", f"/mobile/hall/{rid}", "provider", status=404)
    call(ctx, "POST", f"/admin/requests/{rid}/publish", status=409, payload={
        "expected_version": revised["row_version"], "scope_version": published["current_scope_version"], "reason": "stale scope"})


def test_request_idempotency_returns_original_and_rejects_changed_payload(integration_context):
    ctx = integration_context
    payload = {"original_description": "予約管理の開発について相談したいです。", "timing_text": "11月", "budget_text": "相談", "file_ids": []}
    key = uuid4().hex
    first = call(ctx, "POST", "/mobile/requests", "customer", status=201, payload=payload, key=key)
    replay = call(ctx, "POST", "/mobile/requests", "customer", status=201, payload=payload, key=key)
    assert replay == first
    call(ctx, "POST", "/mobile/requests", "customer", status=409,
         payload={**payload, "budget_text": "変更した予算"}, key=key)
    count = ctx.connection.execute("SELECT count(*) AS n FROM opc.requests").fetchone()["n"]
    assert count == 1


def test_full_delivery_qa_release_revision_and_explicit_acceptance(integration_context):
    ctx = integration_context
    record, engagement = confirmed_engagement(ctx)
    eid = engagement["engagement_id"]
    assert call(ctx, "GET", "/mobile/hall", "provider")["items"] == []
    first_key = uuid4().hex
    first, first_payload = deliver(ctx, engagement, first_key)
    replay = call(ctx, "POST", f"/mobile/engagements/{eid}/deliveries", "provider", status=201,
                  payload=first_payload, key=first_key)
    assert replay == first
    did = first["delivery_id"]
    call(ctx, "POST", f"/mobile/engagements/{eid}/deliveries/{did}/acceptance", "customer", status=409,
         payload={"expected_version": first["row_version"], "decision": "accepted", "feedback": ""}, key=uuid4().hex)
    qa = call(ctx, "POST", f"/admin/engagements/{eid}/deliveries/{did}/review", payload={
        "expected_version": first["row_version"], "decision": "approved", "evidence": "Test source, guide, and report reviewed by fixture reviewer"})
    released = call(ctx, "POST", f"/admin/engagements/{eid}/deliveries/{did}/publish",
                    payload={"expected_version": qa["row_version"]})
    call(ctx, "POST", f"/mobile/engagements/{eid}/deliveries/{did}/acceptance", "stranger", status=404,
         payload={"expected_version": released["row_version"], "decision": "accepted", "feedback": ""}, key=uuid4().hex)
    revised = call(ctx, "POST", f"/mobile/engagements/{eid}/deliveries/{did}/acceptance", "customer", payload={
        "expected_version": released["row_version"], "decision": "revision_requested", "feedback": "予約重複時の表示を修正してください"}, key=uuid4().hex)
    assert revised["status"] == "revision"
    second, _ = deliver(ctx, {**revised, "engagement_id": eid})
    assert second["delivery_version"] == 2
    call(ctx, "POST", f"/mobile/engagements/{eid}/deliveries/{did}/acceptance", "customer", status=409,
         payload={"expected_version": second["row_version"], "decision": "accepted", "feedback": ""}, key=uuid4().hex)
    did2 = second["delivery_id"]
    qa2 = call(ctx, "POST", f"/admin/engagements/{eid}/deliveries/{did2}/review", payload={
        "expected_version": second["row_version"], "decision": "approved", "evidence": "Revised evidence reviewed"})
    released2 = call(ctx, "POST", f"/admin/engagements/{eid}/deliveries/{did2}/publish",
                     payload={"expected_version": qa2["row_version"]})
    accepted = call(ctx, "POST", f"/mobile/engagements/{eid}/deliveries/{did2}/acceptance", "customer", payload={
        "expected_version": released2["row_version"], "decision": "accepted", "feedback": "確認しました"}, key=uuid4().hex)
    assert accepted["status"] == "completed"
    stored = ctx.connection.execute("SELECT status,closed_at FROM opc.engagements WHERE id=%s", (eid,)).fetchone()
    assert stored["status"] == "completed" and stored["closed_at"] is not None
    audit = ctx.connection.execute("SELECT count(*) AS n FROM opc.audit_events WHERE application_actor_id=%s", (ctx.actors["customer"]["id"],)).fetchone()
    assert audit["n"] > 0


def upload(context, actor, filename, content):
    audience = "admin" if actor == "admin" else "mobile"
    response = context.client.post(f"/api/v1/{audience}/files", headers=context.headers[actor],
                                   files={"file": (filename, content, "text/plain")})
    assert response.status_code == 201, response.text
    result = response.json()
    assert "storage_key" not in result
    return result


def inspect(context, file):
    return call(context, "POST", f"/admin/files/{file['id']}/inspection", payload={
        "expected_version": file["row_version"], "decision": "clean", "reason": "Synthetic UTF-8 test fixture inspected"})


def test_files_require_check_ownership_and_current_explicit_publication(integration_context):
    ctx = integration_context
    private_bytes = "この原文添付は公開しません。".encode()
    reference_bytes = "明示的に公開した参照資料。".encode()
    private = upload(ctx, "customer", "private-original.txt", private_bytes)
    reference = upload(ctx, "admin", "reviewed-reference.txt", reference_bytes)
    call(ctx, "GET", f"/mobile/files/{private['id']}/download", "customer", status=409)
    inspect(ctx, private)
    inspect(ctx, reference)
    call(ctx, "GET", f"/mobile/files/{private['id']}", "stranger", status=404)
    call(ctx, "POST", "/mobile/requests", "stranger", status=422, key=uuid4().hex, payload={
        "original_description": "別のお客様のファイルを添付できてはいけません。", "timing_text": "11月", "budget_text": "相談",
        "file_ids": [private["id"]]})
    scope = prepare_scope(ctx, submit(ctx, file_ids=[private["id"]]), file_ids=[reference["id"]])
    rid = scope["id"]
    call(ctx, "GET", f"/mobile/files/{reference['id']}", "provider", status=404)
    draft_detail = call(ctx, "GET", f"/mobile/requests/{rid}", "customer")
    assert draft_detail["scope"]["reference_files"] == []
    published = approve_and_publish(ctx, scope)
    hall = call(ctx, "GET", f"/mobile/hall/{rid}", "provider")
    assert len(hall["references"]) == 1
    assert "private-original.txt" not in str(hall)
    for actor in ("provider", "customer"):
        downloaded = ctx.client.get(f"/api/v1/mobile/files/{reference['id']}/download", headers=ctx.headers[actor])
        assert downloaded.status_code == 200, downloaded.text
        assert downloaded.content == reference_bytes
        assert downloaded.headers["cache-control"] == "no-store"
    assert call(ctx, "GET", f"/mobile/files/{reference['id']}/preview", "provider")["text"] == reference_bytes.decode()
    call(ctx, "GET", f"/mobile/files/{private['id']}", "provider", status=404)
    call(ctx, "POST", f"/admin/requests/{rid}/publication/withdraw", payload={
        "expected_version": published["row_version"], "reason": "Withdraw file reference version"})
    call(ctx, "GET", f"/mobile/files/{reference['id']}", "provider", status=404)
    own_download = ctx.client.get(f"/api/v1/mobile/files/{private['id']}/download", headers=ctx.headers["customer"])
    assert own_download.content == private_bytes


def test_long_japanese_text_preview_truncates_at_utf8_boundary_and_rejects_invalid_bytes(integration_context):
    ctx = integration_context
    long_text = upload(ctx, "customer", "long-japanese.txt", ("あ" * 30000).encode("utf-8"))
    inspect(ctx, long_text)
    preview = call(ctx, "GET", f"/mobile/files/{long_text['id']}/preview", "customer")
    assert preview["state"] == "ready"
    assert preview["truncated"] is True
    assert preview["text"] == "あ" * (65536 // 3)
    invalid_text = upload(ctx, "customer", "invalid-utf8.txt", b"valid prefix\xff" + b"a" * 70000)
    inspect(ctx, invalid_text)
    invalid = call(ctx, "GET", f"/mobile/files/{invalid_text['id']}/preview", "customer")
    assert invalid["state"] == "unsupported"
    assert invalid["error_code"] == "TEXT_ENCODING_UNSUPPORTED"


def test_consultations_internal_messages_and_notification_isolation(integration_context):
    ctx = integration_context
    first = published_request(ctx)
    rid = first["id"]
    provider_thread = call(ctx, "POST", f"/mobile/requests/{rid}/consultation", "provider")["id"]
    customer_thread = call(ctx, "POST", f"/mobile/requests/{rid}/consultation", "customer")["id"]
    assert provider_thread != customer_thread
    assert ctx.connection.execute("SELECT count(*) AS n FROM opc.engagements").fetchone()["n"] == 0
    message = {"body": "公開範囲について相談します。", "client_message_id": str(uuid4())}
    first_message = call(ctx, "POST", f"/mobile/threads/{provider_thread}/messages", "provider", status=201, payload=message)
    assert call(ctx, "POST", f"/mobile/threads/{provider_thread}/messages", "provider", status=201, payload=message) == first_message
    call(ctx, "POST", f"/mobile/threads/{provider_thread}/messages", "provider", status=409,
         payload={**message, "body": "同じIDで異なるメッセージ"})
    call(ctx, "GET", f"/mobile/threads/{provider_thread}/messages", "customer", status=404)
    call(ctx, "GET", f"/mobile/threads/{provider_thread}/messages", "stranger", status=404)
    assert len(call(ctx, "GET", f"/mobile/threads/{provider_thread}/messages", "provider")["items"]) == 1
    internal = call(ctx, "POST", "/admin/threads", status=201, payload={"request_id": rid, "kind": "internal"})["id"]
    call(ctx, "POST", f"/admin/threads/{internal}/messages", status=201,
         payload={"body": "内部専用メモ", "client_message_id": str(uuid4())})
    for actor in ("customer", "provider", "stranger"):
        call(ctx, "GET", f"/mobile/threads/{internal}/messages", actor, status=404)
        assert internal not in [item["id"] for item in call(ctx, "GET", "/mobile/threads", actor)["items"]]
    second = published_request(ctx)
    second_thread = call(ctx, "POST", f"/mobile/requests/{second['id']}/consultation", "provider")["id"]
    call(ctx, "POST", f"/mobile/threads/{second_thread}/messages", "provider", status=409, payload=message)
    call(ctx, "POST", f"/admin/requests/{rid}/publication/withdraw", payload={
        "expected_version": first["row_version"], "reason": "Withdraw consultation scope"})
    call(ctx, "GET", f"/mobile/threads/{provider_thread}/messages", "provider", status=404)
    notifications = call(ctx, "GET", "/mobile/notifications", "customer")["items"]
    assert notifications
    call(ctx, "POST", f"/mobile/notifications/{notifications[0]['id']}/read", "stranger", status=404)
    assert call(ctx, "POST", f"/mobile/notifications/{notifications[0]['id']}/read", "customer")["read_at"]
    assert call(ctx, "GET", "/mobile/notifications", "stranger")["items"] == []


def test_clarification_creates_new_original_and_invalidates_old_review(integration_context):
    ctx = integration_context
    published = published_request(ctx)
    rid = published["id"]
    asked = call(ctx, "POST", f"/admin/requests/{rid}/clarifications", status=201, payload={
        "expected_version": published["row_version"], "question": "予約の重複条件を説明してください。"})
    assert asked["intake_status"] == "needs_info"
    assert call(ctx, "GET", "/mobile/hall", "provider")["total"] == 0
    questions = call(ctx, "GET", f"/mobile/requests/{rid}/clarifications", "customer")["items"]
    qid = questions[0]["id"]
    call(ctx, "POST", f"/mobile/requests/{rid}/clarifications/{qid}/answer", "stranger", status=404,
         payload={"expected_version": asked["row_version"], "answer": "部外者の回答"})
    answered = call(ctx, "POST", f"/mobile/requests/{rid}/clarifications/{qid}/answer", "customer", payload={
        "expected_version": asked["row_version"], "answer": "同じ担当者に重なる時間帯は予約できません。"})
    assert answered["current_request_version"] == 2
    assert answered["current_scope_version"] is None
    assert answered["intake_status"] == "submitted"
    call(ctx, "POST", f"/mobile/requests/{rid}/clarifications/{qid}/answer", "customer", status=409,
         payload={"expected_version": answered["row_version"], "answer": "過去の回答の上書き"})
    scope = prepare_scope(ctx, answered)
    assert scope["current_scope_version"] == 2
    call(ctx, "POST", f"/admin/requests/{rid}/publish", status=409, payload={
        "expected_version": scope["row_version"], "scope_version": 2, "reason": "Cannot reuse original approvals"})
    republished = approve_and_publish(ctx, scope)
    assert republished["current_request_version"] == 2
    history = ctx.connection.execute("SELECT count(*) AS n FROM opc.review_decisions WHERE request_id=%s", (rid,)).fetchone()
    assert history["n"] == 4


def test_disabled_account_loses_current_session_and_cannot_login(integration_context):
    from conftest import TEST_PASSWORD

    ctx = integration_context
    profile = call(ctx, "GET", "/mobile/auth/me", "customer")
    call(ctx, "PUT", f"/admin/accounts/{ctx.actors['customer']['id']}/status", payload={
        "expected_version": profile["row_version"], "status": "disabled", "reason": "Integration verifies immediate session revocation"})
    call(ctx, "GET", "/mobile/auth/me", "customer", status=401)
    response = ctx.client.post("/api/v1/mobile/auth/login", json={"email": ctx.actors["customer"]["email"], "password": TEST_PASSWORD})
    assert response.status_code == 401
    remaining = ctx.connection.execute("SELECT count(*) AS n FROM opc.auth_sessions WHERE account_id=%s AND revoked_at IS NULL",
                                       (ctx.actors["customer"]["id"],)).fetchone()
    assert remaining["n"] == 0


def parallel_posts(context, path, payloads, keys, actor):
    from concurrent.futures import ThreadPoolExecutor
    from threading import Barrier

    start = Barrier(2)

    def request(index):
        start.wait(timeout=5)
        return context.client.post("/api/v1" + path, json=payloads[index],
                                   headers={**context.headers[actor], "Idempotency-Key": keys[index]})

    with ThreadPoolExecutor(max_workers=2) as executor:
        futures = [executor.submit(request, index) for index in range(2)]
        return [future.result(timeout=20) for future in futures]


def test_two_real_connections_serialize_same_idempotency_key(durable_context):
    ctx = durable_context
    payload = {"original_description": "同時送信されても一つの依頼だけを作成します。", "timing_text": "11月", "budget_text": "相談", "file_ids": []}
    key = uuid4().hex
    responses = parallel_posts(ctx, "/mobile/requests", [payload, payload], [key, key], "customer")
    assert [response.status_code for response in responses] == [201, 201], [response.text for response in responses]
    assert responses[0].json() == responses[1].json()
    assert ctx.connection.execute("SELECT count(*) AS n FROM opc.requests").fetchone()["n"] == 1
    assert ctx.connection.execute("SELECT count(*) AS n FROM opc.idempotency_keys").fetchone()["n"] == 1


def test_two_real_connections_cannot_create_two_active_cooperations(durable_context):
    ctx = durable_context
    record = published_request(ctx)
    payload = {"request_id": record["id"], "expected_version": record["row_version"],
               "provider_id": ctx.actors["provider"]["id"], "terms": "確定済み関係を記録する試験",
               "reason": "Concurrent confirmed relationship records must produce one active cooperation"}
    responses = parallel_posts(ctx, "/admin/engagements", [payload, payload], [uuid4().hex, uuid4().hex], "admin")
    assert sorted(response.status_code for response in responses) == [201, 409], [response.text for response in responses]
    assert ctx.connection.execute("SELECT count(*) AS n FROM opc.engagements WHERE closed_at IS NULL").fetchone()["n"] == 1
    assert ctx.connection.execute("SELECT count(*) AS n FROM opc.assignments WHERE ended_at IS NULL").fetchone()["n"] == 1
    assert ctx.connection.execute("SELECT count(*) AS n FROM opc.hall_requests").fetchone()["n"] == 0


def test_thread_pagination_filters_withdrawn_consultations_before_limit(durable_context):
    ctx = durable_context
    older = published_request(ctx)
    visible_thread = call(ctx, "POST", f"/mobile/requests/{older['id']}/consultation", "provider")["id"]
    newer = published_request(ctx)
    hidden_thread = call(ctx, "POST", f"/mobile/requests/{newer['id']}/consultation", "provider")["id"]
    call(ctx, "POST", f"/admin/requests/{newer['id']}/publication/withdraw", payload={
        "expected_version": newer["row_version"], "reason": "The most recent consultation is no longer visible"})
    page = call(ctx, "GET", "/mobile/threads?limit=1&offset=0", "provider")
    assert [thread["id"] for thread in page["items"]] == [visible_thread]
    assert hidden_thread not in str(page)
