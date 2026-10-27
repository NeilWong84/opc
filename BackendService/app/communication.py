from typing import Literal
from uuid import UUID
from fastapi import APIRouter, Query, Request

from .deps import ActorDep, TxDep, ensure_admin, ensure_provider
from .errors import DomainError
from .idempotency import idempotent
from .models import Input, Text
from .files import hall_allowed

router = APIRouter(tags=["会话、通知与运营"])


class MessageInput(Input):
    body: Text
    client_message_id: UUID


class ThreadInput(Input):
    request_id: UUID
    kind: Literal["customer_project", "internal"]
    engagement_id: UUID | None = None


def thread_access(conn, actor, thread, settings):
    if not thread:
        return False
    if actor.audience == "admin":
        return bool(actor.roles & {"administrator", "operator"})
    if thread["kind"] == "internal":
        return False
    req = conn.execute("SELECT customer_id FROM opc.requests WHERE id=%s", (thread["request_id"],)).fetchone()
    if thread["kind"] == "consultation":
        if thread["initiator_id"] != actor.id:
            return False
        if req["customer_id"] == actor.id:
            return True
        return hall_allowed(conn, actor, settings) and bool(conn.execute(
            "SELECT 1 FROM opc.hall_requests WHERE request_id=%s", (thread["request_id"],)).fetchone())
    if thread["kind"] == "negotiation":
        if req["customer_id"] == actor.id:
            return True
        if thread["initiator_id"] != actor.id:
            return False
        try:
            ensure_provider(conn, actor)
        except DomainError:
            return False
        return bool(conn.execute("""SELECT 1 FROM opc.hall_requests WHERE request_id=%s
            UNION ALL SELECT 1 FROM opc.assignments a JOIN opc.engagements e ON e.id=a.engagement_id
            WHERE e.request_id=%s AND a.provider_id=%s AND a.ended_at IS NULL""",
            (thread["request_id"], thread["request_id"], actor.id)).fetchone())
    if req["customer_id"] == actor.id:
        return True
    if not conn.execute("""SELECT 1 FROM opc.assignments WHERE engagement_id=%s
        AND provider_id=%s AND ended_at IS NULL""", (thread["engagement_id"], actor.id)).fetchone():
        return False
    try:
        ensure_provider(conn, actor)
        return True
    except DomainError:
        return False


def accessible_thread(conn, actor, thread_id, settings):
    row = conn.execute("SELECT * FROM opc.conversation_threads WHERE id=%s", (thread_id,)).fetchone()
    if not thread_access(conn, actor, row, settings):
        raise DomainError(404, "NOT_FOUND", "会话不存在或无权访问")
    return row


def participant(conn, thread_id, account_id, added_by):
    conn.execute("""INSERT INTO opc.thread_participants(thread_id,account_id,added_by)
        SELECT %s,%s,%s WHERE NOT EXISTS(SELECT 1 FROM opc.thread_participants
        WHERE thread_id=%s AND account_id=%s AND left_at IS NULL)""", (thread_id, account_id, added_by, thread_id, account_id))


def project_thread(conn, request_id, engagement_id, added_by):
    """Caller holds the request lock; reuse one project conversation per cooperation."""
    row = conn.execute("SELECT id FROM opc.conversation_threads WHERE engagement_id=%s AND kind='customer_project'",
                       (engagement_id,)).fetchone()
    if row:
        return row
    row = conn.execute("""INSERT INTO opc.conversation_threads(request_id,kind,engagement_id)
        VALUES (%s,'customer_project',%s) RETURNING id""", (request_id, engagement_id)).fetchone()
    req = conn.execute("SELECT customer_id FROM opc.requests WHERE id=%s", (request_id,)).fetchone()
    assignment = conn.execute("SELECT provider_id FROM opc.assignments WHERE engagement_id=%s AND ended_at IS NULL",
                              (engagement_id,)).fetchone()
    for account_id in {added_by, req["customer_id"], assignment["provider_id"] if assignment else added_by}:
        participant(conn, row["id"], account_id, added_by)
    return row


@router.post("/api/v1/mobile/requests/{request_id}/consultation", summary="创建本人咨询；不确定承接者")
def consultation(request_id: UUID, request: Request, actor: ActorDep, conn: TxDep):
    req = conn.execute("SELECT * FROM opc.requests WHERE id=%s FOR UPDATE", (request_id,)).fetchone()
    if not req or (req["customer_id"] != actor.id and (not hall_allowed(conn, actor, request.app.state.settings) or
        not conn.execute("SELECT 1 FROM opc.hall_requests WHERE request_id=%s", (request_id,)).fetchone())):
        raise DomainError(404, "NOT_FOUND", "需求不可访问")
    existing = conn.execute("SELECT id FROM opc.conversation_threads WHERE request_id=%s AND kind='consultation' AND initiator_id=%s", (request_id, actor.id)).fetchone()
    if existing:
        return existing
    row = conn.execute("""INSERT INTO opc.conversation_threads(request_id,kind,initiator_id)
        VALUES (%s,'consultation',%s) RETURNING id""", (request_id, actor.id)).fetchone()
    participant(conn, row["id"], actor.id, actor.id)
    return row


@router.post("/api/v1/admin/threads", status_code=201, summary="建立项目或内部会话；参与身份由服务端推导")
def create_thread(body: ThreadInput, actor: ActorDep, conn: TxDep):
    ensure_admin(actor, "operator")
    req = conn.execute("SELECT * FROM opc.requests WHERE id=%s FOR UPDATE", (body.request_id,)).fetchone()
    if not req:
        raise DomainError(404, "NOT_FOUND", "需求不存在")
    if body.kind == "customer_project" and not body.engagement_id:
        raise DomainError(422, "ENGAGEMENT_REQUIRED", "项目会话需要真实合作")
    if body.engagement_id and not conn.execute("SELECT 1 FROM opc.engagements WHERE id=%s AND request_id=%s", (body.engagement_id, body.request_id)).fetchone():
        raise DomainError(404, "NOT_FOUND", "合作不存在")
    if body.kind == "customer_project":
        return project_thread(conn, body.request_id, body.engagement_id, actor.id)
    row = conn.execute("""INSERT INTO opc.conversation_threads(request_id,kind,engagement_id)
        VALUES (%s,%s,%s) RETURNING id""", (body.request_id, body.kind, body.engagement_id)).fetchone()
    participant(conn, row["id"], actor.id, actor.id)
    if body.kind == "customer_project":
        participant(conn, row["id"], req["customer_id"], actor.id)
        assignment = conn.execute("SELECT provider_id FROM opc.assignments WHERE engagement_id=%s AND ended_at IS NULL", (body.engagement_id,)).fetchone()
        if assignment:
            participant(conn, row["id"], assignment["provider_id"], actor.id)
    return row


@router.get("/api/v1/mobile/threads", summary="当前账号有权访问的会话")
@router.get("/api/v1/admin/threads", summary="运营会话列表")
def threads(request: Request, actor: ActorDep, conn: TxDep, limit: int = Query(30, ge=1, le=100), offset: int = Query(0, ge=0),
            request_id: UUID | None = None):
    if actor.audience == "admin":
        ensure_admin(actor, "operator")
        rows = conn.execute("""SELECT * FROM opc.conversation_threads
            WHERE (%s::uuid IS NULL OR request_id=%s) ORDER BY created_at DESC,id LIMIT %s OFFSET %s""",
            (request_id, request_id, limit, offset)).fetchall()
    else:
        # Apply current visibility BEFORE pagination: hidden newer consultations must
        # not push a visible older project out of an apparently empty first page.
        provider_ok = False
        if "provider" in actor.roles:
            try:
                ensure_provider(conn, actor)
                provider_ok = True
            except DomainError:
                pass
        hall_ok = hall_allowed(conn, actor, request.app.state.settings)
        rows = conn.execute("""SELECT t.*,a.display_name AS initiator_name FROM opc.conversation_threads t JOIN opc.requests r ON r.id=t.request_id
            LEFT JOIN opc.accounts a ON a.id=t.initiator_id
            WHERE ((t.kind='consultation' AND t.initiator_id=%s AND (r.customer_id=%s OR
              (%s AND EXISTS(SELECT 1 FROM opc.hall_requests h WHERE h.request_id=t.request_id))))
            OR (t.kind='customer_project' AND (r.customer_id=%s OR
              (%s AND EXISTS(SELECT 1 FROM opc.assignments a WHERE a.engagement_id=t.engagement_id
             AND a.provider_id=%s AND a.ended_at IS NULL))))
            OR (t.kind='negotiation' AND (r.customer_id=%s OR (%s AND t.initiator_id=%s AND
              (EXISTS(SELECT 1 FROM opc.hall_requests h WHERE h.request_id=t.request_id) OR
               EXISTS(SELECT 1 FROM opc.assignments a JOIN opc.engagements e ON e.id=a.engagement_id
                 WHERE e.request_id=t.request_id AND a.provider_id=%s AND a.ended_at IS NULL))))))
            AND (%s::uuid IS NULL OR t.request_id=%s) ORDER BY t.created_at DESC,t.id LIMIT %s OFFSET %s""",
                            (actor.id, actor.id, hall_ok, actor.id, provider_ok, actor.id,
                             actor.id, provider_ok, actor.id, actor.id,
                             request_id, request_id, limit, offset)).fetchall()
    return {"items": [r for r in rows if thread_access(conn, actor, r, request.app.state.settings)], "limit": limit, "offset": offset}


@router.get("/api/v1/mobile/threads/{thread_id}/messages", summary="读取有权访问的消息")
@router.get("/api/v1/admin/threads/{thread_id}/messages", summary="运营读取会话消息")
def messages(thread_id: UUID, request: Request, actor: ActorDep, conn: TxDep, limit: int = Query(50, ge=1, le=100), offset: int = Query(0, ge=0)):
    accessible_thread(conn, actor, thread_id, request.app.state.settings)
    return {"items": conn.execute("""SELECT m.id,m.author_id,a.display_name AS author_name,m.body,m.client_message_id,m.sent_at
        FROM opc.messages m JOIN opc.accounts a ON a.id=m.author_id
        WHERE m.thread_id=%s ORDER BY m.sent_at,m.id LIMIT %s OFFSET %s""", (thread_id, limit, offset)).fetchall(), "limit": limit, "offset": offset}


@router.post("/api/v1/mobile/threads/{thread_id}/messages", status_code=201, summary="发送消息，按客户端消息标识幂等")
@router.post("/api/v1/admin/threads/{thread_id}/messages", status_code=201, summary="运营发送会话消息")
def send_message(thread_id: UUID, body: MessageInput, request: Request, actor: ActorDep, conn: TxDep):
    thread = conn.execute("SELECT request_id FROM opc.conversation_threads WHERE id=%s", (thread_id,)).fetchone()
    if thread:
        conn.execute("SELECT id FROM opc.requests WHERE id=%s FOR SHARE", (thread["request_id"],))
    accessible_thread(conn, actor, thread_id, request.app.state.settings)
    conn.execute("SELECT id FROM opc.conversation_threads WHERE id=%s FOR UPDATE", (thread_id,))
    participant(conn, thread_id, actor.id, actor.id)
    def action():
        return conn.execute("""INSERT INTO opc.messages(thread_id,author_id,body,client_message_id)
            VALUES (%s,%s,%s,%s) RETURNING id,thread_id,body,sent_at""", (thread_id, actor.id, body.body, body.client_message_id)).fetchone()
    return idempotent(conn, actor, "send_message", str(body.client_message_id), {"thread_id": thread_id, "body": body.body}, action)


@router.get("/api/v1/mobile/notifications", summary="本人站内通知")
@router.get("/api/v1/admin/notifications", summary="本人管理通知")
def notifications(actor: ActorDep, conn: TxDep, limit: int = Query(30, ge=1, le=100), offset: int = Query(0, ge=0)):
    return {"items": conn.execute("SELECT id,template_key,parameters,created_at,read_at FROM opc.notifications WHERE recipient_id=%s ORDER BY created_at DESC,id LIMIT %s OFFSET %s", (actor.id, limit, offset)).fetchall(), "limit": limit, "offset": offset}


@router.post("/api/v1/mobile/notifications/{notification_id}/read", summary="标记本人通知已读")
@router.post("/api/v1/admin/notifications/{notification_id}/read", summary="标记本人管理通知已读")
def read_notification(notification_id: UUID, actor: ActorDep, conn: TxDep):
    row = conn.execute("UPDATE opc.notifications SET read_at=coalesce(read_at,now()) WHERE id=%s AND recipient_id=%s RETURNING id,read_at", (notification_id, actor.id)).fetchone()
    if not row:
        raise DomainError(404, "NOT_FOUND", "通知不存在")
    return row


@router.get("/api/v1/admin/audit-events", summary="结构与操作审计（无密码、令牌或消息正文）")
def audit(actor: ActorDep, conn: TxDep, limit: int = Query(50, ge=1, le=100), before_id: int | None = Query(None, ge=1)):
    ensure_admin(actor, "administrator")
    return {"items": conn.execute("""SELECT id,occurred_at,application_actor_id,correlation_id,table_name,operation,entity_key,changed_fields,details
        FROM opc.audit_events WHERE (%s::bigint IS NULL OR id<%s) ORDER BY id DESC LIMIT %s""", (before_id, before_id, limit)).fetchall()}


@router.get("/api/v1/admin/dashboard", summary="后台受理、审核及交付计数")
def dashboard(actor: ActorDep, conn: TxDep):
    ensure_admin(actor, "operator", "compliance_reviewer", "technical_reviewer", "quality_reviewer")
    return {"requests": conn.execute("SELECT intake_status,count(*) AS count FROM opc.requests GROUP BY intake_status").fetchall(),
            "engagements": conn.execute("SELECT status,count(*) AS count FROM opc.engagements GROUP BY status").fetchall()}
