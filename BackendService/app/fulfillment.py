"""合作事实、双方条款确认、固定版本交付、内部质检与客户验收。

所有写入均处于依赖提供的同一事务中，固定按需求、合作、交付顺序加锁。
本模块不选择接单机制，不执行仓库代码，不将报价或验收解释为付款。
"""

from __future__ import annotations

import re
from typing import Annotated, Any, Literal
from urllib.parse import urlsplit
from uuid import UUID

from fastapi import APIRouter, Header, Query, Request
from pydantic import AwareDatetime, BaseModel, Field, StringConstraints, model_validator

from .auth import business_audit
from .common import check_version, emit, owned_files
from .deps import ActorDep, TxDep, ensure_admin, ensure_mobile, ensure_provider
from .errors import DomainError
from .idempotency import idempotent
from .models import Input, ReasonInput, VersionInput

router = APIRouter(tags=["合作、交付与验收"])
Text = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=12000)]
Reason = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=2000)]
IdempotencyKey = Annotated[str, Header(alias="Idempotency-Key", min_length=1, max_length=200)]


class CreateEngagement(VersionInput):
    request_id: UUID
    provider_id: UUID
    terms: Text
    reason: Reason
    quoted_amount: int | None = Field(default=None, ge=0, le=99999999999999, strict=True)
    due_at: AwareDatetime | None = None


class AgreementInput(VersionInput):
    scope_version: int = Field(ge=1)
    terms: Text
    reason: Reason
    quoted_amount: int | None = Field(default=None, ge=0, le=99999999999999, strict=True)
    due_at: AwareDatetime | None = None


class ReassignInput(ReasonInput):
    provider_id: UUID


class DeliveryFile(Input):
    file_id: UUID
    purpose: Literal["source", "guide", "tests", "demo", "other"]


class DeliveryInput(VersionInput):
    agreement_version: int = Field(ge=1)
    note: Text
    source_file_id: UUID | None = None
    repository_url: str | None = Field(default=None, max_length=2048)
    source_commit: str | None = Field(default=None, max_length=64)
    source_archive_ref: str | None = Field(default=None, max_length=2000)
    guide_text: Text
    test_report_text: Text
    files: list[DeliveryFile] = Field(default_factory=list, max_length=20)

    @model_validator(mode="after")
    def fixed_source(self):
        if self.source_file_id is not None:
            if any(v is not None for v in (self.repository_url, self.source_commit, self.source_archive_ref)):
                raise ValueError("源码包与仓库固定提交必须二选一")
        else:
            url = urlsplit(self.repository_url or "")
            if url.scheme != "https" or not url.hostname or url.username or url.password or url.fragment:
                raise ValueError("仓库必须使用无凭据的 HTTPS 地址")
            if not re.fullmatch(r"[0-9a-f]{40}([0-9a-f]{24})?", self.source_commit or ""):
                raise ValueError("必须提交完整的 40 或 64 位小写十六进制 commit，不能使用分支名称")
            if not self.source_archive_ref or not self.source_archive_ref.strip():
                raise ValueError("仓库交付必须提供客户可取得的约定源码归档证据")
        ids = [f.file_id for f in self.files]
        if len(ids) != len(set(ids)):
            raise ValueError("同一交付文件不可重复关联")
        if self.source_file_id in ids:
            raise ValueError("主源码包会自动关联，不可在附加文件中重复")
        return self


class ReviewInput(VersionInput):
    decision: Literal["approved", "changes_requested", "rejected"]
    evidence: Text


class AcceptanceInput(VersionInput):
    decision: Literal["accepted", "revision_requested"]
    feedback: str = Field(default="", max_length=4000)

    @model_validator(mode="after")
    def revision_feedback(self):
        self.feedback = self.feedback.strip()
        if self.decision == "revision_requested" and not self.feedback:
            raise ValueError("要求修改时必须填写具体反馈")
        return self


class MutationResult(BaseModel):
    engagement_id: UUID
    row_version: int
    status: str
    agreement_version: int | None = None
    assignment_version: int | None = None
    delivery_id: UUID | None = None
    delivery_version: int | None = None
    review_id: UUID | None = None
    publication_id: UUID | None = None
    acceptance_id: UUID | None = None


class EngagementPage(BaseModel):
    items: list[dict[str, Any]]
    limit: int
    offset: int


class EngagementDetail(BaseModel):
    engagement: dict[str, Any]
    agreements: list[dict[str, Any]]
    confirmations: list[dict[str, Any]]
    deliveries: list[dict[str, Any]]
    acceptances: list[dict[str, Any]]
    assignments: list[dict[str, Any]] = Field(default_factory=list)
    reviews: list[dict[str, Any]] = Field(default_factory=list)
    publications: list[dict[str, Any]] = Field(default_factory=list)


def _not_found():
    raise DomainError(404, "NOT_FOUND", "合作或交付不存在，或当前账号无权访问")


def require_state(engagement, *allowed):
    """Keep terminal and workflow state checks consistent across mutations."""
    if engagement["closed_at"] is not None or engagement["status"] not in allowed:
        raise DomainError(409, "STATE_CONFLICT", "当前合作状态不允许此操作")


def require_latest(actual: int, requested: int):
    if actual != requested:
        raise DomainError(409, "VERSION_CONFLICT", "必须操作最新业务版本")


def parties_confirmed(confirmed, customer_id, provider_id):
    """Past assignees' confirmations can never authorize the new provider."""
    return bool(provider_id and customer_id != provider_id and
                confirmed.get("customer") == customer_id and confirmed.get("provider") == provider_id)


def _lock_engagement(conn, engagement_id):
    identity = conn.execute("SELECT request_id FROM opc.engagements WHERE id=%s", (engagement_id,)).fetchone()
    if not identity:
        _not_found()
    conn.execute("SELECT id FROM opc.requests WHERE id=%s FOR UPDATE", (identity["request_id"],)).fetchone()
    row = conn.execute(
        """SELECT e.*, r.customer_id, r.public_code, r.current_scope_version
        FROM opc.engagements e JOIN opc.requests r ON r.id=e.request_id
        WHERE e.id=%s FOR UPDATE OF e""", (engagement_id,),
    ).fetchone()
    if not row:
        _not_found()
    return row


def _get_engagement(conn, engagement_id):
    row = conn.execute(
        """SELECT e.*,r.customer_id,r.public_code,r.current_scope_version
        FROM opc.engagements e JOIN opc.requests r ON r.id=e.request_id WHERE e.id=%s""",
        (engagement_id,),
    ).fetchone()
    if not row:
        _not_found()
    return row


def _assignment(conn, engagement_id):
    return conn.execute(
        "SELECT * FROM opc.assignments WHERE engagement_id=%s AND ended_at IS NULL", (engagement_id,),
    ).fetchone()


def _authorized_provider(conn, account_id):
    # Include the role independently: an authorization row never creates a role.
    row = conn.execute(
        """SELECT a.id FROM opc.accounts a
        JOIN opc.provider_authorizations p ON p.account_id=a.id AND p.revoked_at IS NULL
        JOIN opc.account_roles ar ON ar.account_id=a.id AND ar.role_code='provider' AND ar.revoked_at IS NULL
        WHERE a.id=%s AND a.status='active' FOR SHARE OF a,p,ar""", (account_id,),
    ).fetchone()
    if not row:
        raise DomainError(422, "PROVIDER_REQUIRED", "负责人必须是启用且具有当前内部授权的承接账号")


def _party(conn, actor, engagement):
    ensure_mobile(actor)
    if "customer" in actor.roles and actor.id == engagement["customer_id"]:
        return "customer"
    if "provider" not in actor.roles:
        _not_found()
    ensure_provider(conn, actor)
    assignment = _assignment(conn, engagement["id"])
    if not assignment or assignment["provider_id"] != actor.id:
        _not_found()
    return "provider"


def _mobile_precheck(conn, actor, engagement_id):
    """Reject revoked provider access before probing the requested object."""
    ensure_mobile(actor)
    if "customer" in actor.roles:
        owned = conn.execute(
            """SELECT 1 FROM opc.engagements e JOIN opc.requests r ON r.id=e.request_id
            WHERE e.id=%s AND r.customer_id=%s""", (engagement_id, actor.id),
        ).fetchone()
        if owned:
            return
        if "provider" not in actor.roles:
            _not_found()
    ensure_provider(conn, actor)


def _latest_agreement(conn, engagement_id):
    row = conn.execute(
        "SELECT * FROM opc.agreement_versions WHERE engagement_id=%s ORDER BY version DESC LIMIT 1",
        (engagement_id,),
    ).fetchone()
    if not row:
        raise DomainError(409, "AGREEMENT_REQUIRED", "合作尚未建立条款版本")
    return row


def _latest_delivery(conn, engagement_id, delivery_id):
    row = conn.execute(
        "SELECT * FROM opc.deliveries WHERE engagement_id=%s ORDER BY version DESC LIMIT 1 FOR UPDATE",
        (engagement_id,),
    ).fetchone()
    if not row or row["id"] != delivery_id:
        raise DomainError(409, "VERSION_CONFLICT", "必须操作当前合作的最新交付版本")
    return row


def _lock_cleared_delivery_files(conn, delivery):
    rows = conn.execute(
        """SELECT f.id,f.upload_status,f.scan_status FROM opc.files f WHERE f.id=%s OR f.id IN
        (SELECT file_id FROM opc.delivery_files WHERE delivery_id=%s) ORDER BY f.id FOR SHARE OF f""",
        (delivery["source_file_id"], delivery["id"]),
    ).fetchall()
    if any(row["upload_status"] != "ready" or row["scan_status"] != "clean" for row in rows):
        raise DomainError(409, "FILE_NOT_READY", "交付文件当前不可用，不能发布或验收")


def _change_state(conn, engagement, status, *, close=False):
    if close:
        row = conn.execute(
            "UPDATE opc.engagements SET status=%s,closed_at=now() WHERE id=%s RETURNING row_version,status",
            (status, engagement["id"]),
        ).fetchone()
        conn.execute("UPDATE opc.requests SET intake_status='closed' WHERE id=%s", (engagement["request_id"],))
    else:
        row = conn.execute(
            "UPDATE opc.engagements SET status=%s WHERE id=%s RETURNING row_version,status", (status, engagement["id"]),
        ).fetchone()
    return {"engagement_id": engagement["id"], **row}


def _withdraw_deliveries(conn, engagement_id, actor_id, reason):
    conn.execute(
        """UPDATE opc.delivery_publications p SET withdrawn_by=%s,withdrawn_at=now(),withdrawal_reason=%s
        FROM opc.deliveries d WHERE p.delivery_id=d.id AND d.engagement_id=%s AND p.withdrawn_at IS NULL""",
        (actor_id, reason, engagement_id),
    )


def _new_agreement(conn, engagement, actor_id, *, version, scope_version, terms, quoted_amount, due_at):
    conn.execute(
        """INSERT INTO opc.agreement_versions
        (engagement_id,version,request_id,scope_version,terms,quoted_amount,due_at,authored_by)
        VALUES (%s,%s,%s,%s,%s,%s,%s,%s)""",
        (engagement["id"], version, engagement["request_id"], scope_version, terms, quoted_amount, due_at, actor_id),
    )


def _notify_parties(conn, engagement, event_type, title, body):
    recipients = {engagement["customer_id"]}
    assignment = _assignment(conn, engagement["id"])
    if assignment:
        recipients.add(assignment["provider_id"])
    for account_id in recipients:
        emit(conn, account_id, event_type, title, body, {"engagement_id": str(engagement["id"])})


def _detail(conn, engagement, *, audience):
    # Explicit projections prevent private audit and QA fields entering mobile JSON.
    core = {k: engagement[k] for k in (
        "id", "request_id", "customer_id", "public_code", "status", "created_at", "closed_at", "row_version",
    )}
    assignment = _assignment(conn, engagement["id"])
    core["provider_id"] = assignment["provider_id"] if assignment else None
    agreements = conn.execute(
        """SELECT a.version,a.scope_version,a.terms,a.quoted_amount,a.currency,a.due_at,a.authored_at,
        jsonb_build_object('title',s.title,'goal',s.goal,'included_scope',s.included_scope,
          'excluded_scope',s.excluded_scope,'deliverables',s.deliverables,
          'acceptance_criteria',s.acceptance_criteria,'duration_text',s.duration_text,
          'revision_terms',s.revision_terms) AS scope
        FROM opc.agreement_versions a JOIN opc.scope_versions s
        ON s.request_id=a.request_id AND s.version=a.scope_version
        WHERE a.engagement_id=%s ORDER BY a.version""", (engagement["id"],),
    ).fetchall()
    for agreement in agreements:
        if agreement["quoted_amount"] is not None:
            agreement["quoted_amount"] = int(agreement["quoted_amount"])
        agreement["scope"]["reference_files"] = conn.execute(
            """SELECT f.id AS file_id,f.original_name,f.kind,f.media_type,f.size_bytes,f.duration_ms,s.sort_order
            FROM opc.scope_files s JOIN opc.files f ON f.id=s.file_id
            WHERE s.request_id=%s AND s.scope_version=%s
            AND f.upload_status='ready' AND f.scan_status='clean' ORDER BY s.sort_order,f.id""",
            (engagement["request_id"], agreement["scope_version"]),
        ).fetchall()
    confirmations = conn.execute(
        """SELECT agreement_version,party,confirmed_by,confirmed_at FROM opc.agreement_confirmations
        WHERE engagement_id=%s ORDER BY agreement_version,party""", (engagement["id"],),
    ).fetchall()
    visibility = ""
    if audience == "customer":
        visibility = """AND EXISTS (SELECT 1 FROM opc.delivery_publications p
          JOIN opc.delivery_reviews q ON q.id=p.review_id AND q.delivery_id=p.delivery_id
          WHERE p.delivery_id=d.id AND p.withdrawn_at IS NULL AND q.decision='approved')
          AND NOT EXISTS (SELECT 1 FROM opc.deliveries n WHERE n.engagement_id=d.engagement_id AND n.version>d.version)
          AND d.agreement_version=(SELECT max(a.version) FROM opc.agreement_versions a WHERE a.engagement_id=d.engagement_id)
          AND (d.source_file_id IS NULL OR EXISTS (SELECT 1 FROM opc.files f WHERE f.id=d.source_file_id AND f.upload_status='ready' AND f.scan_status='clean'))
          AND NOT EXISTS (SELECT 1 FROM opc.delivery_files df JOIN opc.files f ON f.id=df.file_id
            WHERE df.delivery_id=d.id AND (f.upload_status<>'ready' OR f.scan_status<>'clean'))"""
    deliveries = conn.execute(
        """SELECT d.id,d.version,d.agreement_version,d.note,d.source_file_id,d.repository_url,d.source_commit,
        d.source_archive_ref,d.guide_text,d.test_report_text,d.submitted_at,
        EXISTS(SELECT 1 FROM opc.delivery_publications p WHERE p.delivery_id=d.id AND p.withdrawn_at IS NULL) AS published
        FROM opc.deliveries d WHERE d.engagement_id=%s """ + visibility + " ORDER BY d.version",
        (engagement["id"],),
    ).fetchall()
    for delivery in deliveries:
        delivery["files"] = conn.execute(
            """SELECT f.id,f.original_name,f.media_type,f.kind,f.size_bytes,f.sha256,df.purpose
            FROM opc.delivery_files df JOIN opc.files f ON f.id=df.file_id
            WHERE df.delivery_id=%s AND f.upload_status='ready' AND f.scan_status='clean' ORDER BY f.original_name""",
            (delivery["id"],),
        ).fetchall()
    # Feedback is customer-visible, unlike internal quality-review evidence.
    acceptances = conn.execute(
        """SELECT a.id,a.delivery_id,d.version AS delivery_version,a.decision,a.feedback,a.decided_at
        FROM opc.acceptance_decisions a JOIN opc.deliveries d ON d.id=a.delivery_id
        WHERE d.engagement_id=%s ORDER BY d.version""", (engagement["id"],),
    ).fetchall()
    result = {"engagement": core, "agreements": agreements, "confirmations": confirmations,
              "deliveries": deliveries, "acceptances": acceptances}
    if audience == "admin":
        result["assignments"] = conn.execute(
            "SELECT * FROM opc.assignments WHERE engagement_id=%s ORDER BY version", (engagement["id"],),
        ).fetchall()
        result["reviews"] = conn.execute(
            "SELECT q.* FROM opc.delivery_reviews q JOIN opc.deliveries d ON d.id=q.delivery_id WHERE d.engagement_id=%s ORDER BY d.version",
            (engagement["id"],),
        ).fetchall()
        result["publications"] = conn.execute(
            "SELECT p.* FROM opc.delivery_publications p JOIN opc.deliveries d ON d.id=p.delivery_id WHERE d.engagement_id=%s ORDER BY d.version",
            (engagement["id"],),
        ).fetchall()
    return result


@router.post("/api/v1/admin/engagements", response_model=MutationResult, status_code=201,
             summary="记录已确认的合作关系（默认关闭，非自动派单）",
             description="仅运营/管理员；assignment_mode=record_confirmed 时启用。expected_version 为需求 row_version。记录已明确的双方及条款，双方仍须在手机确认。报价不代表收款。")
def create_engagement(body: CreateEngagement, request: Request, conn: TxDep, actor: ActorDep, idempotency_key: IdempotencyKey):
    ensure_admin(actor, "operator")
    if request.app.state.settings.assignment_mode != "record_confirmed":
        raise DomainError(409, "ASSIGNMENT_MODE_UNCONFIGURED", "接单机制尚未启用，不能自动建立合作关系")

    def action():
        original = conn.execute("SELECT * FROM opc.requests WHERE id=%s FOR UPDATE", (body.request_id,)).fetchone()
        if not original:
            _not_found()
        check_version(original, body.expected_version)
        hall = conn.execute("SELECT scope_version FROM opc.hall_requests WHERE request_id=%s", (body.request_id,)).fetchone()
        if not hall:
            raise DomainError(409, "PUBLICATION_REQUIRED", "只能基于当前审核通过且可承接的大厅版本记录合作")
        if body.provider_id == original["customer_id"]:
            raise DomainError(422, "INVALID_PROVIDER", "客户与负责人必须为不同账号")
        _authorized_provider(conn, body.provider_id)
        engagement = conn.execute(
            "INSERT INTO opc.engagements(request_id,created_by) VALUES (%s,%s) RETURNING *",
            (body.request_id, actor.id),
        ).fetchone()
        engagement["customer_id"] = original["customer_id"]
        conn.execute(
            "INSERT INTO opc.assignments(engagement_id,version,provider_id,recorded_by,reason) VALUES (%s,1,%s,%s,%s)",
            (engagement["id"], body.provider_id, actor.id, body.reason),
        )
        _new_agreement(conn, engagement, actor.id, version=1, scope_version=hall["scope_version"],
                       terms=body.terms, quoted_amount=body.quoted_amount, due_at=body.due_at)
        # A recorded cooperation includes a usable mobile conversation for both
        # parties. Access still checks current ownership/assignment on every read.
        from .communication import project_thread
        project_thread(conn, body.request_id, engagement["id"], actor.id)
        _notify_parties(conn, engagement, "agreement.created", "合作条款待确认", "请查看并确认当前合作条款。")
        return {"engagement_id": engagement["id"], "row_version": engagement["row_version"],
                "status": engagement["status"], "agreement_version": 1, "assignment_version": 1}

    return idempotent(conn, actor, "engagement.create", idempotency_key, body.model_dump(mode="json"), action)


@router.get("/api/v1/admin/engagements", response_model=EngagementPage, summary="后台合作列表")
def admin_engagements(conn: TxDep, actor: ActorDep, limit: Annotated[int, Query(ge=1, le=100)] = 30,
                      offset: Annotated[int, Query(ge=0)] = 0):
    ensure_admin(actor, "operator", "quality_reviewer", "technical_reviewer")
    items = conn.execute(
        """SELECT e.id,e.request_id,r.public_code,r.customer_id,e.status,e.created_at,e.closed_at,e.row_version,
        a.provider_id FROM opc.engagements e JOIN opc.requests r ON r.id=e.request_id
        LEFT JOIN opc.assignments a ON a.engagement_id=e.id AND a.ended_at IS NULL
        ORDER BY e.created_at DESC,e.id LIMIT %s OFFSET %s""", (limit, offset),
    ).fetchall()
    return {"items": items, "limit": limit, "offset": offset}


@router.get("/api/v1/admin/engagements/{engagement_id}", response_model=EngagementDetail, summary="后台合作详情与质检历史")
def admin_engagement_detail(engagement_id: UUID, conn: TxDep, actor: ActorDep):
    ensure_admin(actor, "operator", "quality_reviewer", "technical_reviewer")
    return _detail(conn, _get_engagement(conn, engagement_id), audience="admin")


@router.get("/api/v1/mobile/engagements", response_model=EngagementPage, summary="手机本人合作列表")
def mobile_engagements(conn: TxDep, actor: ActorDep, perspective: Literal["customer", "provider"] = "customer",
                       limit: Annotated[int, Query(ge=1, le=100)] = 30, offset: Annotated[int, Query(ge=0)] = 0,
                       request_id: UUID | None = None):
    ensure_mobile(actor)
    if perspective == "provider":
        ensure_provider(conn, actor)
        predicate = "a.provider_id=%s"
    else:
        if "customer" not in actor.roles:
            raise DomainError(403, "CUSTOMER_REQUIRED", "需要客户身份")
        predicate = "r.customer_id=%s"
    items = conn.execute(
        """SELECT e.id,e.request_id,r.public_code,e.status,e.created_at,e.closed_at,e.row_version,a.provider_id
        FROM opc.engagements e JOIN opc.requests r ON r.id=e.request_id
        LEFT JOIN opc.assignments a ON a.engagement_id=e.id AND a.ended_at IS NULL WHERE """ + predicate +
        " AND (%s::uuid IS NULL OR e.request_id=%s) ORDER BY e.created_at DESC,e.id LIMIT %s OFFSET %s",
        (actor.id, request_id, request_id, limit, offset),
    ).fetchall()
    return {"items": items, "limit": limit, "offset": offset}


@router.get("/api/v1/mobile/engagements/{engagement_id}", response_model=EngagementDetail,
            summary="手机合作详情（客户仅可读取最新合法发布交付）")
def mobile_engagement_detail(engagement_id: UUID, conn: TxDep, actor: ActorDep):
    _mobile_precheck(conn, actor, engagement_id)
    engagement = _get_engagement(conn, engagement_id)
    party = _party(conn, actor, engagement)
    return _detail(conn, engagement, audience=party)


@router.post("/api/v1/admin/engagements/{engagement_id}/reassign", response_model=MutationResult,
             summary="接管负责人并生成待双方重新确认的新条款版本")
def reassign(engagement_id: UUID, body: ReassignInput, conn: TxDep, actor: ActorDep):
    ensure_admin(actor, "operator")
    engagement = _lock_engagement(conn, engagement_id)
    check_version(engagement, body.expected_version)
    require_state(engagement, "pending_confirmation", "executing", "internal_review", "awaiting_acceptance", "revision")
    old = _assignment(conn, engagement_id)
    if not old:
        raise DomainError(409, "ASSIGNMENT_REQUIRED", "当前合作没有有效负责人")
    if body.provider_id in (old["provider_id"], engagement["customer_id"]):
        raise DomainError(422, "INVALID_PROVIDER", "新负责人必须不同于客户及当前负责人")
    _authorized_provider(conn, body.provider_id)
    agreement = _latest_agreement(conn, engagement_id)
    conn.execute("UPDATE opc.assignments SET ended_by=%s,ended_at=now(),end_reason=%s WHERE id=%s",
                 (actor.id, body.reason, old["id"]))
    conn.execute(
        "INSERT INTO opc.assignments(engagement_id,version,provider_id,recorded_by,reason) VALUES (%s,%s,%s,%s,%s)",
        (engagement_id, old["version"] + 1, body.provider_id, actor.id, body.reason),
    )
    new_version = agreement["version"] + 1
    _new_agreement(conn, engagement, actor.id, version=new_version, scope_version=agreement["scope_version"],
                   terms=agreement["terms"], quoted_amount=agreement["quoted_amount"], due_at=agreement["due_at"])
    _withdraw_deliveries(conn, engagement_id, actor.id, body.reason)
    result = _change_state(conn, engagement, "pending_confirmation")
    _notify_parties(conn, engagement, "agreement.reassigned", "合作负责人已变更", "请重新确认当前负责人及条款后开始履约。")
    return {**result, "agreement_version": new_version, "assignment_version": old["version"] + 1}


@router.post("/api/v1/admin/engagements/{engagement_id}/cancel", response_model=MutationResult, summary="取消合作并保留历史证据")
def cancel_engagement(engagement_id: UUID, body: ReasonInput, conn: TxDep, actor: ActorDep):
    ensure_admin(actor, "operator")
    engagement = _lock_engagement(conn, engagement_id)
    check_version(engagement, body.expected_version)
    require_state(engagement, "pending_confirmation", "executing", "internal_review", "awaiting_acceptance", "revision")
    _notify_parties(conn, engagement, "engagement.cancelled", "合作已取消", "合作已由后台取消，后续安排请联系运营。")
    _withdraw_deliveries(conn, engagement_id, actor.id, body.reason)
    conn.execute(
        "UPDATE opc.assignments SET ended_by=%s,ended_at=now(),end_reason=%s WHERE engagement_id=%s AND ended_at IS NULL",
        (actor.id, body.reason, engagement_id),
    )
    return _change_state(conn, engagement, "cancelled", close=True)


@router.post("/api/v1/admin/engagements/{engagement_id}/agreements", response_model=MutationResult, status_code=201,
             summary="追加已审核范围的合作条款并要求双方重新确认")
def create_agreement(engagement_id: UUID, body: AgreementInput, conn: TxDep, actor: ActorDep):
    ensure_admin(actor, "operator")
    engagement = _lock_engagement(conn, engagement_id)
    check_version(engagement, body.expected_version)
    require_state(engagement, "pending_confirmation", "executing", "internal_review", "awaiting_acceptance", "revision")
    old = _latest_agreement(conn, engagement_id)
    if body.scope_version < old["scope_version"] or body.scope_version not in (old["scope_version"], engagement["current_scope_version"]):
        raise DomainError(409, "VERSION_CONFLICT", "只能保留既有审核范围，或采用当前已激活的新审核范围")
    reviews = conn.execute(
        "SELECT count(*) AS count FROM opc.review_decisions WHERE request_id=%s AND scope_version=%s AND decision='approved'",
        (engagement["request_id"], body.scope_version),
    ).fetchone()
    if reviews["count"] != 2:
        raise DomainError(409, "REVIEW_REQUIRED", "合作范围必须通过合规及技术审核")
    version = old["version"] + 1
    _new_agreement(conn, engagement, actor.id, version=version, scope_version=body.scope_version,
                   terms=body.terms, quoted_amount=body.quoted_amount, due_at=body.due_at)
    business_audit(conn, "agreement_versions", engagement_id, body.reason)
    _withdraw_deliveries(conn, engagement_id, actor.id, body.reason)
    result = _change_state(conn, engagement, "pending_confirmation")
    _notify_parties(conn, engagement, "agreement.updated", "合作条款已更新", "请查看最新条款并重新确认。")
    return {**result, "agreement_version": version}


@router.post("/api/v1/mobile/engagements/{engagement_id}/agreements/{agreement_version}/confirm",
             response_model=MutationResult, summary="本人确认最新合作条款（双方确认后执行）")
def confirm_agreement(engagement_id: UUID, agreement_version: int, body: VersionInput, conn: TxDep, actor: ActorDep):
    _mobile_precheck(conn, actor, engagement_id)
    engagement = _lock_engagement(conn, engagement_id)
    party = _party(conn, actor, engagement)
    check_version(engagement, body.expected_version)
    require_state(engagement, "pending_confirmation")
    agreement = _latest_agreement(conn, engagement_id)
    require_latest(agreement["version"], agreement_version)
    existing = conn.execute(
        "SELECT 1 FROM opc.agreement_confirmations WHERE engagement_id=%s AND agreement_version=%s AND party=%s",
        (engagement_id, agreement_version, party),
    ).fetchone()
    if existing:
        raise DomainError(409, "ALREADY_CONFIRMED", "当前账号已确认此条款版本")
    conn.execute(
        "INSERT INTO opc.agreement_confirmations(engagement_id,agreement_version,party,confirmed_by) VALUES (%s,%s,%s,%s)",
        (engagement_id, agreement_version, party, actor.id),
    )
    assignment = _assignment(conn, engagement_id)
    confirmations = conn.execute(
        "SELECT party,confirmed_by FROM opc.agreement_confirmations WHERE engagement_id=%s AND agreement_version=%s",
        (engagement_id, agreement_version),
    ).fetchall()
    confirmed = {row["party"]: row["confirmed_by"] for row in confirmations}
    ready = parties_confirmed(confirmed, engagement["customer_id"], assignment["provider_id"] if assignment else None)
    if ready:
        _authorized_provider(conn, assignment["provider_id"])
    result = _change_state(conn, engagement, "executing" if ready else "pending_confirmation")
    if ready:
        _notify_parties(conn, engagement, "agreement.confirmed", "双方已确认合作", "当前条款已经双方确认，可以开始履约。")
    return {**result, "agreement_version": agreement_version}


@router.post("/api/v1/mobile/engagements/{engagement_id}/deliveries", response_model=MutationResult, status_code=201,
             summary="负责人提交固定源码交付（进入内部质检，未对客公开）")
def submit_delivery(engagement_id: UUID, body: DeliveryInput, conn: TxDep, actor: ActorDep, idempotency_key: IdempotencyKey):
    ensure_provider(conn, actor)

    def action():
        engagement = _lock_engagement(conn, engagement_id)
        if _party(conn, actor, engagement) != "provider":
            raise DomainError(403, "PROVIDER_REQUIRED", "仅当前负责人可提交交付")
        check_version(engagement, body.expected_version)
        require_state(engagement, "executing", "revision")
        agreement = _latest_agreement(conn, engagement_id)
        require_latest(agreement["version"], body.agreement_version)
        assignment = _assignment(conn, engagement_id)
        ids = [f.file_id for f in body.files]
        if body.source_file_id:
            ids.append(body.source_file_id)
        owned_files(conn, actor.id, ids)
        version = conn.execute("SELECT coalesce(max(version),0)+1 AS next FROM opc.deliveries WHERE engagement_id=%s",
                               (engagement_id,)).fetchone()["next"]
        row = conn.execute(
            """INSERT INTO opc.deliveries(engagement_id,version,assignment_id,agreement_version,submitted_by,note,
            source_file_id,repository_url,source_commit,source_archive_ref,guide_text,test_report_text)
            VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s) RETURNING id""",
            (engagement_id, version, assignment["id"], body.agreement_version, actor.id, body.note, body.source_file_id,
             body.repository_url, body.source_commit, body.source_archive_ref, body.guide_text, body.test_report_text),
        ).fetchone()
        attachments = [(f.file_id, f.purpose) for f in body.files]
        if body.source_file_id:
            attachments.append((body.source_file_id, "source"))
        for file_id, purpose in attachments:
            conn.execute("INSERT INTO opc.delivery_files(delivery_id,file_id,purpose) VALUES (%s,%s,%s)",
                         (row["id"], file_id, purpose))
        # A new internal version invalidates old customer access immediately.
        _withdraw_deliveries(conn, engagement_id, actor.id, "负责人提交了新的交付版本")
        result = _change_state(conn, engagement, "internal_review")
        emit(conn, actor.id, "delivery.submitted", "交付已提交内部检查", "检查通过并正式发布后，客户才可查看交付。",
             {"engagement_id": str(engagement_id), "delivery_id": str(row["id"])})
        return {**result, "delivery_id": row["id"], "delivery_version": version}

    return idempotent(conn, actor, "delivery.create:" + str(engagement_id), idempotency_key, body.model_dump(mode="json"), action)


@router.post("/api/v1/admin/engagements/{engagement_id}/deliveries/{delivery_id}/review", response_model=MutationResult,
             summary="内部质检记录（仅质检角色；不等于客户验收）")
def review_delivery(engagement_id: UUID, delivery_id: UUID, body: ReviewInput, conn: TxDep, actor: ActorDep):
    ensure_admin(actor, "quality_reviewer")
    engagement = _lock_engagement(conn, engagement_id)
    check_version(engagement, body.expected_version)
    require_state(engagement, "internal_review")
    delivery = _latest_delivery(conn, engagement_id, delivery_id)
    require_latest(_latest_agreement(conn, engagement_id)["version"], delivery["agreement_version"])
    if conn.execute("SELECT 1 FROM opc.delivery_reviews WHERE delivery_id=%s", (delivery_id,)).fetchone():
        raise DomainError(409, "ALREADY_REVIEWED", "交付质检证据不可覆盖，请提交新交付版本")
    row = conn.execute(
        "INSERT INTO opc.delivery_reviews(delivery_id,reviewer_id,decision,evidence) VALUES (%s,%s,%s,%s) RETURNING id",
        (delivery_id, actor.id, body.decision, body.evidence),
    ).fetchone()
    result = _change_state(conn, engagement, "internal_review" if body.decision == "approved" else "revision")
    assignment = _assignment(conn, engagement_id)
    if assignment:
        emit(conn, assignment["provider_id"], "delivery.reviewed", "交付检查已完成",
             "内部检查通过，等待正式对客发布。" if body.decision == "approved" else "交付需要修改，请与内部质检人员沟通后提交新版本。",
             {"engagement_id": str(engagement_id), "decision": body.decision})
    return {**result, "review_id": row["id"], "delivery_id": delivery_id, "delivery_version": delivery["version"]}


@router.post("/api/v1/admin/engagements/{engagement_id}/deliveries/{delivery_id}/publish", response_model=MutationResult,
             summary="将最新质检通过的交付正式发布给客户")
def publish_delivery(engagement_id: UUID, delivery_id: UUID, body: VersionInput, conn: TxDep, actor: ActorDep):
    ensure_admin(actor, "quality_reviewer")
    engagement = _lock_engagement(conn, engagement_id)
    check_version(engagement, body.expected_version)
    require_state(engagement, "internal_review")
    delivery = _latest_delivery(conn, engagement_id, delivery_id)
    require_latest(_latest_agreement(conn, engagement_id)["version"], delivery["agreement_version"])
    review = conn.execute("SELECT id FROM opc.delivery_reviews WHERE delivery_id=%s AND decision='approved'", (delivery_id,)).fetchone()
    if not review:
        raise DomainError(409, "REVIEW_REQUIRED", "交付必须先通过内部质检")
    if conn.execute("SELECT 1 FROM opc.delivery_publications WHERE delivery_id=%s", (delivery_id,)).fetchone():
        raise DomainError(409, "ALREADY_PUBLISHED", "交付曾经发布，撤回后必须提交并检查新版本")
    _lock_cleared_delivery_files(conn, delivery)
    row = conn.execute(
        "INSERT INTO opc.delivery_publications(delivery_id,review_id,published_by) VALUES (%s,%s,%s) RETURNING id",
        (delivery_id, review["id"], actor.id),
    ).fetchone()
    result = _change_state(conn, engagement, "awaiting_acceptance")
    _notify_parties(conn, engagement, "delivery.published", "交付已正式发布", "客户可查看最新交付并明确验收或要求修改。")
    return {**result, "publication_id": row["id"], "delivery_id": delivery_id, "delivery_version": delivery["version"]}


@router.post("/api/v1/admin/engagements/{engagement_id}/deliveries/{delivery_id}/withdraw", response_model=MutationResult,
             summary="撤回最新对客交付并要求新交付版本")
def withdraw_delivery(engagement_id: UUID, delivery_id: UUID, body: ReasonInput, conn: TxDep, actor: ActorDep):
    ensure_admin(actor, "quality_reviewer")
    engagement = _lock_engagement(conn, engagement_id)
    check_version(engagement, body.expected_version)
    require_state(engagement, "awaiting_acceptance", "revision")
    delivery = _latest_delivery(conn, engagement_id, delivery_id)
    publication = conn.execute(
        "SELECT id FROM opc.delivery_publications WHERE delivery_id=%s AND withdrawn_at IS NULL", (delivery_id,),
    ).fetchone()
    if not publication:
        raise DomainError(409, "NOT_PUBLISHED", "交付没有有效的对客发布记录")
    _withdraw_deliveries(conn, engagement_id, actor.id, body.reason)
    result = _change_state(conn, engagement, "revision")
    _notify_parties(conn, engagement, "delivery.withdrawn", "交付已撤回", "当前交付已撤回，等待提交并检查新版本。")
    return {**result, "delivery_id": delivery_id, "delivery_version": delivery["version"]}


@router.post("/api/v1/mobile/engagements/{engagement_id}/deliveries/{delivery_id}/acceptance", response_model=MutationResult,
             summary="客户明确验收或要求修改最新公开交付（不触发付款）")
def accept_delivery(engagement_id: UUID, delivery_id: UUID, body: AcceptanceInput, conn: TxDep, actor: ActorDep,
                    idempotency_key: IdempotencyKey):
    ensure_mobile(actor)
    if "customer" not in actor.roles:
        raise DomainError(403, "CUSTOMER_REQUIRED", "仅客户可作出验收决定")

    def action():
        engagement = _lock_engagement(conn, engagement_id)
        if engagement["customer_id"] != actor.id:
            _not_found()
        check_version(engagement, body.expected_version)
        require_state(engagement, "awaiting_acceptance")
        delivery = _latest_delivery(conn, engagement_id, delivery_id)
        require_latest(_latest_agreement(conn, engagement_id)["version"], delivery["agreement_version"])
        publication = conn.execute(
            """SELECT p.id FROM opc.delivery_publications p JOIN opc.delivery_reviews q ON q.id=p.review_id
            AND q.delivery_id=p.delivery_id WHERE p.delivery_id=%s AND p.withdrawn_at IS NULL AND q.decision='approved'""",
            (delivery_id,),
        ).fetchone()
        if not publication:
            raise DomainError(409, "PUBLICATION_REQUIRED", "仅最新有效对客发布交付可供验收")
        _lock_cleared_delivery_files(conn, delivery)
        row = conn.execute(
            "INSERT INTO opc.acceptance_decisions(delivery_id,customer_id,decision,feedback) VALUES (%s,%s,%s,%s) RETURNING id",
            (delivery_id, actor.id, body.decision, body.feedback),
        ).fetchone()
        accepted = body.decision == "accepted"
        result = _change_state(conn, engagement, "completed" if accepted else "revision", close=accepted)
        _notify_parties(conn, engagement, "delivery.accepted" if accepted else "delivery.revision_requested",
                        "客户已验收交付" if accepted else "客户要求修改", "客户已记录对当前交付版本的明确决定，请查看验收反馈。")
        return {**result, "acceptance_id": row["id"], "delivery_id": delivery_id, "delivery_version": delivery["version"]}

    return idempotent(conn, actor, "delivery.accept:" + str(delivery_id), idempotency_key, body.model_dump(mode="json"), action)
