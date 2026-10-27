"""Verify public pages, APK bytes, TLS and existing API identities without business writes."""
from datetime import datetime, timezone
from hashlib import sha256
from html.parser import HTMLParser
import json
from pathlib import Path
import urllib.error
import urllib.parse
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
SITE = 'https://www.opcapp.art'
ADMIN = 'https://admin.opcapp.art'
IP = 'https://43.165.191.156'
OPENER = urllib.request.build_opener(urllib.request.ProxyHandler({}))
REPORT = {'time': datetime.now(timezone.utc).isoformat(), 'checks': []}


def call(url, method='GET', body=None, token=None, headers=None):
    headers = dict(headers or {})
    if token: headers['Authorization'] = 'Bearer ' + token
    if body is not None:
        body = json.dumps(body).encode()
        headers['Content-Type'] = 'application/json'
    request = urllib.request.Request(url, data=body, headers=headers, method=method)
    try:
        response = OPENER.open(request, timeout=60)
    except urllib.error.HTTPError as error:
        response = error
    with response:
        data = response.read()
        return response.status, response.headers, data, response.url


def check(name, condition):
    if not condition: raise RuntimeError('Verification failed: ' + name)
    REPORT['checks'].append(name)
    print('PASS ' + name, flush=True)


class Links(HTMLParser):
    def __init__(self):
        super().__init__()
        self.assets = []

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if tag in ('script', 'img') and a.get('src'): self.assets.append(a['src'])
        if tag == 'link' and a.get('rel') in ('stylesheet', 'icon'): self.assets.append(a['href'])


def main():
    sessions = []
    try:
        for locale in ('ja', 'zh'):
            for page in ('/', '/download/'):
                url = SITE + '/' + locale + page
                status, headers, data, _ = call(url)
                html = data.decode('utf-8')
                check(locale + page + ' trusted HTTPS HTML', status == 200 and ('lang="ja"' if locale == 'ja' else 'lang="zh-CN"') in html)
                check(locale + page + ' canonical and alternate languages', '<link rel="canonical" href="' + url + '"' in html and 'hreflang="zh-CN"' in html and 'hreflang="ja"' in html)
                check(locale + page + ' fresh content and CSP', 'no-cache' in headers.get('Cache-Control', '') and "default-src 'self'" in headers.get('Content-Security-Policy', ''))
                parser = Links(); parser.feed(html)
                for asset in set(parser.assets):
                    status, _, data, _ = call(urllib.parse.urljoin(url, asset))
                    check(locale + page + ' asset ' + asset.rsplit('/', 1)[-1], status == 200 and bool(data))
        check('formal sitemap reachable', call(SITE + '/sitemap.xml')[0] == 200)
        check('missing public page remains 404', call(SITE + '/not-an-opc-page')[0] == 404)
        check('private directories not published', all(call(SITE + path)[0] == 404 for path in ('/.env', '/.local/demo-credentials.json', '/files/')))
        check('HTTP upgrades to trusted HTTPS', call('http://www.opcapp.art/ja/')[3] == SITE + '/ja/')
        release = json.loads(call(SITE + '/release.json')[2])
        expected = json.loads((ROOT / 'Website/dist/release.json').read_text(encoding='utf-8'))
        check('published release matches staged version', all(release[k] == expected[k] for k in ('version_name', 'version_code', 'bytes', 'sha256', 'file')))
        status, headers, binary, _ = call(SITE + '/' + release['url'])
        check('public APK exact size and SHA-256', status == 200 and len(binary) == release['bytes'] and sha256(binary).hexdigest() == release['sha256'])
        check('APK download MIME and cache', 'application/vnd.android.package-archive' in headers.get('Content-Type', '') and 'attachment' in headers.get('Content-Disposition', '') and 'immutable' in headers.get('Cache-Control', ''))
        artifact = ROOT / 'Website/test_artifacts/downloaded-cloud.apk'
        artifact.write_bytes(binary)
        status, headers, partial, _ = call(SITE + '/' + release['url'], headers={'Range':'bytes=0-1023'})
        check('APK resumable range response', status == 206 and partial == binary[:1024] and headers.get('Content-Range', '').startswith('bytes 0-1023/'))
        status, headers, admin_html, _ = call(ADMIN + '/')
        check('administrator domain serves own application', status == 200 and b'id="app"' in admin_html and 'noindex' in headers.get('X-Robots-Tag', ''))
        parser = Links(); parser.feed(admin_html.decode())
        for asset in parser.assets:
            check('admin static asset ' + asset.rsplit('/',1)[-1], call(urllib.parse.urljoin(ADMIN+'/', asset))[0] == 200)
        check('IP admin path redirects to domain', call(IP + '/admin/')[3] == ADMIN + '/')
        check('existing IP API ready', json.loads(call(IP + '/health/ready')[2]).get('status') == 'ready')
        check('anonymous administration denied', call(ADMIN + '/api/v1/admin/requests')[0] == 401)
        accounts = json.loads((ROOT / 'BackendService/.local/demo-credentials.json').read_text(encoding='utf-8-sig'))['accounts']
        for role, origin, audience in (('admin', ADMIN, 'admin'), ('customer', IP, 'mobile'), ('provider', IP, 'mobile')):
            credentials = accounts[role]
            status, _, data, _ = call(origin + f'/api/v1/{audience}/auth/login', 'POST', {k:credentials[k] for k in ('email','password')})
            check('existing ' + role + ' login', status == 200)
            token = json.loads(data)['access_token']
            sessions.append((origin, audience, token))
            status, _, data, _ = call(origin + f'/api/v1/{audience}/auth/me', token=token)
            check(role + ' identity retained', status == 200 and json.loads(data)['id'] == credentials['id'])
            endpoint = '/api/v1/admin/requests' if role == 'admin' else '/api/v1/mobile/threads'
            check(role + ' real data API', call(origin + endpoint, token=token)[0] == 200)
            other = '/api/v1/mobile/auth/me' if role == 'admin' else '/api/v1/admin/requests'
            check(role + ' audience separation', call(origin + other, token=token)[0] in (401,403))
    finally:
        for origin, audience, token in sessions:
            check(audience + ' verification session revoked', call(origin + f'/api/v1/{audience}/auth/logout', 'POST', token=token)[0] in (200,204))
        target = ROOT / 'Website/test_artifacts/live-verification.json'
        target.write_text(json.dumps(REPORT, ensure_ascii=False, indent=2), encoding='utf-8')
    print('Live checks passed; no requirements, messages, terms or business records changed.')


if __name__ == '__main__':
    main()
