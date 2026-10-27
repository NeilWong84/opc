"""Versioned intake, human review and a permission-filtered task hall.

All mutations use the caller's transaction. The database additionally protects
append-only evidence and the exact scope/review/publication relationships.
"""

from typing import Annotated, Literal
from uuid import UUID

from fastapi import APIRouter, Header, Query, Request
from fastapi.encoders import jsonable_encoder
from psycopg.types.json import Jsonb
from pydantic import Field, StringConstraints, field_validator, model_validator

from .auth import business_audit
from .common import check_version, emit, owned_files
from .deps import ActorDep, TxDep, ensure_admin, ensure_mobile, ensure_provider
from .errors import DomainError
from .idempotency import idempotent
from .models import Input, ReasonInput, VersionInput

router = APIRouter(tags=["需求、审核与大厅"])

ShortText = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=500)]
LongText = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=10000)]
Description = Annotated[str, StringConstraints(strip_whitespace=True, min_length=10, max_length=4000)]
AnswerText = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=4000)]
FileIds = Annotated[list[UUID], Field(max_length=20)]


class FileSelection(Input):
    file_ids: FileIds = Field(default_factory=list, description="显式选择的文件 ID；不会自动公开私有附件")

    @field_validator("file_ids")
    @classmethod
    def unique_files(cls, value):
        if len(set(value)) != len(value):
            raise ValueError("文件 ID 不能重复")
        return value


class ClassificationInput(FileSelection):
    platform_code: Annotated[str | None, Field(max_length=50)] = None
    development_type_code: Annotated[str | None, Field(max_length=50)] = None


class DraftInput(ClassificationInput):
    expected_version: int = Field(default=0, ge=0, description="首次保存为 0；已有草稿传其 row_version")
    description: Annotated[str, StringConstraints(max_length=4000)] = ""
    timing_text: Annotated[str, StringConstraints(max_length=500)] = ""
    budget_text: Annotated[str, StringConstraints(max_length=500)] = ""


class RequestContent(ClassificationInput):
    original_description: Description
    timing_text: ShortText
    budget_text: ShortText


class RequestCreate(RequestContent):
    service_code: Literal["development"] = "development"


class RequestRevision(RequestContent, VersionInput):
    pass


class ScopeCreate(FileSelection, VersionInput):
    title: ShortText
    public_summary: LongText
    category: ShortText
    goal: LongText
    included_scope: LongText
    excluded_scope: LongText
    deliverables: Annotated[list[ShortText], Field(min_length=1, max_length=50)]
    acceptance_criteria: Annotated[list[ShortText], Field(min_length=1, max_length=50)]
    duration_text: ShortText
    revision_terms: LongText


class ReviewCreate(ReasonInput):
    scope_version: int = Field(ge=1)
    kind: Literal["compliance", "technical"]
    decision: Literal["approved", "needs_info", "rejected"]
    question: AnswerText | None = None

    @model_validator(mode="after")
    def require_question(self):
        if self.decision == "needs_info" and not self.question:
            raise ValueError("退回补充时必须填写对客澄清问题")
        if self.decision != "needs_info" and self.question is not None:
            raise ValueError("只有退回补充决定可同时创建澄清问题")
        return self


class PublishInput(ReasonInput):
    scope_version: int = Field(ge=1, description="必须为当前已双审通过的范围版本")


class ClarificationCreate(VersionInput):
    question: AnswerText


class ClarificationAnswer(VersionInput):
    answer: AnswerText


REQUEST_FIELDS = (
    "id", "public_code", "service_code", "intake_status", "current_request_version",
    "current_scope_version", "row_version", "created_at", "updated_at",
)
SCOPE_FIELDS = (
    "version", "request_version", "title", "public_summary", "category", "goal",
    "included_scope", "excluded_scope", "deliverables", "acceptance_criteria",
    "duration_text", "revision_terms", "authored_at",
)
HALL_FIELDS = (
    "request_id", "public_code", "service_code", "scope_version", "title", "public_summary",
    "category", "goal", "included_scope", "excluded_scope", "deliverables",
    "acceptance_criteria", "duration_text", "revision_terms", "publication_id", "published_at",
)
FILE_FIELDS_SQL = "f.id AS file_id,f.original_name,f.kind,f.media_type,f.size_bytes,f.duration_ms,f.upload_status,f.scan_status"
ADMIN_READ_ROLES = ("operator", "compliance_reviewer", "technical_reviewer")

CLASSIFICATION_FIELDS = ("platform_code", "development_type_code")


def validate_classifications(conn, body, previous=None):
    for field, table in (("platform_code", "development_platforms"), ("development_type_code", "development_types")):
        code = getattr(body, field)
        if previous and code == previous.get(field):
            continue
        if code is not None and not conn.execute(
            f"SELECT 1 FROM opc.{table} WHERE code=%s AND enabled", (code,),
        ).fetchone():
            raise DomainError(422, "INVALID_CLASSIFICATION", "请选择有效的开发分类")


@router.get("/api/v1/mobile/request-classifications", summary="读取开发端及开发类型中日双语字典")
def request_classifications(conn: TxDep, actor: ActorDep):
    ensure_mobile(actor)
    return {
        key: conn.execute(
            f"SELECT code,name_zh,name_ja,enabled FROM opc.{table} ORDER BY sort_order,code",
        ).fetchall()
        for key, table in (("platforms", "development_platforms"), ("development_types", "development_types"))
    }


def project_fields(row: dict, fields: tuple[str, ...]) -> dict:
    """An allowlist keeps new internal database fields out of mobile responses."""
    return {key: row[key] for key in fields if key in row}


def require_customer(actor):
    ensure_mobile(actor)
    if "customer" not in actor.roles:
        raise DomainError(403, "CUSTOMER_REQUIRED", "该操作要求客户身份")


def require_open(row):
    if row["intake_status"] in ("withdrawn", "closed"):
        raise DomainError(409, "STATE_CONFLICT", "该需求已撤回或关闭")


def request_row(conn, request_id: UUID, actor=None, *, lock=False):
    sql = "SELECT * FROM opc.requests WHERE id=%s"
    params = [request_id]
    if actor is not None:
        sql += " AND customer_id=%s"
        params.append(actor.id)
    if lock:
        sql += " FOR UPDATE"
    row = conn.execute(sql, params).fetchone()
    if not row:
        raise DomainError(404, "NOT_FOUND", "需求不存在或不可访问")
    return row


def draft_lock(conn, actor_id):
    conn.execute("SELECT pg_advisory_xact_lock(hashtextextended(%s,0))", (f"draft:{actor_id}",))


def withdraw_publications(conn, request_id, actor_id, reason):
    conn.execute(
        "UPDATE opc.publications SET withdrawn_by=%s,withdrawn_at=now(),withdrawal_reason=%s "
        "WHERE request_id=%s AND withdrawn_at IS NULL", (actor_id, reason, request_id),
    )


def original_files(conn, request_id, version):
    return conn.execute(
        f"SELECT {FILE_FIELDS_SQL},l.sort_order FROM opc.request_files l JOIN opc.files f ON f.id=l.file_id "
        "WHERE l.request_id=%s AND l.request_version=%s ORDER BY l.sort_order,f.id",
        (request_id, version),
    ).fetchall()


def add_original(conn, request_id, version, actor_id, body: RequestContent, previous=None):
    validate_classifications(conn, body, previous)
    conn.execute(
        "INSERT INTO opc.request_versions(request_id,version,original_description,timing_text,budget_text,submitted_by,platform_code,development_type_code) "
        "VALUES (%s,%s,%s,%s,%s,%s,%s,%s)",
        (request_id, version, body.original_description, body.timing_text, body.budget_text, actor_id,
         body.platform_code, body.development_type_code),
    )
    for index, file_id in enumerate(body.file_ids):
        conn.execute(
            "INSERT INTO opc.request_files(request_id,request_version,file_id,sort_order) VALUES (%s,%s,%s,%s)",
            (request_id, version, file_id, index),
        )


def scope_references(conn, request_id, version):
    return conn.execute(
        f"SELECT {FILE_FIELDS_SQL},l.sort_order FROM opc.scope_files l JOIN opc.files f ON f.id=l.file_id "
        "WHERE l.request_id=%s AND l.scope_version=%s ORDER BY l.sort_order,f.id", (request_id, version),
    ).fetchall()


def customer_published_references(conn, request_id, version):
    """A customer's own intake does not disclose unreviewed reference packages."""
    return conn.execute(
        "SELECT f.id AS file_id,f.original_name,f.kind,f.media_type,f.size_bytes,f.duration_ms,s.sort_order "
        "FROM opc.publications p JOIN opc.publication_files l ON l.publication_id=p.id "
        "JOIN opc.scope_files s ON s.request_id=l.request_id AND s.scope_version=l.scope_version AND s.file_id=l.file_id "
        "JOIN opc.files f ON f.id=l.file_id JOIN opc.requests r ON r.id=p.request_id "
        "JOIN opc.scope_versions v ON v.request_id=r.id AND v.version=r.current_scope_version "
        "WHERE p.request_id=%s AND p.scope_version=%s AND p.withdrawn_at IS NULL "
        "AND p.scope_version=r.current_scope_version AND v.request_version=r.current_request_version "
        "AND r.intake_status IN ('submitted','in_review') AND f.upload_status='ready' AND f.scan_status='clean' "
        "ORDER BY s.sort_order,f.id", (request_id, version),
    ).fetchall()


def check_scope_files(conn, actor, row, file_ids):
    """Require an explicit selection from this original's files or author-owned files."""
    if not file_ids:
        return
    accessible = conn.execute(
        "SELECT f.id FROM opc.files f WHERE f.id=ANY(%s::uuid[]) "
        "AND f.upload_status='ready' AND f.scan_status='clean' AND "
        "(f.owner_id=%s OR EXISTS (SELECT 1 FROM opc.request_files l WHERE l.file_id=f.id "
        "AND l.request_id=%s AND l.request_version=%s)) FOR SHARE OF f",
        (file_ids, actor.id, row["id"], row["current_request_version"]),
    ).fetchall()
    if {item["id"] for item in accessible} != set(file_ids):
        raise DomainError(422, "INVALID_ATTACHMENTS", "参考资料必须属于当前原文附件或本人，且已完成上传与检查")


def detail(conn, row, *, admin=False):
    result = dict(row) if admin else project_fields(row, REQUEST_FIELDS)
    original = conn.execute(
        "SELECT version,original_description,timing_text,budget_text,submitted_at,platform_code,development_type_code "
        "FROM opc.request_versions WHERE request_id=%s AND version=%s",
        (row["id"], row["current_request_version"]),
    ).fetchone()
    result["original"] = original
    result["private_files"] = original_files(conn, row["id"], row["current_request_version"])
    scope = conn.execute(
        "SELECT * FROM opc.scope_versions WHERE request_id=%s AND version=%s",
        (row["id"], row["current_scope_version"]),
    ).fetchone() if row["current_scope_version"] else None
    result["scope"] = scope if admin or scope is None else project_fields(scope, SCOPE_FIELDS)
    if result["scope"] is not None:
        references = scope_references if admin else customer_published_references
        result["scope"]["reference_files"] = references(conn, row["id"], row["current_scope_version"])
    review_sql = "*" if admin else "id,scope_version,kind,decision,decided_at"
    result["reviews"] = conn.execute(
        f"SELECT {review_sql} FROM opc.review_decisions WHERE request_id=%s ORDER BY scope_version,decided_at,id",
        (row["id"],),
    ).fetchall()
    question_sql = "*" if admin else "id,request_version,question,asked_at,answer,answered_at"
    result["clarifications"] = conn.execute(
        f"SELECT {question_sql} FROM opc.clarifications WHERE request_id=%s ORDER BY asked_at,id", (row["id"],),
    ).fetchall()
    publication_sql = "*" if admin else "id,scope_version,published_at,withdrawn_at"
    result["publications"] = conn.execute(
        f"SELECT {publication_sql} FROM opc.publications WHERE request_id=%s ORDER BY published_at,id", (row["id"],),
    ).fetchall()
    return result


@router.get("/api/v1/mobile/draft", summary="读取本人需求草稿")
def get_draft(conn: TxDep, actor: ActorDep):
    require_customer(actor)
    row = conn.execute(
        "SELECT description,timing_text,budget_text,row_version,updated_at,platform_code,development_type_code FROM opc.request_drafts WHERE customer_id=%s",
        (actor.id,),
    ).fetchone()
    if row:
        row["files"] = conn.execute(
            f"SELECT {FILE_FIELDS_SQL},l.sort_order FROM opc.draft_files l JOIN opc.files f ON f.id=l.file_id "
            "WHERE l.customer_id=%s ORDER BY l.sort_order,f.id", (actor.id,),
        ).fetchall()
    return {"draft": row}


@router.put("/api/v1/mobile/draft", summary="保存本人需求草稿（版本校验）")
def save_draft(body: DraftInput, conn: TxDep, actor: ActorDep):
    require_customer(actor)
    validate_classifications(conn, body)
    draft_lock(conn, actor.id)
    row = conn.execute("SELECT * FROM opc.request_drafts WHERE customer_id=%s FOR UPDATE", (actor.id,)).fetchone()
    if row:
        check_version(row, body.expected_version)
    elif body.expected_version != 0:
        raise DomainError(409, "VERSION_CONFLICT", "草稿已不存在，请重新读取")
    owned_files(conn, actor.id, body.file_ids, allow_pending=True)
    if row:
        conn.execute(
            "UPDATE opc.request_drafts SET description=%s,timing_text=%s,budget_text=%s,platform_code=%s,development_type_code=%s WHERE customer_id=%s",
            (body.description, body.timing_text, body.budget_text, body.platform_code, body.development_type_code, actor.id),
        )
        conn.execute("DELETE FROM opc.draft_files WHERE customer_id=%s", (actor.id,))
    else:
        conn.execute(
            "INSERT INTO opc.request_drafts(customer_id,description,timing_text,budget_text,platform_code,development_type_code) VALUES (%s,%s,%s,%s,%s,%s)",
            (actor.id, body.description, body.timing_text, body.budget_text, body.platform_code, body.development_type_code),
        )
    for index, file_id in enumerate(body.file_ids):
        conn.execute("INSERT INTO opc.draft_files(customer_id,file_id,sort_order) VALUES (%s,%s,%s)", (actor.id, file_id, index))
    return get_draft(conn, actor)


@router.delete("/api/v1/mobile/draft", summary="删除本人需求草稿")
def delete_draft(conn: TxDep, actor: ActorDep, expected_version: Annotated[int, Query(ge=1)]):
    require_customer(actor)
    draft_lock(conn, actor.id)
    row = conn.execute("SELECT * FROM opc.request_drafts WHERE customer_id=%s FOR UPDATE", (actor.id,)).fetchone()
    if not row:
        raise DomainError(404, "NOT_FOUND", "草稿不存在")
    check_version(row, expected_version)
    conn.execute("DELETE FROM opc.draft_files WHERE customer_id=%s", (actor.id,))
    conn.execute("DELETE FROM opc.request_drafts WHERE customer_id=%s", (actor.id,))
    return {"deleted": True}


@router.post("/api/v1/mobile/requests", status_code=201, summary="提交开发需求（幂等、仅待审）")
def create_request(
    body: RequestCreate, conn: TxDep, actor: ActorDep,
    idempotency_key: Annotated[str, Header(alias="Idempotency-Key", min_length=8, max_length=128)],
):
    require_customer(actor)

    def action():
        owned_files(conn, actor.id, body.file_ids, allow_pending=True)
        row = conn.execute(
            "INSERT INTO opc.requests(customer_id,service_code) VALUES (%s,%s) RETURNING *", (actor.id, body.service_code),
        ).fetchone()
        add_original(conn, row["id"], 1, actor.id, body)
        draft_lock(conn, actor.id)
        conn.execute("DELETE FROM opc.draft_files WHERE customer_id=%s", (actor.id,))
        conn.execute("DELETE FROM opc.request_drafts WHERE customer_id=%s", (actor.id,))
        emit(conn, actor.id, "request.submitted", "需求已提交", "需求已进入受理流程，审核通过并发布后才会进入大厅。", {"request_id": str(row["id"])})
        return jsonable_encoder(detail(conn, row))

    return idempotent(conn, actor, "request.create", idempotency_key, body.model_dump(mode="json"), action)


@router.get("/api/v1/mobile/requests", summary="分页读取本人需求与受理状态")
def my_requests(
    conn: TxDep, actor: ActorDep, limit: Annotated[int, Query(ge=1, le=100)] = 20,
    offset: Annotated[int, Query(ge=0, le=100000)] = 0,
    platform_code: Annotated[str | None, Query(max_length=50)] = None,
    development_type_code: Annotated[str | None, Query(max_length=50)] = None,
):
    require_customer(actor)
    join = " FROM opc.requests r JOIN opc.request_versions v ON v.request_id=r.id AND v.version=r.current_request_version"
    where = " WHERE r.customer_id=%s AND (%s::text IS NULL OR COALESCE(v.platform_code,'unclassified')=%s) AND (%s::text IS NULL OR COALESCE(v.development_type_code,'unclassified')=%s)"
    params = (actor.id, platform_code, platform_code, development_type_code, development_type_code)
    count = conn.execute("SELECT count(*) AS total" + join + where, params).fetchone()["total"]
    rows = conn.execute(
        "SELECT r.*,v.original_description,v.platform_code,v.development_type_code" + join + where +
        " ORDER BY r.created_at DESC,r.id LIMIT %s OFFSET %s", params + (limit, offset),
    ).fetchall()
    return {"items": [project_fields(row, REQUEST_FIELDS + ("original_description",) + CLASSIFICATION_FIELDS) for row in rows], "total": count, "limit": limit, "offset": offset}


@router.get("/api/v1/mobile/requests/{request_id}", summary="读取本人需求详情（排除内部审核备注）")
def customer_detail(request_id: UUID, conn: TxDep, actor: ActorDep):
    require_customer(actor)
    return detail(conn, request_row(conn, request_id, actor))


@router.get("/api/v1/mobile/requests/{request_id}/revisions", summary="读取本人原始需求及附件版本历史")
def customer_revisions(request_id: UUID, conn: TxDep, actor: ActorDep):
    require_customer(actor)
    request_row(conn, request_id, actor)
    rows = conn.execute(
        "SELECT version,original_description,timing_text,budget_text,submitted_at,platform_code,development_type_code FROM opc.request_versions "
        "WHERE request_id=%s ORDER BY version DESC", (request_id,),
    ).fetchall()
    for row in rows:
        row["private_files"] = original_files(conn, request_id, row["version"])
    return {"items": rows}


@router.post("/api/v1/mobile/requests/{request_id}/revisions", status_code=201, summary="补充原文为新版本并使旧审核发布失效")
def revise_request(request_id: UUID, body: RequestRevision, conn: TxDep, actor: ActorDep):
    require_customer(actor)
    row = request_row(conn, request_id, actor, lock=True)
    check_version(row, body.expected_version)
    require_open(row)
    owned_files(conn, actor.id, body.file_ids, allow_pending=True)
    new_version = row["current_request_version"] + 1
    previous = conn.execute(
        "SELECT platform_code,development_type_code FROM opc.request_versions WHERE request_id=%s AND version=%s",
        (request_id, row["current_request_version"]),
    ).fetchone()
    content = body.model_copy(update={field: previous[field] for field in CLASSIFICATION_FIELDS if field not in body.model_fields_set})
    add_original(conn, request_id, new_version, actor.id, content, previous)
    withdraw_publications(conn, request_id, actor.id, "客户补充原始需求，原发布版本失效")
    unanswered = conn.execute("SELECT 1 FROM opc.clarifications WHERE request_id=%s AND answer IS NULL LIMIT 1", (request_id,)).fetchone()
    row = conn.execute(
        "UPDATE opc.requests SET current_request_version=%s,current_scope_version=NULL,intake_status=%s WHERE id=%s RETURNING *",
        (new_version, "needs_info" if unanswered else "submitted", request_id),
    ).fetchone()
    emit(conn, actor.id, "request.revised", "需求已补充", "新版本需重新整理及审核。", {"request_id": str(request_id), "request_version": new_version})
    return detail(conn, row)


@router.post("/api/v1/mobile/requests/{request_id}/withdraw", summary="撤回本人尚无有效合作的需求")
def withdraw_request(request_id: UUID, body: ReasonInput, conn: TxDep, actor: ActorDep):
    require_customer(actor)
    row = request_row(conn, request_id, actor, lock=True)
    check_version(row, body.expected_version)
    require_open(row)
    if conn.execute("SELECT 1 FROM opc.engagements WHERE request_id=%s AND closed_at IS NULL", (request_id,)).fetchone():
        raise DomainError(409, "STATE_CONFLICT", "存在有效合作，须先通过合作取消流程处理")
    withdraw_publications(conn, request_id, actor.id, body.reason)
    row = conn.execute("UPDATE opc.requests SET intake_status='withdrawn' WHERE id=%s RETURNING *", (request_id,)).fetchone()
    business_audit(conn, "requests", request_id, body.reason)
    emit(conn, actor.id, "request.withdrawn", "需求已撤回", "需求已停止受理并从大厅下架。", {"request_id": str(request_id)})
    return detail(conn, row)


@router.get("/api/v1/mobile/requests/{request_id}/clarifications", summary="读取本人需求澄清问答")
def customer_clarifications(request_id: UUID, conn: TxDep, actor: ActorDep):
    require_customer(actor)
    request_row(conn, request_id, actor)
    return {"items": conn.execute(
        "SELECT id,request_version,question,asked_at,answer,answered_at FROM opc.clarifications WHERE request_id=%s ORDER BY asked_at,id",
        (request_id,),
    ).fetchall()}


@router.post("/api/v1/mobile/requests/{request_id}/clarifications/{clarification_id}/answer", summary="回答澄清并创建待复审原文版本")
def answer_clarification(request_id: UUID, clarification_id: UUID, body: ClarificationAnswer, conn: TxDep, actor: ActorDep):
    require_customer(actor)
    row = request_row(conn, request_id, actor, lock=True)
    check_version(row, body.expected_version)
    require_open(row)
    question = conn.execute("SELECT * FROM opc.clarifications WHERE id=%s AND request_id=%s FOR UPDATE", (clarification_id, request_id)).fetchone()
    if not question:
        raise DomainError(404, "NOT_FOUND", "澄清问题不存在")
    if question["answer"] is not None:
        raise DomainError(409, "STATE_CONFLICT", "该问题已回答")
    conn.execute("UPDATE opc.clarifications SET answer=%s,answered_by=%s,answered_at=now() WHERE id=%s", (body.answer, actor.id, clarification_id))
    version = row["current_request_version"] + 1
    conn.execute(
        "INSERT INTO opc.request_versions(request_id,version,original_description,timing_text,budget_text,submitted_by,platform_code,development_type_code) "
        "SELECT request_id,%s,original_description,timing_text,budget_text,%s,platform_code,development_type_code FROM opc.request_versions WHERE request_id=%s AND version=%s",
        (version, actor.id, request_id, row["current_request_version"]),
    )
    conn.execute(
        "INSERT INTO opc.request_files(request_id,request_version,file_id,sort_order) "
        "SELECT request_id,%s,file_id,sort_order FROM opc.request_files WHERE request_id=%s AND request_version=%s",
        (version, request_id, row["current_request_version"]),
    )
    withdraw_publications(conn, request_id, actor.id, "客户回答澄清，新版本需重新审核")
    unanswered = conn.execute("SELECT 1 FROM opc.clarifications WHERE request_id=%s AND answer IS NULL LIMIT 1", (request_id,)).fetchone()
    row = conn.execute(
        "UPDATE opc.requests SET current_request_version=%s,current_scope_version=NULL,intake_status=%s WHERE id=%s RETURNING *",
        (version, "needs_info" if unanswered else "submitted", request_id),
    ).fetchone()
    emit(conn, actor.id, "clarification.answered", "补充已收到", "回答已保存，范围需重新整理及审核。", {"request_id": str(request_id), "request_version": version})
    return detail(conn, row)


@router.get("/api/v1/admin/requests", summary="后台需求受理队列与搜索")
def admin_requests(
    conn: TxDep, actor: ActorDep, limit: Annotated[int, Query(ge=1, le=100)] = 20,
    offset: Annotated[int, Query(ge=0, le=100000)] = 0,
    status: Literal["submitted", "needs_info", "in_review", "withdrawn", "closed"] | None = None,
    q: Annotated[str, Query(max_length=200)] = "",
):
    ensure_admin(actor, *ADMIN_READ_ROLES)
    where = " WHERE (%s::text IS NULL OR r.intake_status=%s) AND (%s='' OR strpos(lower(r.public_code||' '||v.original_description),lower(%s))>0)"
    params = (status, status, q, q)
    join = " FROM opc.requests r JOIN opc.request_versions v ON v.request_id=r.id AND v.version=r.current_request_version"
    total = conn.execute("SELECT count(*) AS total" + join + where, params).fetchone()["total"]
    rows = conn.execute(
        "SELECT r.*,v.original_description" + join + where + " ORDER BY r.updated_at DESC,r.id LIMIT %s OFFSET %s",
        params + (limit, offset),
    ).fetchall()
    return {"items": rows, "total": total, "limit": limit, "offset": offset}


@router.get("/api/v1/admin/requests/{request_id}", summary="后台需求、私有附件与审核发布证据")
def admin_detail(request_id: UUID, conn: TxDep, actor: ActorDep):
    ensure_admin(actor, *ADMIN_READ_ROLES)
    return detail(conn, request_row(conn, request_id), admin=True)


@router.get("/api/v1/admin/requests/{request_id}/scopes", summary="后台技术整理版本与显式参考资料")
def admin_scopes(request_id: UUID, conn: TxDep, actor: ActorDep):
    ensure_admin(actor, *ADMIN_READ_ROLES)
    request_row(conn, request_id)
    rows = conn.execute("SELECT * FROM opc.scope_versions WHERE request_id=%s ORDER BY version DESC", (request_id,)).fetchall()
    for row in rows:
        row["reference_files"] = scope_references(conn, request_id, row["version"])
    return {"items": rows}


@router.post("/api/v1/admin/requests/{request_id}/scopes", status_code=201, summary="新建并激活技术整理版本（旧审核发布失效）")
def create_scope(request_id: UUID, body: ScopeCreate, conn: TxDep, actor: ActorDep):
    ensure_admin(actor, "technical_reviewer")
    row = request_row(conn, request_id, lock=True)
    check_version(row, body.expected_version)
    require_open(row)
    if conn.execute("SELECT 1 FROM opc.clarifications WHERE request_id=%s AND answer IS NULL LIMIT 1", (request_id,)).fetchone():
        raise DomainError(409, "CLARIFICATION_PENDING", "仍有未回答澄清问题，暂不可激活整理版本")
    check_scope_files(conn, actor, row, body.file_ids)
    version = conn.execute("SELECT coalesce(max(version),0)+1 AS version FROM opc.scope_versions WHERE request_id=%s", (request_id,)).fetchone()["version"]
    conn.execute(
        "INSERT INTO opc.scope_versions(request_id,version,request_version,title,public_summary,category,goal,included_scope,excluded_scope,"
        "deliverables,acceptance_criteria,duration_text,revision_terms,authored_by) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)",
        (request_id, version, row["current_request_version"], body.title, body.public_summary, body.category, body.goal,
         body.included_scope, body.excluded_scope, Jsonb(body.deliverables), Jsonb(body.acceptance_criteria), body.duration_text, body.revision_terms, actor.id),
    )
    for index, file_id in enumerate(body.file_ids):
        conn.execute("INSERT INTO opc.scope_files(request_id,scope_version,file_id,sort_order) VALUES (%s,%s,%s,%s)", (request_id, version, file_id, index))
    withdraw_publications(conn, request_id, actor.id, "整理范围或参考资料已改版，须重新双审")
    row = conn.execute("UPDATE opc.requests SET current_scope_version=%s,intake_status='in_review' WHERE id=%s RETURNING *", (version, request_id)).fetchone()
    return detail(conn, row, admin=True)


@router.get("/api/v1/admin/requests/{request_id}/reviews", summary="读取不可覆盖的双审核记录")
def admin_reviews(request_id: UUID, conn: TxDep, actor: ActorDep):
    ensure_admin(actor, *ADMIN_READ_ROLES)
    request_row(conn, request_id)
    return {"items": conn.execute("SELECT * FROM opc.review_decisions WHERE request_id=%s ORDER BY scope_version,decided_at,id", (request_id,)).fetchall()}


def ask_question(conn, row, actor_id, question):
    return conn.execute(
        "INSERT INTO opc.clarifications(request_id,request_version,question,asked_by) VALUES (%s,%s,%s,%s) RETURNING *",
        (row["id"], row["current_request_version"], question, actor_id),
    ).fetchone()


@router.post("/api/v1/admin/requests/{request_id}/reviews", status_code=201, summary="人工合规或技术审核当前范围版本")
def create_review(request_id: UUID, body: ReviewCreate, conn: TxDep, actor: ActorDep):
    ensure_admin(actor, "compliance_reviewer" if body.kind == "compliance" else "technical_reviewer")
    row = request_row(conn, request_id, lock=True)
    check_version(row, body.expected_version)
    require_open(row)
    if body.scope_version != row["current_scope_version"]:
        raise DomainError(409, "VERSION_CONFLICT", "只能审核当前技术整理版本")
    if conn.execute("SELECT 1 FROM opc.review_decisions WHERE request_id=%s AND scope_version=%s AND kind=%s", (request_id, body.scope_version, body.kind)).fetchone():
        raise DomainError(409, "REVIEW_EXISTS", "当前范围此类审核已记录，修改结论需新建范围版本")
    conn.execute(
        "INSERT INTO opc.review_decisions(request_id,scope_version,kind,decision,reviewer_id,reason) VALUES (%s,%s,%s,%s,%s,%s)",
        (request_id, body.scope_version, body.kind, body.decision, actor.id, body.reason),
    )
    state = row["intake_status"]
    if body.decision == "needs_info":
        ask_question(conn, row, actor.id, body.question)
        state = "needs_info"
    elif body.decision == "rejected":
        state = "closed"
    if body.decision != "approved":
        withdraw_publications(conn, request_id, actor.id, "当前审核未通过，停止发布")
    row = conn.execute("UPDATE opc.requests SET intake_status=%s WHERE id=%s RETURNING *", (state, request_id)).fetchone()
    emit(conn, row["customer_id"], "request.reviewed", "审核进度已更新", "请查看需求状态与需要补充的问题。", {"request_id": str(request_id), "decision": body.decision, "kind": body.kind})
    return detail(conn, row, admin=True)


@router.post("/api/v1/admin/requests/{request_id}/publish", status_code=201, summary="将当前同版本双审通过的范围发布大厅")
def publish_request(request_id: UUID, body: PublishInput, conn: TxDep, actor: ActorDep):
    ensure_admin(actor, "operator")
    row = request_row(conn, request_id, lock=True)
    check_version(row, body.expected_version)
    require_open(row)
    if body.scope_version != row["current_scope_version"]:
        raise DomainError(409, "VERSION_CONFLICT", "发布范围已过期")
    if row["intake_status"] == "needs_info":
        raise DomainError(409, "STATE_CONFLICT", "需求仍待客户补充")
    if conn.execute("SELECT 1 FROM opc.publications WHERE request_id=%s AND withdrawn_at IS NULL", (request_id,)).fetchone():
        raise DomainError(409, "ALREADY_PUBLISHED", "当前需求已发布")
    if conn.execute("SELECT 1 FROM opc.engagements WHERE request_id=%s AND closed_at IS NULL", (request_id,)).fetchone():
        raise DomainError(409, "STATE_CONFLICT", "需求已有有效合作")
    decisions = conn.execute("SELECT id,kind FROM opc.review_decisions WHERE request_id=%s AND scope_version=%s AND decision='approved'", (request_id, body.scope_version)).fetchall()
    reviews = {item["kind"]: item["id"] for item in decisions}
    if set(reviews) != {"compliance", "technical"}:
        raise DomainError(409, "REVIEW_REQUIRED", "发布必须具备当前范围的合规与技术通过记录")
    publication = conn.execute(
        "INSERT INTO opc.publications(request_id,scope_version,compliance_review_id,technical_review_id,published_by) VALUES (%s,%s,%s,%s,%s) RETURNING *",
        (request_id, body.scope_version, reviews["compliance"], reviews["technical"], actor.id),
    ).fetchone()
    business_audit(conn, "publications", publication["id"], body.reason)
    conn.execute(
        "INSERT INTO opc.publication_files(publication_id,request_id,scope_version,file_id) SELECT %s,request_id,scope_version,file_id "
        "FROM opc.scope_files WHERE request_id=%s AND scope_version=%s", (publication["id"], request_id, body.scope_version),
    )
    row = conn.execute("UPDATE opc.requests SET intake_status='in_review' WHERE id=%s RETURNING *", (request_id,)).fetchone()
    emit(conn, row["customer_id"], "request.published", "需求已发布", "审核通过的整理范围已发布至获授权的任务大厅。", {"request_id": str(request_id), "publication_id": str(publication["id"])})
    return detail(conn, row, admin=True)


@router.post("/api/v1/admin/requests/{request_id}/publication/withdraw", summary="下架当前发布并保留审核发布历史")
def unpublish_request(request_id: UUID, body: ReasonInput, conn: TxDep, actor: ActorDep):
    ensure_admin(actor, "operator")
    row = request_row(conn, request_id, lock=True)
    check_version(row, body.expected_version)
    if not conn.execute("SELECT 1 FROM opc.publications WHERE request_id=%s AND withdrawn_at IS NULL", (request_id,)).fetchone():
        raise DomainError(409, "NOT_PUBLISHED", "当前没有有效发布")
    withdraw_publications(conn, request_id, actor.id, body.reason)
    row = conn.execute("UPDATE opc.requests SET intake_status=intake_status WHERE id=%s RETURNING *", (request_id,)).fetchone()
    emit(conn, row["customer_id"], "publication.withdrawn", "需求发布已下架", "当前发布已退出任务大厅。", {"request_id": str(request_id)})
    return detail(conn, row, admin=True)


@router.get("/api/v1/admin/requests/{request_id}/clarifications", summary="后台读取澄清历史与实际操作人")
def admin_clarifications(request_id: UUID, conn: TxDep, actor: ActorDep):
    ensure_admin(actor, *ADMIN_READ_ROLES)
    request_row(conn, request_id)
    return {"items": conn.execute("SELECT * FROM opc.clarifications WHERE request_id=%s ORDER BY asked_at,id", (request_id,)).fetchall()}


@router.post("/api/v1/admin/requests/{request_id}/clarifications", status_code=201, summary="向客户提出澄清并暂停当前发布")
def create_clarification(request_id: UUID, body: ClarificationCreate, conn: TxDep, actor: ActorDep):
    ensure_admin(actor, *ADMIN_READ_ROLES)
    row = request_row(conn, request_id, lock=True)
    check_version(row, body.expected_version)
    require_open(row)
    ask_question(conn, row, actor.id, body.question)
    withdraw_publications(conn, request_id, actor.id, "等待客户澄清，暂停大厅发布")
    row = conn.execute("UPDATE opc.requests SET intake_status='needs_info' WHERE id=%s RETURNING *", (request_id,)).fetchone()
    emit(conn, row["customer_id"], "clarification.requested", "需求需要补充", "请在需求详情回答澄清问题。", {"request_id": str(request_id)})
    return detail(conn, row, admin=True)


def authorize_hall(request, conn, actor):
    ensure_mobile(actor)
    audience = request.app.state.settings.hall_audience
    if audience == "disabled":
        raise DomainError(503, "HALL_DISABLED", "任务大厅尚未开放")
    if audience == "internal":
        ensure_provider(conn, actor)
    elif audience != "authenticated":
        raise DomainError(503, "HALL_DISABLED", "任务大厅受众配置无效")


@router.get("/api/v1/mobile/hall", summary="分页搜索有效双审发布（默认仅内部授权账号）")
def hall(
    request: Request, conn: TxDep, actor: ActorDep,
    limit: Annotated[int, Query(ge=1, le=100)] = 20, offset: Annotated[int, Query(ge=0, le=100000)] = 0,
    q: Annotated[str, Query(max_length=200)] = "", category: Annotated[str | None, Query(max_length=100)] = None,
):
    authorize_hall(request, conn, actor)
    where = " WHERE (%s='' OR strpos(lower(h.title||' '||h.public_summary),lower(%s))>0) AND (%s::text IS NULL OR h.category=%s)"
    params = (q, q, category, category)
    total = conn.execute("SELECT count(*) AS total FROM opc.hall_requests h" + where, params).fetchone()["total"]
    rows = conn.execute(
        "SELECT h.*,(SELECT count(*) FROM opc.hall_reference_files f WHERE f.publication_id=h.publication_id) AS reference_count "
        "FROM opc.hall_requests h" + where + " ORDER BY h.published_at DESC,h.request_id LIMIT %s OFFSET %s",
        params + (limit, offset),
    ).fetchall()
    return {"items": [project_fields(row, HALL_FIELDS + ("reference_count",)) for row in rows], "total": total, "limit": limit, "offset": offset}


@router.get("/api/v1/mobile/hall/{request_id}", summary="读取合法大厅详情及该发布版本参考资料")
def hall_detail(request_id: UUID, request: Request, conn: TxDep, actor: ActorDep):
    authorize_hall(request, conn, actor)
    row = conn.execute("SELECT * FROM opc.hall_requests WHERE request_id=%s", (request_id,)).fetchone()
    if not row:
        raise DomainError(404, "NOT_FOUND", "大厅需求不存在或不可访问")
    result = project_fields(row, HALL_FIELDS)
    result["references"] = conn.execute(
        "SELECT file_id,original_name,kind,media_type,size_bytes,duration_ms,sort_order FROM opc.hall_reference_files "
        "WHERE publication_id=%s ORDER BY sort_order,file_id", (row["publication_id"],),
    ).fetchall()
    return result
