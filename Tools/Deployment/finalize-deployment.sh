set -eu
umask 077
archive=/tmp/opc-20261026-02-final.tar.gz
printf '%s  %s\n' '26953669d70dd6ad8e923f62673abf9c065fc32917903199f7ece8bb012cb2be' "$archive" | sha256sum -c -
test "$(readlink -f /opt/opc/current)" = /opt/opc/releases/20261026-02
tar --no-same-owner -xzf "$archive" -C /opt/opc/releases/20261026-02
install -m 600 /tmp/opc-20261026-02-final.manifest.json /opt/opc/releases/20261026-02/source-manifest.json
cd /opt/opc/current
python3 - <<'PY'
from hashlib import sha256
import json
from pathlib import Path
root = Path.cwd()
manifest = json.loads((root / 'source-manifest.json').read_text())
assert all(sha256((root / name).read_bytes()).hexdigest() == digest for name, digest in manifest.items())
print('PASS final source manifest: ' + str(len(manifest)) + ' files')
PY
# The verified source dump remains in its private staging directory and local snapshot.
rm -f /tmp/opc-data-20261026.tar.gz /tmp/opc-verify-import-20261026.py
docker compose --env-file /opt/opc/shared/site.env -f Deploy/compose.yaml config --quiet
docker compose --env-file /opt/opc/shared/site.env -f Deploy/compose.yaml ps
systemctl is-active opc-certificate-renew.timer
systemctl show opc-certificate-renew.service -p Result -p ExecMainStatus
curl --fail --silent --show-error --max-time 20 https://43.165.191.156/health/ready
printf '\n'
docker stats --no-stream --format '{{.Name}} {{.MemUsage}}'
df -h /opt/opc
