"""Build an explicit, secret-free source archive for Docker builds on the target."""
from hashlib import sha256
import argparse
import json
from pathlib import Path
import tarfile

ROOT = Path(__file__).resolve().parents[2]
TARGET = ROOT / '.local' / 'deployment'
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--tag', default='20261026-01')
tag = parser.parse_args().tag
if not tag or any(character not in 'abcdefghijklmnopqrstuvwxyz0123456789-.' for character in tag):
    raise SystemExit('Invalid release tag')
paths = [ROOT / '.dockerignore', ROOT / 'BackendService' / 'Dockerfile',
         ROOT / 'BackendService' / 'requirements.lock.txt', ROOT / 'BackendService' / 'requirements.runtime.txt']
paths.extend(ROOT / 'FrontendAdmin' / name for name in ('Dockerfile', '.dockerignore', 'package.json', 'package-lock.json', 'index.html', 'vite.config.ts', 'tsconfig.json', 'tsconfig.app.json', 'tsconfig.node.json') if (ROOT / 'FrontendAdmin' / name).is_file())
paths.append(ROOT / 'FrontendAdmin' / 'scripts' / 'production-guard.mjs')
if (ROOT / 'Website').is_dir():
    if not (ROOT / 'Website/dist/index.html').is_file():
        raise SystemExit('Build and check Website before packaging the current Compose deployment')
    paths.extend(ROOT / 'Website' / name for name in ('Dockerfile', '.dockerignore', 'nginx.conf'))
    paths.extend(path for path in (ROOT / 'Website/dist').rglob('*') if path.is_file())
for folder in ('BackendService/app', 'DB/migrations', 'Tools/Deployment/container', 'Deploy', 'FrontendAdmin/src', 'FrontendAdmin/public', 'FrontendAdmin/docker'):
    if not (ROOT / folder).exists():
        continue
    for path in (ROOT / folder).rglob('*'):
        relative = path.relative_to(ROOT / folder)
        if any(part in {'node_modules', 'dist', '.git', '.local', '__pycache__', 'test-results', 'playwright-report'} for part in relative.parts):
            continue
        if path.is_file() and not path.name.startswith('.env') and path.suffix not in {'.pyc', '.log', '.pem'}:
            paths.append(path)
paths.extend(ROOT / 'Tools' / 'Deployment' / name for name in ('prepare-host.py', 'renew-certificate.sh', 'backup.sh', 'verify-public.py', 'verify-office.sh', 'verify-restore.sh', 'configure-renewal.sh', 'stage-release.sh'))
paths.extend(ROOT / name for name in ('README.md', 'Docs/deployment/tencent-compose-test.md', 'Docs/testing/tencent-compose-deployment-2026-10-26.md'))
manifest = {path.relative_to(ROOT).as_posix(): sha256(path.read_bytes()).hexdigest() for path in sorted(set(paths))}
archive = TARGET / f'opc-{tag}.tar.gz'
with tarfile.open(archive, 'w:gz') as output:
    for name in manifest:
        output.add(ROOT / name, arcname=name, recursive=False)
(TARGET / f'opc-{tag}.manifest.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
print(f'Package: {archive.name}; files={len(manifest)}; sha256={sha256(archive.read_bytes()).hexdigest()}')
