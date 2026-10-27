"""Check migrated data through public HTTPS; preserve passwords and save admin via DPAPI."""
import ctypes
from ctypes import wintypes
from datetime import datetime, timezone
from hashlib import sha256
import json
from pathlib import Path

import httpx

ROOT = Path(__file__).resolve().parents[2]
LOCAL = ROOT / '.local/deployment'
source = json.loads((ROOT / 'BackendService/.local/demo-credentials.json').read_text(encoding='utf-8-sig'))['accounts']
manifest = json.loads((LOCAL / 'migration-20261026/manifest.json').read_text())
expected_files = {f['id']: f for f in manifest['files']}
report = {'time': datetime.now(timezone.utc).isoformat(), 'checks': []}
sessions = []


def check(name, condition):
    if not condition:
        raise SystemExit('Verification failed: ' + name)
    report['checks'].append(name)
    print('PASS ' + name, flush=True)


with httpx.Client(base_url='https://43.165.191.156', timeout=90, trust_env=False) as client:
    def get(path, token=None):
        return client.get(path, headers={'Authorization': 'Bearer ' + token} if token else {})

    try:
        check('public trusted HTTPS ready with eight migrations', get('/health/ready').json() == {'status': 'ready', 'migrations': 8})
        check('public admin page', get('/').status_code == 200)
        check('unauthenticated business access blocked', get('/api/v1/admin/requests').status_code == 401)
        tokens = {}
        for role in ('admin', 'customer', 'provider'):
            audience = 'admin' if role == 'admin' else 'mobile'
            credentials = source[role]
            response = client.post(f'/api/v1/{audience}/auth/login', json={k: credentials[k] for k in ('email', 'password')})
            check('existing ' + role + ' password retained', response.status_code == 200)
            token = response.json()['access_token']
            tokens[role] = token
            sessions.append((audience, token))
            response = get(f'/api/v1/{audience}/auth/me', token)
            check('existing ' + role + ' identity retained', response.status_code == 200 and response.json()['id'] == credentials['id'])
        admin = tokens['admin']
        check('mobile token denied admin API', get('/api/v1/admin/accounts', tokens['customer']).status_code in {401, 403})
        check('admin token denied mobile API', get('/api/v1/mobile/auth/me', admin).status_code in {401, 403})
        response = get('/api/v1/admin/accounts?limit=100', admin)
        check('all 18 migrated accounts visible', response.status_code == 200 and len(response.json()['items']) == manifest['tables']['accounts']['rows'])
        response = get('/api/v1/admin/requests?limit=100', admin)
        check('all 21 migrated requests visible', response.status_code == 200 and len(response.json()['items']) == manifest['tables']['requests']['rows'])
        response = get('/api/v1/admin/files?limit=100', admin)
        check('all 42 migrated files visible', response.status_code == 200 and {f['id'] for f in response.json()['items']} == set(expected_files))
        files = response.json()['items']
        for item in files:
            response = get(f'/api/v1/admin/files/{item["id"]}/download', admin)
            expected = expected_files[item['id']]
            check_data = response.status_code == 200 and len(response.content) == expected['bytes'] and sha256(response.content).hexdigest() == expected['sha256']
            if not check_data:
                raise SystemExit('Migrated file HTTP download mismatch; no private names printed')
        check('42 authenticated public downloads match exact source SHA256', True)
        for suffix in ('.docx', '.xlsx', '.pptx', '.pdf', '.png'):
            selected = next((f for f in files if f['original_name'].lower().endswith(suffix)), None)
            if selected:
                response = get(f'/api/v1/admin/files/{selected["id"]}/preview', admin)
                check('real migrated ' + suffix + ' preview', response.status_code == 200 and (response.content.startswith(b'%PDF-') if suffix != '.png' else response.content.startswith(b'\x89PNG')))
        for role in ('customer', 'provider'):
            check(role + ' migrated project API', get('/api/v1/mobile/engagements?perspective=' + role, tokens[role]).status_code == 200)
            check(role + ' migrated communication API', get('/api/v1/mobile/threads', tokens[role]).status_code == 200)
    finally:
        for audience, token in sessions:
            client.post(f'/api/v1/{audience}/auth/logout', headers={'Authorization': 'Bearer ' + token})
        (LOCAL / 'migration-20261026/public-verification.json').write_text(json.dumps(report, indent=2), encoding='utf-8')

# Store the verified original administrator login without creating any plaintext copy.
target = LOCAL / 'admin-credentials.json'
previous = LOCAL / 'admin-credentials.pre-migration.json'
if previous.exists():
    raise SystemExit('Encrypted pre-migration admin backup already exists; refusing overwrite')
class Blob(ctypes.Structure):
    _fields_ = [('size', wintypes.DWORD), ('data', ctypes.POINTER(ctypes.c_byte))]

payload = json.dumps(source['admin']).encode()
buffer = (ctypes.c_byte * len(payload)).from_buffer_copy(payload)
plain, encrypted = Blob(len(payload), buffer), Blob()
if not ctypes.windll.crypt32.CryptProtectData(ctypes.byref(plain), None, None, None, None, 5, ctypes.byref(encrypted)):
    raise ctypes.WinError()
try:
    value = ctypes.string_at(encrypted.data, encrypted.size).hex()
finally:
    ctypes.windll.kernel32.LocalFree(encrypted.data)
target.rename(previous)
target.write_text(json.dumps({'format': 'Windows-DPAPI-local-machine-UTF8', 'encryption_scope': 'LocalMachine', 'payload_dpapi': value}), encoding='utf-8')
print('Verified original administrator login saved with machine DPAPI; prior encrypted login retained.')
