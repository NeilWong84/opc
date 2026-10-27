"""Read-only verification of a completed Android run before/after PG restart.

Run only after Flutter has produced integration_response_data.json. This script
never starts/stops PostgreSQL, writes business data, or prints a database DSN.
--output saves a non-secret deterministic snapshot; --compare checks an earlier
snapshot before writing the new one. Every database transaction is read-only.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import sys
from uuid import UUID

import psycopg
from psycopg.conninfo import conninfo_to_dict
from psycopg.rows import dict_row

BACKEND = Path(__file__).resolve().parents[1]
PROJECT = BACKEND.parent
STATE_PATH = BACKEND / ".local" / "integration" / "instance.json"
MARKER = "opc.local-integration.v1"
sys.path.insert(0, str(BACKEND))
from app.config import Settings  # noqa: E402
from app.files import storage_path  # noqa: E402


def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest_json(value):
    return hashlib.sha256(json.dumps(value, ensure_ascii=False, sort_keys=True, default=str).encode()).hexdigest()


def read_report(path):
    report = json.loads(path.read_text(encoding="utf-8"))
    require(isinstance(report, dict), "Android result must be a JSON object")
    require(report.get("status") == "completed", "Android run is not completed; do not capture a persistence snapshot yet")
    require(bool(re.fullmatch(r"[a-zA-Z0-9_-]{1,100}", str(report.get("run_id", "")))), "Invalid run identifier")
    for key in ("request_id", "engagement_id", "delivery_id", "source_file_id", "private_file_id", "reference_file_id"):
        require(isinstance(report.get(key), str), f"Missing Android result field: {key}")
        report[key] = str(UUID(report[key]))
    return report


def verify(report, settings):
    state = json.loads(STATE_PATH.read_text(encoding="utf-8"))
    require(state.get("marker") == MARKER and state.get("port") == 55440,
            "Local instance marker/port does not match the dedicated integration instance")
    options = conninfo_to_dict(settings.database_url)
    require(options.get("host") == "127.0.0.1" and options.get("port") == "55440"
            and options.get("dbname") == "opc_integration" and options.get("user") == "opc_app"
            and options.get("hostaddr", "127.0.0.1") == "127.0.0.1",
            "Only restricted opc_app at 127.0.0.1:55440/opc_integration is supported")
    with psycopg.connect(settings.database_url, row_factory=dict_row, connect_timeout=4) as conn:
        conn.read_only = True
        conn.isolation_level = psycopg.IsolationLevel.REPEATABLE_READ
        identity = conn.execute("""SELECT current_database() AS database,current_user AS role,
            shobj_description(d.oid,'pg_database') AS marker,r.rolsuper,r.rolcreatedb,r.rolcreaterole,
            r.rolreplication,r.rolbypassrls,current_setting('fsync') AS fsync,
            current_setting('synchronous_commit') AS synchronous_commit,
            current_setting('transaction_read_only') AS transaction_read_only,
            current_setting('server_version_num') AS server_version_num
            FROM pg_database d JOIN pg_roles r ON r.rolname=current_user WHERE d.datname=current_database()""").fetchone()
        require(identity["database"] == "opc_integration" and identity["marker"] == MARKER and identity["role"] == "opc_app",
                "Connected database identity does not match the integration instance")
        require(not any(identity[key] for key in ("rolsuper", "rolcreatedb", "rolcreaterole", "rolreplication", "rolbypassrls")),
                "Persistence verification requires the restricted application role")
        require(identity["fsync"] == "on" and identity["synchronous_commit"] == "on", "PostgreSQL durability settings must both be on")
        require(identity["transaction_read_only"] == "on", "Verification transaction must be read-only")
        require(int(identity["server_version_num"]) // 10000 == 18, "Expected PostgreSQL 18")
        migrations = conn.execute("SELECT version,checksum FROM opc.schema_migrations ORDER BY version").fetchall()
        expected = {p.stem: hashlib.sha256(p.read_bytes()).hexdigest()
                    for p in sorted((PROJECT / "DB" / "migrations").glob("*.sql"))}
        require(len(migrations) == 6 and len(expected) == 6
                and {row["version"]: row["checksum"] for row in migrations} == expected,
                "The six applied migration checksums must match the repository exactly")

        request = conn.execute("""SELECT id,customer_id,intake_status,current_request_version,current_scope_version,row_version
            FROM opc.requests WHERE id=%s""", (report["request_id"],)).fetchone()
        require(request is not None and request["intake_status"] == "closed", "The Android request is not persisted as closed")
        engagement = conn.execute("""SELECT id,request_id,status,row_version,closed_at FROM opc.engagements WHERE id=%s""",
                                  (report["engagement_id"],)).fetchone()
        require(engagement is not None and str(engagement["request_id"]) == report["request_id"]
                and engagement["status"] == "completed" and engagement["closed_at"] is not None,
                "The matching Android engagement is not completed")
        deliveries = conn.execute("""SELECT id,version,agreement_version,source_file_id,submitted_by,submitted_at,
            note,guide_text,test_report_text FROM opc.deliveries WHERE engagement_id=%s ORDER BY version""",
                                 (report["engagement_id"],)).fetchall()
        require([row["version"] for row in deliveries] == [1, 2], "Expected the persisted v1 revision and v2 delivery")
        latest = deliveries[-1]
        require(str(latest["id"]) == report["delivery_id"] and str(latest["source_file_id"]) == report["source_file_id"],
                "The Android result does not reference the latest v2 source delivery")
        acceptances = conn.execute("""SELECT a.id,a.delivery_id,d.version,a.customer_id,a.decision,a.feedback,a.decided_at
            FROM opc.acceptance_decisions a JOIN opc.deliveries d ON d.id=a.delivery_id
            WHERE d.engagement_id=%s ORDER BY d.version""", (report["engagement_id"],)).fetchall()
        require([(row["version"], row["decision"]) for row in acceptances] == [(1, "revision_requested"), (2, "accepted")]
                and all(row["customer_id"] == request["customer_id"] for row in acceptances),
                "Expected the owning customer's v1 revision request and explicit v2 acceptance")
        publication = conn.execute("""SELECT p.id,p.delivery_id,p.published_at,q.decision FROM opc.delivery_publications p
            JOIN opc.delivery_reviews q ON q.id=p.review_id AND q.delivery_id=p.delivery_id
            WHERE p.delivery_id=%s AND p.withdrawn_at IS NULL""", (report["delivery_id"],)).fetchone()
        require(publication is not None and publication["decision"] == "approved", "Latest delivery publication/quality evidence is missing")
        require(conn.execute("""SELECT 1 FROM opc.request_files WHERE request_id=%s AND request_version=%s AND file_id=%s""",
                             (report["request_id"], request["current_request_version"], report["private_file_id"])).fetchone(),
                "Private original file is not linked to the current request version")
        # Subsequent customer clarification creates a new original version and
        # withdraws the hall publication. The existing cooperation still binds
        # its immutable approved agreement scope, including historical references.
        agreement_references = conn.execute("""SELECT g.version AS agreement_version,g.scope_version,
            p.id AS publication_id,p.published_at,p.withdrawn_at,f.file_id
            FROM opc.agreement_versions g JOIN opc.publications p ON p.request_id=g.request_id AND p.scope_version=g.scope_version
            JOIN opc.publication_files f ON f.publication_id=p.id
            JOIN opc.review_decisions c ON c.id=p.compliance_review_id AND c.decision='approved' AND c.kind='compliance'
            JOIN opc.review_decisions t ON t.id=p.technical_review_id AND t.decision='approved' AND t.kind='technical'
            WHERE g.engagement_id=%s AND g.version=%s AND g.request_id=%s AND f.file_id=%s
            ORDER BY p.published_at,p.id""", (report["engagement_id"], latest["agreement_version"],
                                               report["request_id"], report["reference_file_id"])).fetchall()
        require(agreement_references, "Explicit reviewed reference is missing from the delivery's agreed scope history")

        files = []
        storage_root = settings.storage_root if settings.storage_root.is_absolute() else BACKEND / settings.storage_root
        for purpose in ("private", "reference", "source"):
            row = conn.execute("""SELECT id,size_bytes,sha256,storage_key,upload_status,scan_status FROM opc.files WHERE id=%s""",
                               (report[f"{purpose}_file_id"],)).fetchone()
            require(row is not None and row["upload_status"] == "ready" and row["scan_status"] == "clean",
                    f"Persisted {purpose} file is missing or not cleared")
            path = storage_path(storage_root, row["storage_key"])
            require(path.is_file() and path.stat().st_size == row["size_bytes"], f"Actual {purpose} bytes are missing or size differs")
            with path.open("rb") as stream:
                actual_hash = hashlib.file_digest(stream, "sha256").hexdigest()
            require(actual_hash == row["sha256"], f"Actual {purpose} SHA-256 differs from PostgreSQL metadata")
            files.append({"purpose": purpose, "id": str(row["id"]), "size_bytes": row["size_bytes"],
                          "sha256": actual_hash, "upload_status": row["upload_status"], "scan_status": row["scan_status"]})

        messages = conn.execute("""SELECT m.id,m.thread_id,m.author_id,m.body,m.sent_at,t.kind FROM opc.messages m
            JOIN opc.conversation_threads t ON t.id=m.thread_id WHERE t.request_id=%s ORDER BY m.sent_at,m.id""",
                                (report["request_id"],)).fetchall()
        require(any(m["kind"] == "customer_project" and report["run_id"] in m["body"] for m in messages),
                "Persisted shared project message for this Android run is missing")
        notifications = conn.execute("""SELECT id,recipient_id,template_key,parameters,created_at,read_at FROM opc.notifications
            WHERE recipient_id IN (%s,%s) AND (request_id=%s OR parameters->>'request_id'=%s OR parameters->>'engagement_id'=%s)
            ORDER BY created_at,id""", (request["customer_id"], latest["submitted_by"], report["request_id"],
                                       report["request_id"], report["engagement_id"])).fetchall()
        require(notifications and any(n["recipient_id"] == request["customer_id"] for n in notifications),
                "Persisted customer business notifications are missing")
        require(any(n["read_at"] is not None for n in notifications), "The Android notification read receipt is missing")

        # Hash free text and notification payloads instead of putting customer
        # descriptions, messages, filenames or storage keys in a report.
        for row in deliveries:
            row["content_sha256"] = digest_json({key: row.pop(key) for key in ("note", "guide_text", "test_report_text")})
        for row in acceptances:
            row["feedback_sha256"] = hashlib.sha256(row.pop("feedback").encode()).hexdigest()
        for row in messages:
            row["body_sha256"] = hashlib.sha256(row.pop("body").encode()).hexdigest()
        for row in notifications:
            row["parameters_sha256"] = digest_json(row.pop("parameters"))
        snapshot = {"schema": "opc.mobile-persistence.v1", "run_id": report["run_id"], "verified": True,
                    "database": {"host": "127.0.0.1", "port": 55440, **identity}, "migrations": migrations,
                    "request": request, "engagement": engagement, "deliveries": deliveries,
                    "acceptances": acceptances, "delivery_publication": publication,
                    "agreement_references": agreement_references, "files": files,
                    "messages": messages, "notifications": notifications}
        return json.loads(json.dumps(snapshot, ensure_ascii=False, default=str))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, default=PROJECT / "APPClient" / "build" / "integration_response_data.json")
    parser.add_argument("--output", type=Path, help="Write the verified non-secret JSON snapshot")
    parser.add_argument("--compare", type=Path, help="Require exact equality with a previous verified snapshot")
    args = parser.parse_args()
    if args.output:
        protected = {STATE_PATH.resolve(), (BACKEND / ".env").resolve(), args.input.resolve()}
        if args.compare:
            protected.add(args.compare.resolve())
        require(args.output.resolve() not in protected, "Snapshot output must not overwrite input, comparison or credential files")
    result = verify(read_report(args.input), Settings(_env_file=BACKEND / ".env"))
    if args.compare:
        before = json.loads(args.compare.read_text(encoding="utf-8"))
        require(before == result, "Persistence snapshot differs from the reference; no success snapshot was written")
    serialized = json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(serialized, encoding="utf-8")
    print(serialized, end="")


if __name__ == "__main__":
    try:
        main()
    except psycopg.Error as exc:
        raise SystemExit(f"Persistence verification failed (SQLSTATE {exc.sqlstate or 'connection'}); connection credentials omitted") from None
    except (ValueError, OSError) as exc:
        raise SystemExit(f"Persistence verification failed: {exc}") from None
