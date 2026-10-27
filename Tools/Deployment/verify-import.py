"""Verify a restored, isolated OPC database and its private file bytes before cutover."""
from hashlib import sha256
import json
from pathlib import Path

import psycopg
from psycopg import sql

DATABASE = 'opc_migrated_20261026'
root = Path('/migration')
manifest = json.loads((root / 'manifest.json').read_text())
password = Path('/run/secrets/pg-admin').read_text().strip()
if sha256((root / 'opc_integration.dump').read_bytes()).hexdigest() != manifest['dump_sha256']:
    raise SystemExit('Dump checksum mismatch')
with psycopg.connect(host='postgres', dbname=DATABASE, user='postgres', password=password) as conn:
    conn.execute("SET LOCAL timezone='UTC'")
    actual = {row[0] for row in conn.execute("SELECT tablename FROM pg_tables WHERE schemaname='opc'")}
    if actual != set(manifest['tables']):
        raise SystemExit('Restored table set mismatch')
    for table, expected in manifest['tables'].items():
        digest, count = sha256(), 0
        for (row,) in conn.execute(sql.SQL('SELECT row_to_json(t)::text FROM opc.{} t ORDER BY id').format(sql.Identifier(table))):
            payload = row.encode()
            digest.update(len(payload).to_bytes(8, 'big') + payload)
            count += 1
        if {'rows': count, 'sha256': digest.hexdigest()} != expected:
            raise SystemExit('Restored row checksum mismatch: ' + table)
    rows = conn.execute('SELECT id,storage_key,size_bytes,sha256 FROM opc.files ORDER BY id').fetchall()
    if len(rows) != len(manifest['files']):
        raise SystemExit('File count mismatch')
    for row, expected in zip(rows, manifest['files'], strict=True):
        identity, key, size, digest = row
        path = root / 'files' / key
        if {'id': str(identity), 'key': key, 'bytes': size, 'sha256': digest} != expected:
            raise SystemExit('Restored file metadata mismatch')
        if path.stat().st_size != size or sha256(path.read_bytes()).hexdigest() != digest:
            raise SystemExit('Restored private file bytes mismatch')
    # Source tokens must never become valid cloud sessions. Retain the historical rows.
    revoked = conn.execute('UPDATE opc.auth_sessions SET revoked_at=now() WHERE revoked_at IS NULL RETURNING id').fetchall()
print(json.dumps({'database': DATABASE, 'tables_verified': len(actual), 'table_checksums_match': True,
                  'files_verified': len(rows), 'file_bytes': sum(f['bytes'] for f in manifest['files']),
                  'source_sessions_revoked': len(revoked), 'snapshot_at': manifest['snapshot_at']}))
