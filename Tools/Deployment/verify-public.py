"""Verify cloud HTTPS and real auth boundaries without printing passwords/tokens."""
from datetime import datetime, timezone
from hashlib import sha256
import json
import os
from pathlib import Path
import secrets
import socket
import urllib.error
import urllib.request
from uuid import uuid4

ORIGIN = 'https://43.165.191.156'
if os.environ.get('OPC_VERIFY_LOOPBACK') == '1':
    original_resolve = socket.getaddrinfo
    def local_resolve(host, port, *args, **kwargs):
        return original_resolve('127.0.0.1' if host == '43.165.191.156' else host, port, *args, **kwargs)
    socket.getaddrinfo = local_resolve
bootstrap = json.loads(Path('/opt/opc/shared/secrets/admin-login.json').read_text())
report = {'time': datetime.now(timezone.utc).isoformat(), 'checks': []}


def call(path, method='GET', body=None, token=None, content_type=None):
    headers = {}
    if token:
        headers['Authorization'] = 'Bearer ' + token
    if isinstance(body, dict):
        body = json.dumps(body).encode()
        content_type = 'application/json'
    if content_type:
        headers['Content-Type'] = content_type
    request = urllib.request.Request(ORIGIN + path, data=body, headers=headers, method=method)
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            data, status, mime = response.read(), response.status, response.headers.get('Content-Type', '')
    except urllib.error.HTTPError as error:
        data, status, mime = error.read(), error.code, error.headers.get('Content-Type', '')
    return status, json.loads(data) if 'application/json' in mime else data


def check(name, condition):
    if not condition:
        raise RuntimeError('Verification failed: ' + name)
    report['checks'].append(name)
    print('PASS ' + name, flush=True)


admin_token = customer_token = None
customer_id = None
try:
    status, page = call('/')
    check('trusted HTTPS admin static page (loopback)' if os.environ.get('OPC_VERIFY_LOOPBACK') else 'trusted HTTPS admin static page', status == 200 and b'id="app"' in page)
    status, ready = call('/health/ready')
    check('PostgreSQL eight migrations ready', status == 200 and ready == {'status': 'ready', 'migrations': 8})
    status, capability = call('/api/v1/capabilities')
    check('Japan business defaults retained', status == 200 and capability['currency'] == 'JPY' and capability['locales'] == ['ja', 'zh'] and capability['hall_audience'] == 'internal')
    check('unauthenticated admin requests denied', call('/api/v1/admin/requests')[0] == 401)
    status, login = call('/api/v1/admin/auth/login', 'POST', {'email': bootstrap['email'], 'password': bootstrap['password']})
    check('administrator login', status == 200 and login['audience'] == 'admin')
    admin_token = login['access_token']
    status, account = call('/api/v1/admin/auth/me', token=admin_token)
    check('administrator identity', status == 200 and 'administrator' in account['roles'])
    check('admin token cannot access mobile audience', call('/api/v1/mobile/auth/me', token=admin_token)[0] in {401, 403})
    customer_email = f'cloud-smoke-{uuid4().hex[:12]}@example.com'
    password = secrets.token_urlsafe(24)
    status, customer = call('/api/v1/mobile/auth/register', 'POST', {'email': customer_email, 'password': password, 'display_name': '云部署验证客户（合成）', 'ui_locale': 'ja'})
    check('customer registration without extra roles', status == 201 and customer['roles'] == ['customer'])
    customer_id = customer['id']
    status, login = call('/api/v1/mobile/auth/login', 'POST', {'email': customer_email, 'password': password})
    check('mobile login', status == 200 and login['audience'] == 'mobile')
    customer_token = login['access_token']
    check('mobile token cannot access admin audience', call('/api/v1/admin/accounts', token=customer_token)[0] in {401, 403})
    status, categories = call('/api/v1/mobile/request-classifications', token=customer_token)
    check('real bilingual classifications', status == 200 and len(categories['platforms']) == 5 and len(categories['development_types']) == 6)
    check('internal hall rejects ordinary customers', call('/api/v1/mobile/hall', token=customer_token)[0] == 403)
    content = b'OPC cloud deployment fixture. No customer information.\n'
    boundary = 'opc-deployment-' + uuid4().hex
    body = (f'--{boundary}\r\nContent-Disposition: form-data; name="file"; filename="deployment-fixture.txt"\r\nContent-Type: text/plain\r\n\r\n'.encode() + content + f'\r\n--{boundary}--\r\n'.encode())
    status, uploaded = call('/api/v1/mobile/files', 'POST', body, customer_token, 'multipart/form-data; boundary=' + boundary)
    check('private upload records exact bytes', status == 201 and uploaded['sha256'] == sha256(content).hexdigest() and uploaded['scan_status'] == 'pending')
    report['fixture_file_id'] = uploaded['id']
    check('pending file download remains blocked', call(f'/api/v1/mobile/files/{uploaded["id"]}/download', token=customer_token)[0] == 409)
    status, requests = call('/api/v1/admin/requests', token=admin_token)
    check('management request API', status == 200 and isinstance(requests['items'], list))
finally:
    if customer_token:
        call('/api/v1/mobile/auth/logout', 'POST', token=customer_token)
    if customer_id and admin_token:
        status, record = call('/api/v1/admin/accounts/' + customer_id + '/status', 'PUT', {'expected_version': customer['row_version'], 'status': 'disabled', 'reason': '云部署验证结束，停用合成测试账号'}, admin_token)
        # Status changes may require a refreshed row version; never claim cleanup if it failed.
        report['test_customer_disabled'] = status == 200
        if status != 200:
            print('Test customer cleanup requires review; no credentials printed.')
    if admin_token:
        call('/api/v1/admin/auth/logout', 'POST', token=admin_token)
    target = Path('/opt/opc/shared/deployment-verification.json')
    target.write_text(json.dumps(report, indent=2), encoding='utf-8')
    target.chmod(0o600)
