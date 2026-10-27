import codecs
import hashlib
import mimetypes
from pathlib import Path
from typing import Annotated, Literal
from uuid import UUID, uuid4

from fastapi import APIRouter, File, Query, Request, UploadFile
from fastapi.responses import FileResponse

from .auth import business_audit
from .common import check_version
from .deps import ActorDep, TxDep, ensure_admin, ensure_provider
from .errors import DomainError
from .models import ReasonInput
from .document_preview import OFFICE_EXTENSIONS, office_pdf

router = APIRouter(tags=["私有文件与预览"])
SAFE_COLUMNS = "id,original_name,media_type,kind,size_bytes,sha256,upload_status,scan_status,duration_ms,row_version"


def file_kind(name):
    ext = Path(name).suffix.lower()
    for kind, values in {
        "image": {".jpg", ".jpeg", ".png", ".webp", ".gif"}, "video": {".mp4", ".m4v", ".mov", ".webm"},
        "document": {".doc", ".docx"}, "spreadsheet": {".xls", ".xlsx", ".csv"},
        "presentation": {".ppt", ".pptx"}, "pdf": {".pdf"}, "text": {".txt", ".md"},
    }.items():
        if ext in values:
            return kind
    return "other"


def safe_name(name):
    if not name or len(name) > 240 or any(c in name for c in ('/', '\\', '\r', '\n', '\x00')) or not name.strip():
        raise DomainError(422, "INVALID_FILENAME", "文件名无效")
    return name


def storage_path(root, key):
    # Only our random keys are ever interpreted as filesystem paths.
    try:
        key = UUID(str(key)).hex
    except ValueError:
        raise DomainError(503, "STORAGE_UNAVAILABLE", "文件存储标识无效") from None
    root = Path(root).resolve()
    path = (root / key).resolve()
    if path.parent != root:
        raise DomainError(503, "STORAGE_UNAVAILABLE", "文件存储不可用")
    return path


def hall_allowed(conn, actor, settings):
    if actor.audience != "mobile" or settings.hall_audience == "disabled":
        return False
    if settings.hall_audience == "authenticated":
        return True
    try:
        ensure_provider(conn, actor)
        return True
    except DomainError:
        return False


def can_read_file(conn, actor, file_id, settings):
    row = conn.execute("SELECT owner_id FROM opc.files WHERE id=%s", (file_id,)).fetchone()
    if not row:
        return False
    if row["owner_id"] == actor.id:
        return True
    if actor.audience == "admin":
        if actor.roles & {"administrator", "operator"}:
            return True
        if actor.roles & {"technical_reviewer", "compliance_reviewer"}:
            if conn.execute("SELECT 1 FROM opc.request_files WHERE file_id=%s UNION ALL SELECT 1 FROM opc.scope_files WHERE file_id=%s LIMIT 1", (file_id, file_id)).fetchone():
                return True
        if "quality_reviewer" in actor.roles:
            return bool(conn.execute("SELECT 1 FROM opc.deliveries WHERE source_file_id=%s UNION ALL SELECT 1 FROM opc.delivery_files WHERE file_id=%s LIMIT 1", (file_id, file_id)).fetchone())
        return False
    # Metadata (including names/counts) uses the same readiness boundary as content.
    if not conn.execute("SELECT 1 FROM opc.files WHERE id=%s AND upload_status='ready' AND scan_status='clean'", (file_id,)).fetchone():
        return False
    if hall_allowed(conn, actor, settings) and conn.execute("SELECT 1 FROM opc.hall_reference_files WHERE file_id=%s", (file_id,)).fetchone():
        return True
    # The owning customer can access their current published reference package even
    # when the hall is internal-only or the task has already entered cooperation.
    if conn.execute("""SELECT 1 FROM opc.requests r JOIN opc.publications p ON p.request_id=r.id
        AND p.scope_version=r.current_scope_version AND p.withdrawn_at IS NULL
        JOIN opc.scope_versions s ON s.request_id=r.id AND s.version=p.scope_version AND s.request_version=r.current_request_version
        JOIN opc.publication_files f ON f.publication_id=p.id
        WHERE r.customer_id=%s AND f.file_id=%s AND r.intake_status IN ('submitted','in_review','closed')""", (actor.id, file_id)).fetchone():
        return True
    # Agreed scope snapshots remain readable to the owning customer after hall
    # withdrawal/newer scope versions, just as they do to the current provider.
    if conn.execute("""SELECT 1 FROM opc.requests r JOIN opc.engagements e ON e.request_id=r.id
        JOIN opc.agreement_versions g ON g.engagement_id=e.id
        JOIN opc.scope_files f ON f.request_id=g.request_id AND f.scope_version=g.scope_version
        WHERE r.customer_id=%s AND f.file_id=%s""", (actor.id, file_id)).fetchone():
        return True
    # A customer sees only currently published latest delivery attachments, including after acceptance.
    if conn.execute("""SELECT 1 FROM opc.deliveries d JOIN opc.engagements e ON e.id=d.engagement_id
        JOIN opc.requests r ON r.id=e.request_id JOIN opc.delivery_publications p ON p.delivery_id=d.id
        JOIN opc.delivery_reviews q ON q.id=p.review_id AND q.delivery_id=d.id AND q.decision='approved'
        WHERE r.customer_id=%s AND p.withdrawn_at IS NULL
        AND d.agreement_version=(SELECT max(g.version) FROM opc.agreement_versions g WHERE g.engagement_id=e.id)
        AND NOT EXISTS(SELECT 1 FROM opc.deliveries n WHERE n.engagement_id=e.id AND n.version>d.version)
        AND NOT EXISTS(SELECT 1 FROM opc.delivery_files df JOIN opc.files f ON f.id=df.file_id
            WHERE df.delivery_id=d.id AND (f.upload_status<>'ready' OR f.scan_status<>'clean'))
        AND (d.source_file_id IS NULL OR EXISTS(SELECT 1 FROM opc.files f WHERE f.id=d.source_file_id AND f.upload_status='ready' AND f.scan_status='clean'))
        AND (d.source_file_id=%s OR EXISTS(SELECT 1 FROM opc.delivery_files f WHERE f.delivery_id=d.id AND f.file_id=%s))""",
                    (actor.id, file_id, file_id)).fetchone():
        return True
    # Current provider can read explicit reviewed references in the cooperation, never raw customer attachments.
    if "provider" in actor.roles:
        try:
            ensure_provider(conn, actor)
        except DomainError:
            return False
        if conn.execute("""SELECT 1 FROM opc.assignments a JOIN opc.deliveries d ON d.engagement_id=a.engagement_id
            WHERE a.provider_id=%s AND a.ended_at IS NULL AND
            (d.source_file_id=%s OR EXISTS(SELECT 1 FROM opc.delivery_files f WHERE f.delivery_id=d.id AND f.file_id=%s))""",
                        (actor.id, file_id, file_id)).fetchone():
            return True
        return bool(conn.execute("""SELECT 1 FROM opc.assignments a
            JOIN opc.agreement_versions g ON g.engagement_id=a.engagement_id
            JOIN opc.scope_files f ON f.request_id=g.request_id AND f.scope_version=g.scope_version
            WHERE a.provider_id=%s AND a.ended_at IS NULL AND f.file_id=%s""", (actor.id, file_id)).fetchone())
    return False


def readable_file(conn, actor, file_id, settings):
    if not can_read_file(conn, actor, file_id, settings):
        raise DomainError(404, "NOT_FOUND", "文件不存在或无权访问")
    return conn.execute(f"SELECT {SAFE_COLUMNS},storage_key FROM opc.files WHERE id=%s", (file_id,)).fetchone()


@router.post("/api/v1/mobile/files", status_code=201, summary="上传私有原文件（等待检查）")
@router.post("/api/v1/admin/files", status_code=201, summary="管理端上传私有原文件（等待检查）")
def upload(request: Request, actor: ActorDep, conn: TxDep, file: Annotated[UploadFile, File()]):
    name = safe_name(file.filename)
    settings = request.app.state.settings
    key = uuid4().hex
    target = storage_path(settings.storage_root, key)
    target.parent.mkdir(parents=True, exist_ok=True)
    digest, size = hashlib.sha256(), 0
    try:
        with target.open("xb") as out:
            while chunk := file.file.read(65536):
                size += len(chunk)
                if size > settings.upload_limit_bytes:
                    raise DomainError(413, "FILE_TOO_LARGE", "文件超过配置的上传上限")
                digest.update(chunk)
                out.write(chunk)
        if not size:
            raise DomainError(422, "EMPTY_FILE", "不能上传空文件")
        row = conn.execute(f"""INSERT INTO opc.files(owner_id,original_name,media_type,kind,storage_key,
            size_bytes,sha256,upload_status,scan_status) VALUES (%s,%s,%s,%s,%s,%s,%s,'ready','pending')
            RETURNING {SAFE_COLUMNS}""", (actor.id, name, (mimetypes.guess_type(name)[0] or file.content_type or "application/octet-stream")[:200],
                                         file_kind(name), key, size, digest.hexdigest())).fetchone()
        request.state.uploaded_keys.append(key)
        return row
    except Exception:
        target.unlink(missing_ok=True)
        raise
    finally:
        file.file.close()


class ScanInput(ReasonInput):
    decision: Literal["clean", "rejected"]


@router.get("/api/v1/mobile/files", summary="本人上传文件及检查状态")
@router.get("/api/v1/admin/files", summary="运营文件检查队列（包含未关联的上传）")
def files(actor: ActorDep, conn: TxDep,
          scan_status: Literal["pending", "clean", "rejected", "failed"] | None = None,
          limit: int = Query(30, ge=1, le=100), offset: int = Query(0, ge=0)):
    if actor.audience == "admin":
        ensure_admin(actor, "operator")
        owner = None
    else:
        owner = actor.id
    rows = conn.execute(f"""SELECT {SAFE_COLUMNS} FROM opc.files
        WHERE (%s::uuid IS NULL OR owner_id=%s) AND (%s::text IS NULL OR scan_status=%s)
        ORDER BY created_at DESC,id LIMIT %s OFFSET %s""",
        (owner, owner, scan_status, scan_status, limit, offset)).fetchall()
    return {"items": rows, "limit": limit, "offset": offset}


@router.post("/api/v1/admin/files/{file_id}/inspection", summary="记录实际文件安全检查结论（需证据，不自动扫描）")
def inspect_file(file_id: UUID, body: ScanInput, actor: ActorDep, conn: TxDep):
    ensure_admin(actor, "operator")
    row = conn.execute("SELECT * FROM opc.files WHERE id=%s FOR UPDATE", (file_id,)).fetchone()
    check_version(row, body.expected_version)
    if row["upload_status"] != "ready":
        raise DomainError(409, "FILE_NOT_READY", "文件尚未上传完成")
    result = conn.execute(f"UPDATE opc.files SET scan_status=%s WHERE id=%s RETURNING {SAFE_COLUMNS}",
                          (body.decision, file_id)).fetchone()
    business_audit(conn, "files", file_id, body.reason)
    return result


@router.get("/api/v1/mobile/files/{file_id}", summary="读取有权访问的文件元数据")
@router.get("/api/v1/admin/files/{file_id}", summary="读取管理权限内文件元数据")
def metadata(file_id: UUID, request: Request, actor: ActorDep, conn: TxDep):
    row = readable_file(conn, actor, file_id, request.app.state.settings)
    row.pop("storage_key")
    return row


def ready_path(row, settings):
    if row["upload_status"] != "ready" or row["scan_status"] != "clean":
        raise DomainError(409, "FILE_NOT_CLEARED", "文件尚未完成安全检查")
    path = storage_path(settings.storage_root, row["storage_key"])
    if not path.is_file() or path.stat().st_size != row["size_bytes"]:
        raise DomainError(503, "STORAGE_UNAVAILABLE", "原文件暂时不可用")
    return path


@router.get("/api/v1/mobile/files/{file_id}/download", summary="重新鉴权后下载原文件")
@router.get("/api/v1/admin/files/{file_id}/download", summary="管理端重新鉴权后下载原文件")
def download(file_id: UUID, request: Request, actor: ActorDep, conn: TxDep):
    row = readable_file(conn, actor, file_id, request.app.state.settings)
    path = ready_path(row, request.app.state.settings)
    return FileResponse(path, filename=row["original_name"], media_type="application/octet-stream",
                        headers={"X-Content-Type-Options": "nosniff", "Cache-Control": "no-store"})


@router.get("/api/v1/mobile/files/{file_id}/preview", summary="鉴权图片/音视频/文本/PDF 及 Office 文档预览")
@router.get("/api/v1/admin/files/{file_id}/preview", summary="管理端安全文件预览")
def preview(file_id: UUID, request: Request, actor: ActorDep, conn: TxDep):
    row = readable_file(conn, actor, file_id, request.app.state.settings)
    path = ready_path(row, request.app.state.settings)
    with path.open("rb") as source:
        head = source.read(64)
    media = None
    if head.startswith(b"\x89PNG\r\n\x1a\n"):
        media = "image/png"
    elif head.startswith(b"\xff\xd8\xff"):
        media = "image/jpeg"
    elif head.startswith(b"RIFF") and head[8:12] == b"WEBP":
        media = "image/webp"
    elif head.startswith((b"GIF87a", b"GIF89a")):
        media = "image/gif"
    elif head.startswith(b"%PDF-"):
        media = "application/pdf"
    elif head[4:8] == b"ftyp":
        media = "audio/mp4" if Path(row["original_name"]).suffix.lower() in {".m4a", ".aac"} else "video/mp4"
    elif head.startswith(b"RIFF") and head[8:12] == b"WAVE":
        media = "audio/wav"
    elif head.startswith(b"ID3") or (len(head) > 1 and head[0] == 0xff and head[1] & 0xe0 == 0xe0):
        media = "audio/mpeg"
    elif head.startswith(b"fLaC"):
        media = "audio/flac"
    elif head.startswith(b"OggS"):
        media = "audio/ogg"
    elif head.startswith(b"\x1aE\xdf\xa3"):
        media = "video/webm"
    if media:
        return FileResponse(path, media_type=media, headers={"Cache-Control": "no-store", "X-Content-Type-Options": "nosniff", "Content-Security-Policy": "default-src 'none'; sandbox"})
    if Path(row["original_name"]).suffix.lower() in OFFICE_EXTENSIONS:
        pdf = office_pdf(path, row["original_name"], request.app.state.settings)
        # 转换完成后重新核对文件权限及安全状态，再返回派生内容。
        fresh = readable_file(conn, actor, file_id, request.app.state.settings)
        ready_path(fresh, request.app.state.settings)
        return FileResponse(pdf, media_type="application/pdf", headers={"Cache-Control": "no-store",
            "X-Content-Type-Options": "nosniff", "Content-Security-Policy": "default-src 'none'; sandbox"})
    if row["kind"] == "text":
        with path.open("rb") as source:
            raw = source.read(65537)
        try:
            decoder = codecs.getincrementaldecoder("utf-8-sig")("strict")
            text = decoder.decode(raw[:65536], final=len(raw) <= 65536)
        except UnicodeDecodeError:
            return {"state": "unsupported", "error_code": "TEXT_ENCODING_UNSUPPORTED"}
        return {"state": "ready", "format": "text", "text": text, "truncated": len(raw) > 65536}
    return {"state": "unsupported", "error_code": "PREVIEW_CONVERTER_NOT_CONFIGURED", "download_available": True}
