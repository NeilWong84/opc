import hashlib
import json
from fastapi.encoders import jsonable_encoder
from psycopg.types.json import Jsonb
from .errors import DomainError


def payload_hash(payload):
    return hashlib.sha256(json.dumps(jsonable_encoder(payload), ensure_ascii=False,
                                    sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def idempotent(conn, actor, operation, key, payload, action):
    if not key or not 1 <= len(key) <= 200 or not key.strip():
        raise DomainError(422, "IDEMPOTENCY_KEY_REQUIRED", "提供 1–200 字符 Idempotency-Key 请求头")
    digest = payload_hash(payload)
    # The advisory lock serializes a key even when no row exists yet.
    lock = f"{actor.id}:{actor.audience}:{operation}:{key}"
    conn.execute("SELECT pg_advisory_xact_lock(hashtextextended(%s,0))", (lock,))
    operation = f"{actor.audience}:{operation}"
    previous = conn.execute("""SELECT request_hash,result FROM opc.idempotency_keys
        WHERE actor_id=%s AND operation=%s AND key=%s""", (actor.id, operation, key)).fetchone()
    if previous:
        if previous["request_hash"] != digest:
            raise DomainError(409, "IDEMPOTENCY_CONFLICT", "相同幂等键不能提交不同内容")
        return previous["result"]
    result = jsonable_encoder(action())
    conn.execute("""INSERT INTO opc.idempotency_keys(actor_id,operation,key,request_hash,result,expires_at)
        VALUES (%s,%s,%s,%s,%s,now()+interval '7 days')""", (actor.id, operation, key, digest, Jsonb(result)))
    return result
