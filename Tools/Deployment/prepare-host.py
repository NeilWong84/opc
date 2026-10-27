"""Create cloud-test private configuration once; never overwrite credentials."""
import argparse
import json
import os
from pathlib import Path
import secrets
from urllib.parse import urlsplit

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--origin', required=True)
parser.add_argument('--tag', required=True)
args = parser.parse_args()
url = urlsplit(args.origin)
if url.scheme != 'https' or not url.hostname or url.path not in ('', '/') or url.username or url.query or url.fragment:
    raise SystemExit('Explicit HTTPS origin required')
root = Path('/opt/opc')
shared = root / 'shared'
shared.mkdir(parents=True, exist_ok=True, mode=0o700)
secret_dir = shared / 'secrets'
secret_dir.mkdir(exist_ok=True, mode=0o700)
for name in ('files', 'previews'):
    path = shared / name
    path.mkdir(exist_ok=True, mode=0o700)
    os.chown(path, 10001, 10001)
for name in ('acme', 'letsencrypt'):
    (shared / name).mkdir(exist_ok=True)
for name in ('pg-admin', 'pg-app'):
    path = secret_dir / name
    if not path.exists():
        with path.open('x') as output:
            output.write(secrets.token_urlsafe(48))
        path.chmod(0o400)
        os.chown(path, 10001, 10001)
path = secret_dir / 'admin-login.json'
if not path.exists():
    with path.open('x') as output:
        json.dump({'email': 'admin@opc.example.com', 'display_name': 'OPC 测试管理员', 'password': secrets.token_urlsafe(24)}, output, ensure_ascii=False)
    path.chmod(0o400)
    os.chown(path, 10001, 10001)
env = shared / 'site.env'
content = f'PUBLIC_ORIGIN={args.origin.rstrip("/")}\nIMAGE_TAG={args.tag}\nDATA_ROOT={shared}\n'
if env.exists() and env.read_text() != content:
    raise SystemExit('Existing site configuration differs; refusing to overwrite')
if not env.exists():
    with env.open('x') as output:
        output.write(content)
    env.chmod(0o600)
print('Private cloud configuration prepared; no credentials printed.')
