"""SSH/SFTP using a local Windows-DPAPI credential file; never print secrets."""
from __future__ import annotations

import argparse
import base64
import ctypes
from ctypes import wintypes
import hashlib
import json
from pathlib import Path
import select
import sys
import time

import paramiko

sys.stdout.reconfigure(encoding='utf-8', errors='replace')
sys.stderr.reconfigure(encoding='utf-8', errors='replace')

ROOT = Path(__file__).resolve().parents[2]
LOCAL = ROOT / '.local' / 'deployment'


def connect():
    path = LOCAL / 'server-credentials.json'
    credential = json.loads(path.read_text(encoding='utf-8-sig'))
    class Blob(ctypes.Structure):
        _fields_ = [('size', wintypes.DWORD), ('data', ctypes.POINTER(ctypes.c_byte))]

    encrypted = bytes.fromhex(credential['password_dpapi'])
    buffer = (ctypes.c_byte * len(encrypted)).from_buffer_copy(encrypted)
    source, target = Blob(len(encrypted), buffer), Blob()
    if not ctypes.windll.crypt32.CryptUnprotectData(
        ctypes.byref(source), None, None, None, None, 1, ctypes.byref(target)
    ):
        raise ctypes.WinError()
    try:
        password = ctypes.string_at(target.data, target.size).decode('utf-16-le')
    finally:
        ctypes.windll.kernel32.LocalFree(target.data)
    client = paramiko.SSHClient()
    known = LOCAL / 'known_hosts'
    if known.exists():
        client.load_host_keys(str(known))

    class FirstConnection(paramiko.MissingHostKeyPolicy):
        def missing_host_key(self, connection, hostname, key):
            fingerprint = base64.b64encode(hashlib.sha256(key.asbytes()).digest()).decode().rstrip('=')
            print(f'SSH host key recorded: {key.get_name()} SHA256:{fingerprint}', flush=True)
            connection.get_host_keys().add(hostname, key.get_name(), key)
            connection.save_host_keys(str(known))

    client.set_missing_host_key_policy(FirstConnection())
    client.connect(
        credential['host'], username=credential['user'], password=password,
        timeout=15, banner_timeout=20, auth_timeout=20,
        look_for_keys=False, allow_agent=False,
    )
    return client, password


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--script', type=Path)
    group.add_argument('--command')
    group.add_argument('--upload', nargs=2, metavar=('LOCAL', 'REMOTE'))
    group.add_argument('--download', nargs=2, metavar=('REMOTE', 'LOCAL'))
    group.add_argument('--save-admin', action='store_true', help='Save cloud administrator credentials using Windows DPAPI')
    parser.add_argument('--timeout', type=int, default=900)
    args = parser.parse_args()
    client, secret = connect()
    try:
        if args.save_admin:
            target = LOCAL / 'admin-credentials.json'
            if target.exists():
                raise RuntimeError('Encrypted administrator file already exists')
            with client.open_sftp() as sftp, sftp.open('/opt/opc/shared/secrets/admin-login.json', 'rb') as remote:
                payload = remote.read()

            class Blob(ctypes.Structure):
                _fields_ = [('size', wintypes.DWORD), ('data', ctypes.POINTER(ctypes.c_byte))]

            buffer = (ctypes.c_byte * len(payload)).from_buffer_copy(payload)
            source, output = Blob(len(payload), buffer), Blob()
            if not ctypes.windll.crypt32.CryptProtectData(ctypes.byref(source), None, None, None, None, 5, ctypes.byref(output)):
                raise ctypes.WinError()
            try:
                encrypted = ctypes.string_at(output.data, output.size).hex()
            finally:
                ctypes.windll.kernel32.LocalFree(output.data)
            target.write_text(json.dumps({'format': 'Windows-DPAPI-local-machine-UTF8', 'encryption_scope': 'LocalMachine', 'payload_dpapi': encrypted}), encoding='utf-8')
            print('Administrator credentials saved using Windows DPAPI; no plaintext written locally.')
            return
        if args.upload or args.download:
            with client.open_sftp() as sftp:
                if args.upload:
                    source, target = args.upload
                    try:
                        sftp.stat(target)
                    except FileNotFoundError:
                        pass
                    else:
                        raise RuntimeError('Remote destination already exists; refusing to overwrite')
                    # Create exclusively and restrict permissions before transferring private bytes.
                    with Path(source).open('rb') as local, sftp.open(target, 'wx') as remote:
                        sftp.chmod(target, 0o600)
                        while chunk := local.read(1024 * 1024):
                            remote.write(chunk)
                else:
                    source, target = args.download
                    if Path(target).exists():
                        raise RuntimeError('Local destination already exists; refusing to overwrite')
                    sftp.get(source, target)
            print('SFTP transfer completed.', flush=True)
            return
        command = 'bash -se' if args.script else args.command
        stdin, stdout, _ = client.exec_command(command, timeout=30)
        if args.script:
            stdin.write(args.script.read_text(encoding='utf-8-sig'))
        stdin.channel.shutdown_write()
        channel = stdout.channel
        deadline = time.monotonic() + args.timeout
        while True:
            for ready, read, output in (
                (channel.recv_ready, channel.recv, sys.stdout),
                (channel.recv_stderr_ready, channel.recv_stderr, sys.stderr),
            ):
                while ready():
                    chunk = read(65536).decode('utf-8', errors='replace').replace(secret, '[REDACTED]')
                    output.write(chunk)
                    output.flush()
            if channel.exit_status_ready() and not channel.recv_ready() and not channel.recv_stderr_ready():
                raise SystemExit(channel.recv_exit_status())
            if time.monotonic() > deadline:
                raise TimeoutError('SSH command timed out; verify remote state before retrying')
            select.select([channel], [], [], 0.2)
    finally:
        client.close()


if __name__ == '__main__':
    main()
