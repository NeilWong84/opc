"""已发布需求：特定承接者沟通 → 客户确认真实条款 → 本人承接。"""
from typing import Any
from uuid import UUID

from fastapi import APIRouter, Request
from pydantic import AwareDatetime, BaseModel, Field

from .common import check_version, emit
from .communication import accessible_thread, participant, project_thread
from .deps import ActorDep, TxDep, ensure_mobile, ensure_provider
from .errors import DomainError
from .fulfillment import IdempotencyKey, MutationResult, Text, _new_agreement, _change_state
from .idempotency import idempotent
from .models import Input, VersionInput

router = APIRouter(tags=["沟通与自主承接"])


class ProposalInput(Input):
    publication_id: UUID
    terms: Text
    quoted_amount: int | None = Field(default=None, ge=0, le=99999999999999, strict=True)
    due_at: AwareDatetime | None = None


class NegotiationDetail(BaseModel):
    thread_id: UUID
    request_id: UUID
    provider_id: UUID
    provider_name: str
    customer_id: UUID
    available: bool
    publication_id: UUID | None
    scope: dict[str, Any]
    proposal: dict[str, Any] | None


def _available(conn, request_id):
    return conn.execute("SELECT * FROM opc.hall_requests WHERE request_id=%s", (request_id,)).fetchone()


def _thread(conn, actor, thread_id, settings):
    ensure_mobile(actor)
    thread = accessible_thread(conn, actor, thread_id, settings)
    if thread["kind"] != "negotiation":
        raise DomainError(404, "NOT_FOUND", "合作沟通不存在")
    return thread


def _latest(conn, thread_id):
    return conn.execute("SELECT * FROM opc.claim_proposals WHERE thread_id=%s ORDER BY created_at DESC,id DESC LIMIT 1",
                        (thread_id,)).fetchone()


def _proposal_lock(conn, actor, proposal_id, settings):
    identity = conn.execute("""SELECT t.request_id,p.thread_id FROM opc.claim_proposals p
        JOIN opc.conversation_threads t ON t.id=p.thread_id WHERE p.id=%s""", (proposal_id,)).fetchone()
    if not identity:
        raise DomainError(404, "NOT_FOUND", "提案不存在")
    conn.execute("SELECT id FROM opc.requests WHERE id=%s FOR UPDATE", (identity["request_id"],))
    thread = _thread(conn, actor, identity["thread_id"], settings)
    proposal = conn.execute("SELECT * FROM opc.claim_proposals WHERE id=%s FOR UPDATE", (proposal_id,)).fetchone()
    if _latest(conn, thread["id"])["id"] != proposal_id:
        raise DomainError(409, "VERSION_CONFLICT", "条款已更新，请查看最新提案")
    hall = _available(conn, thread["request_id"])
    if not hall or hall["publication_id"] != proposal["publication_id"]:
        raise DomainError(409, "PUBLICATION_REQUIRED", "需求已换版、下架或已被承接")
    return thread, proposal, hall


@router.post("/api/v1/mobile/requests/{request_id}/negotiation", summary="与需求客户建立特定承接者沟通")
def start_negotiation(request_id: UUID, request: Request, conn: TxDep, actor: ActorDep):
    ensure_provider(conn, actor)
    from .requests import authorize_hall
    authorize_hall(request, conn, actor)
    req = conn.execute("SELECT * FROM opc.requests WHERE id=%s FOR UPDATE", (request_id,)).fetchone()
    if not req or not _available(conn, request_id):
        raise DomainError(404, "NOT_FOUND", "需求当前不可承接")
    if req["customer_id"] == actor.id:
        raise DomainError(422, "INVALID_PROVIDER", "不能承接本人需求")
    existing = conn.execute("""SELECT id FROM opc.conversation_threads
        WHERE request_id=%s AND initiator_id=%s AND kind='negotiation'""", (request_id, actor.id)).fetchone()
    if existing:
        return existing
    row = conn.execute("""INSERT INTO opc.conversation_threads(request_id,kind,initiator_id)
        VALUES (%s,'negotiation',%s) RETURNING id""", (request_id, actor.id)).fetchone()
    for account_id in (actor.id, req["customer_id"]):
        participant(conn, row["id"], account_id, actor.id)
    emit(conn, req["customer_id"], "negotiation.created", "有承接者发起沟通", "请查看沟通记录并核对范围与条款。",
         {"request_id": str(request_id), "thread_id": str(row["id"])})
    return row


@router.get("/api/v1/mobile/threads/{thread_id}/negotiation", response_model=NegotiationDetail,
            summary="本人参与的合作沟通及最新条款提案")
def negotiation_detail(thread_id: UUID, request: Request, conn: TxDep, actor: ActorDep):
    thread = _thread(conn, actor, thread_id, request.app.state.settings)
    req = conn.execute("SELECT customer_id FROM opc.requests WHERE id=%s", (thread["request_id"],)).fetchone()
    provider = conn.execute("SELECT display_name FROM opc.accounts WHERE id=%s", (thread["initiator_id"],)).fetchone()
    hall = _available(conn, thread["request_id"])
    proposal = _latest(conn, thread_id)
    scope = {}
    if proposal:
        scope = conn.execute("""SELECT s.title,s.goal,s.included_scope,s.excluded_scope,s.deliverables,
            s.acceptance_criteria,s.duration_text,s.revision_terms FROM opc.scope_versions s
            JOIN opc.publications p ON p.request_id=s.request_id AND p.scope_version=s.version
            WHERE p.id=%s""", (proposal["publication_id"],)).fetchone()
        proposal = {k: proposal[k] for k in ("id", "publication_id", "terms", "quoted_amount", "due_at",
                    "confirmed_by", "confirmed_at", "row_version", "created_at")}
        if proposal["quoted_amount"] is not None:
            proposal["quoted_amount"] = int(proposal["quoted_amount"])
    if hall:
        scope = {k: hall[k] for k in ("title", "goal", "included_scope", "excluded_scope", "deliverables",
                 "acceptance_criteria", "duration_text", "revision_terms")}
    return {"thread_id": thread_id, "request_id": thread["request_id"], "provider_id": thread["initiator_id"],
            "provider_name": provider["display_name"], "customer_id": req["customer_id"],
            "available": bool(hall), "publication_id": hall["publication_id"] if hall else None,
            "scope": scope, "proposal": proposal}


@router.post("/api/v1/mobile/threads/{thread_id}/proposal", summary="承接者提出当前发布范围的合作条款")
def propose(thread_id: UUID, body: ProposalInput, request: Request, conn: TxDep, actor: ActorDep,
            idempotency_key: IdempotencyKey):
    ensure_provider(conn, actor)

    def action():
        thread = _thread(conn, actor, thread_id, request.app.state.settings)
        conn.execute("SELECT id FROM opc.requests WHERE id=%s FOR UPDATE", (thread["request_id"],))
        if thread["initiator_id"] != actor.id:
            raise DomainError(403, "PROVIDER_REQUIRED", "仅本次沟通的承接者可提出条款")
        hall = _available(conn, thread["request_id"])
        if not hall or hall["publication_id"] != body.publication_id:
            raise DomainError(409, "PUBLICATION_REQUIRED", "请先查看当前已发布版本")
        row = conn.execute("""INSERT INTO opc.claim_proposals(thread_id,publication_id,provider_id,terms,quoted_amount,due_at,created_at)
            VALUES (%s,%s,%s,%s,%s,%s,clock_timestamp()) RETURNING id""",
            (thread_id, body.publication_id, actor.id, body.terms, body.quoted_amount, body.due_at)).fetchone()
        customer = conn.execute("SELECT customer_id FROM opc.requests WHERE id=%s", (thread["request_id"],)).fetchone()
        emit(conn, customer["customer_id"], "negotiation.proposed", "请确认合作范围与条款", "核对本次范围及条款后再确认。",
             {"request_id": str(thread["request_id"]), "thread_id": str(thread_id)})
        return row

    return idempotent(conn, actor, "claim.propose:" + str(thread_id), idempotency_key, body.model_dump(mode="json"), action)


@router.post("/api/v1/mobile/claim-proposals/{proposal_id}/confirm", summary="需求客户本人确认本次范围与条款")
def confirm_proposal(proposal_id: UUID, body: VersionInput, request: Request, conn: TxDep, actor: ActorDep):
    ensure_mobile(actor)
    thread, proposal, _ = _proposal_lock(conn, actor, proposal_id, request.app.state.settings)
    customer = conn.execute("SELECT customer_id FROM opc.requests WHERE id=%s", (thread["request_id"],)).fetchone()
    if actor.id != customer["customer_id"] or "customer" not in actor.roles:
        raise DomainError(403, "CUSTOMER_REQUIRED", "仅需求客户本人可确认")
    check_version(proposal, body.expected_version)
    if proposal["confirmed_at"]:
        raise DomainError(409, "ALREADY_CONFIRMED", "本版本已确认")
    conn.execute("UPDATE opc.claim_proposals SET confirmed_by=%s,confirmed_at=now() WHERE id=%s", (actor.id, proposal_id))
    emit(conn, proposal["provider_id"], "negotiation.confirmed", "客户已确认合作条款", "可查看本次条款并承接项目。",
         {"request_id": str(thread["request_id"]), "thread_id": str(thread["id"])})
    return {"id": proposal_id}


@router.post("/api/v1/mobile/claim-proposals/{proposal_id}/claim", response_model=MutationResult,
             status_code=201, summary="已获客户确认的承接者一键承接，归属本人并开始执行")
def claim(proposal_id: UUID, body: VersionInput, request: Request, conn: TxDep, actor: ActorDep,
          idempotency_key: IdempotencyKey):
    ensure_provider(conn, actor)

    def action():
        thread, proposal, hall = _proposal_lock(conn, actor, proposal_id, request.app.state.settings)
        if proposal["provider_id"] != actor.id:
            raise DomainError(403, "PROVIDER_REQUIRED", "仅提案承接者本人可承接")
        check_version(proposal, body.expected_version)
        if not proposal["confirmed_at"]:
            raise DomainError(409, "CUSTOMER_CONFIRMATION_REQUIRED", "请先由客户确认本次范围与条款")
        engagement = conn.execute("INSERT INTO opc.engagements(request_id,created_by) VALUES (%s,%s) RETURNING *",
                                  (thread["request_id"], actor.id)).fetchone()
        conn.execute("""INSERT INTO opc.assignments(engagement_id,version,provider_id,recorded_by,reason)
            VALUES (%s,1,%s,%s,%s)""", (engagement["id"], actor.id, actor.id, "客户确认提案 " + str(proposal_id) + " 后本人承接"))
        _new_agreement(conn, engagement, actor.id, version=1, scope_version=hall["scope_version"],
                       terms=proposal["terms"], quoted_amount=proposal["quoted_amount"], due_at=proposal["due_at"])
        # 客户确认来自该客户实际确认提案的时间与账号；不由承接者代为确认。
        conn.execute("""INSERT INTO opc.agreement_confirmations(engagement_id,agreement_version,party,confirmed_by,confirmed_at)
            VALUES (%s,1,'customer',%s,%s),(%s,1,'provider',%s,now())""",
            (engagement["id"], proposal["confirmed_by"], proposal["confirmed_at"], engagement["id"], actor.id))
        project_thread(conn, thread["request_id"], engagement["id"], actor.id)
        result = _change_state(conn, engagement, "executing")
        for recipient in (actor.id, proposal["confirmed_by"]):
            emit(conn, recipient, "engagement.confirmed", "项目已承接并开始执行", "项目已归属沟通中确认的承接者。",
                 {"request_id": str(thread["request_id"]), "engagement_id": str(engagement["id"])})
        return {**result, "agreement_version": 1, "assignment_version": 1}

    return idempotent(conn, actor, "claim.accept:" + str(proposal_id), idempotency_key, body.model_dump(mode="json"), action)
