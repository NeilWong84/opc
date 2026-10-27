"""Export one consistent OPC PostgreSQL snapshot and the exact referenced file bytes."""
from datetime import datetime, timezone
from hashlib import sha256
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tarfile

ROOT = Path(__file__).resolve().parents[2]
BACKEND = ROOT / 'BackendService'
sys.path.insert(0, str(BACKEND))
import psycopg
from psycopg import sql
from psycopg.conninfo import conninfo_to_dict
from app.config import Settings

os.chdir(BACKEND)
settings = Settings()
target = ROOT / '.local' / 'deployment' / 'migration-20261026'
target.mkdir(mode=0o700)
dump = target / 'opc_integration.dump'
manifest = {'snapshot_at': datetime.now(timezone.utc).isoformat(), 'tables': {}, 'files': []}
with psycopg.connect(settings.database_url) as conn:
    conn.execute('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY')
    conn.execute("SET LOCAL timezone='UTC'")
    identity = conn.execute("SELECT current_database(), shobj_description(oid,'pg_database') FROM pg_database WHERE datname=current_database()").fetchone()
    if identity != ('opc_integration', 'opc.local-integration.v1'):
        raise SystemExit('Refusing an unexpected local database')
    snapshot = conn.execute('SELECT pg_export_snapshot()').fetchone()[0]
    for (table,) in conn.execute("SELECT tablename FROM pg_tables WHERE schemaname='opc' ORDER BY tablename"):
        digest, count = sha256(), 0
        for (row,) in conn.execute(sql.SQL('SELECT row_to_json(t)::text FROM opc.{} t ORDER BY id').format(sql.Identifier(table))):
            payload = row.encode()
            digest.update(len(payload).to_bytes(8, 'big') + payload)
            count += 1
        manifest['tables'][table] = {'rows': count, 'sha256': digest.hexdigest()}
    storage = settings.storage_root.resolve()
    for file_id, key, size, digest, status in conn.execute('SELECT id,storage_key,size_bytes,sha256,upload_status FROM opc.files ORDER BY id'):
        if not re.fullmatch('[0-9a-f]{32}', key):
            raise SystemExit('Unexpected private storage key')
        path = storage / key
        if status != 'ready' or not path.is_file() or path.stat().st_size != size or sha256(path.read_bytes()).hexdigest() != digest:
            raise SystemExit('A database file does not match its private source bytes')
        manifest['files'].append({'id': str(file_id), 'key': key, 'bytes': size, 'sha256': digest})
    config = conninfo_to_dict(settings.database_url)
    env = os.environ.copy()
    env['PGPASSWORD'] = config['password']
    result = subprocess.run([
        r'C:\Program Files\PostgreSQL\18\bin\pg_dump.exe',
        '--host', config.get('host', '127.0.0.1'), '--port', config.get('port', '55440'),
        '--username', config['user'], '--dbname', config['dbname'], '--format=custom',
        '--no-owner', '--no-privileges', '--snapshot', snapshot, '--file', str(dump),
    ], env=env, capture_output=True, timeout=120)
    if result.returncode:
        raise SystemExit('pg_dump failed; no connection string or credentials printed')
    manifest['dump_sha256'] = sha256(dump.read_bytes()).hexdigest()
    (target / 'manifest.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
    archive = target / 'opc-data.tar.gz'
    with tarfile.open(archive, 'w:gz') as output:
        output.add(dump, arcname='opc_integration.dump', recursive=False)
        output.add(target / 'manifest.json', arcname='manifest.json', recursive=False)
        for item in manifest['files']:
            path = storage / item['key']
            if sha256(path.read_bytes()).hexdigest() != item['sha256']:
                raise SystemExit('Source file changed during export')
            output.add(path, arcname='files/' + item['key'], recursive=False)
print(json.dumps({'tables': len(manifest['tables']), 'accounts': manifest['tables']['accounts']['rows'], 'requests': manifest['tables']['requests']['rows'], 'files': len(manifest['files']), 'file_bytes': sum(f['bytes'] for f in manifest['files']), 'archive_sha256': sha256(archive.read_bytes()).hexdigest()}))
