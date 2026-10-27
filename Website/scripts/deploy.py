"""Deploy the approved public website and administrator domain to the Tokyo host.

Uses the existing Windows-DPAPI SSH helper. Never uploads local credentials or
business files. Retains the previous source release and environment for rollback.
"""
from __future__ import annotations

import argparse
from hashlib import sha256
from pathlib import Path
import select
import sys
import tarfile
import time

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'Tools/Deployment'))
from ssh import connect


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--tag', required=True)
    parser.add_argument('--phase', choices=('stage', 'publish', 'all'), default='all')
    args = parser.parse_args()
    tag = args.tag
    if not tag or any(c not in 'abcdefghijklmnopqrstuvwxyz0123456789-.' for c in tag):
        raise ValueError('Invalid deployment tag')
    stage = ROOT / 'Website/test_artifacts'
    stage.mkdir(exist_ok=True)
    archive = stage / f'opc-website-{tag}.tar.gz'
    files = [ROOT / x for x in ('Website/Dockerfile', 'Website/nginx.conf', 'Website/.dockerignore', 'FrontendAdmin/vite.config.ts', 'FrontendAdmin/Dockerfile', 'Deploy/compose.yaml', 'Deploy/nginx/default.conf', 'Deploy/nginx/api_locations')]
    files.extend(p for p in (ROOT / 'Website/dist').rglob('*') if p.is_file())
    if args.phase == 'publish':
        if not archive.exists():
            raise RuntimeError('Publish must reuse the exact local archive from staging')
    else:
        with tarfile.open(archive, 'w:gz') as bundle:
            for file in files:
                bundle.add(file, arcname=file.relative_to(ROOT).as_posix(), recursive=False)
    digest = sha256(archive.read_bytes()).hexdigest()
    remote_archive = f'/tmp/opc-website-{tag}.tar.gz'
    script = (ROOT / 'Website/scripts/publish.sh').read_text(encoding='utf-8').replace('__RELEASE_TAG__', tag).replace('__ARCHIVE_SHA256__', digest).replace('__DEPLOY_PHASE__', args.phase)
    client, secret = connect()
    try:
        with client.open_sftp() as sftp:
            try:
                sftp.stat(remote_archive)
            except FileNotFoundError:
                with sftp.open(remote_archive, 'wx') as remote, archive.open('rb') as local:
                    sftp.chmod(remote_archive, 0o600)
                    while chunk := local.read(1024*1024): remote.write(chunk)
            else:
                if args.phase != 'publish':
                    raise RuntimeError('Deployment archive already exists: inspect prior attempt before using a fresh tag')
        print('Uploaded explicit public package; sha256=' + digest, flush=True)
        stdin, stdout, _ = client.exec_command('bash -se', timeout=30)
        stdin.write(script)
        stdin.channel.shutdown_write()
        channel = stdout.channel
        deadline = time.monotonic() + 900
        while True:
            for ready, read in ((channel.recv_ready, channel.recv), (channel.recv_stderr_ready, channel.recv_stderr)):
                while ready():
                    print(read(65536).decode('utf-8', errors='replace').replace(secret, '[REDACTED]'), end='', flush=True)
            if channel.exit_status_ready() and not channel.recv_ready() and not channel.recv_stderr_ready():
                code = channel.recv_exit_status()
                if code: raise SystemExit(code)
                break
            if time.monotonic() > deadline: raise TimeoutError('Inspect remote state before any retry')
            select.select([channel], [], [], 0.2)
    finally:
        client.close()


if __name__ == '__main__':
    main()
