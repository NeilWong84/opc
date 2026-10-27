from uuid import uuid4
from psycopg.types.json import Jsonb
from .errors import DomainError


def check_version(row, expected):
    if row is None:
        raise DomainError(404, "NOT_FOUND", "记录不存在或无权访问")
    if row["row_version"] != expected:
        raise DomainError(409, "VERSION_CONFLICT", "记录已变化，请刷新后重新操作")


def owned_files(conn, actor_id, file_ids, *, allow_pending=False):
    if len(set(file_ids)) != len(file_ids):
        raise DomainError(422, "DUPLICATE_FILE", "附件不能重复")
    if not file_ids:
        return []
    statuses = ["clean", "pending"] if allow_pending else ["clean"]
    rows = conn.execute("""SELECT id FROM opc.files WHERE id=ANY(%s) AND owner_id=%s
        AND upload_status='ready' AND scan_status=ANY(%s) FOR SHARE""", (list(file_ids), actor_id, statuses)).fetchall()
    if len(rows) != len(file_ids):
        raise DomainError(422, "FILE_UNAVAILABLE", "附件不属于当前账号或尚未完成上传及检查")
    return rows


def emit(conn, account_id, event_type, title, body, payload=None):
    event_id = uuid4()
    data = {"title": title, "body": body, **(payload or {})}
    # JSONB stores serializable business data only; do not put secrets/file bytes in events.
    from fastapi.encoders import jsonable_encoder
    data = jsonable_encoder(data)
    conn.execute("""INSERT INTO opc.notifications(recipient_id,event_key,template_key,parameters)
        VALUES (%s,%s,%s,%s)""", (account_id, str(event_id), event_type, Jsonb(data)))
    conn.execute("""INSERT INTO opc.outbox_events(id,topic,aggregate_id,payload)
        VALUES (%s,%s,%s,%s)""", (event_id, event_type, account_id, Jsonb(data)))
