set -eu
cd /opt/opc/releases/20261026-01
install -m 0644 /tmp/opc-package-lock-verified.json FrontendAdmin/package-lock.json
install -d FrontendAdmin/scripts
install -m 0644 /tmp/opc-production-guard.mjs FrontendAdmin/scripts/production-guard.mjs
docker compose --env-file /opt/opc/shared/site.env -f Deploy/compose.yaml --progress plain build admin > /opt/opc/admin-build.log 2>&1
tail -n 25 /opt/opc/admin-build.log
