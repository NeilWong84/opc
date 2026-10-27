"""Apply only migration 008 to the marked local integration database, without restarting services."""
from __future__ import annotations

import hashlib
import importlib.util
import json
from pathlib import Path


def main():
    path = Path(__file__).with_name("provision-local-integration.py")
    spec = importlib.util.spec_from_file_location("opc_local_integration", path)
    local = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(local)
    state = json.loads((local.ROOT / "instance.json").read_text(encoding="utf-8"))
    if state.get("marker") != local.MARKER or state.get("port") != 55440:
        raise RuntimeError("Refusing an unexpected local instance")
    migrations = local.BACKEND.parent / "DB" / "migrations"
    target = migrations / "008_request_classifications.sql"
    digest = hashlib.sha256(target.read_bytes()).hexdigest()
    with local.connect(state) as conn, conn.transaction():
        marker = conn.execute("SELECT shobj_description(oid,'pg_database') FROM pg_database WHERE datname=current_database()").fetchone()[0]
        if marker != local.MARKER:
            raise RuntimeError("Refusing an unmarked database")
        conn.execute("SELECT pg_advisory_xact_lock(184920,11)")
        applied = dict(conn.execute("SELECT version,checksum FROM opc.schema_migrations").fetchall())
        for version, checksum in applied.items():
            source = migrations / f"{version}.sql"
            if not source.is_file() or hashlib.sha256(source.read_bytes()).hexdigest() != checksum:
                raise RuntimeError("Applied migration checksum mismatch")
        if not all(any(v.startswith(f"{i:03d}_") for v in applied) for i in range(1, 7)):
            raise RuntimeError("The six baseline migrations are required")
        before = conn.execute("SELECT (SELECT count(*) FROM opc.requests),(SELECT count(*) FROM opc.accounts)").fetchone()
        if target.stem not in applied:
            conn.execute(target.read_text(encoding="utf-8"))
            conn.execute("INSERT INTO opc.schema_migrations(version,checksum) VALUES (%s,%s)", (target.stem, digest))
        conn.execute("REVOKE ALL ON opc.development_platforms,opc.development_types FROM opc_app")
        conn.execute("GRANT SELECT ON opc.development_platforms,opc.development_types TO opc_app")
        after = conn.execute("SELECT (SELECT count(*) FROM opc.requests),(SELECT count(*) FROM opc.accounts)").fetchone()
        if before != after:
            raise RuntimeError("Unexpected change in business counts")
        sizes = conn.execute("SELECT (SELECT count(*) FROM opc.development_platforms),(SELECT count(*) FROM opc.development_types)").fetchone()
    print(f"Classification migration ready: {sizes[0]} platforms / {sizes[1]} development types; business counts unchanged {after}.")


if __name__ == "__main__":
    main()
