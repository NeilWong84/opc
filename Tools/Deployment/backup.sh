#!/usr/bin/env bash
# Consistent backup: briefly stop this deployment's API while dumping DB/files.
set -eu
cd /opt/opc/current
compose() { docker compose --env-file /opt/opc/shared/site.env -f Deploy/compose.yaml "$@"; }
. /opt/opc/shared/site.env
database=${DATABASE_NAME:-opc_test}
files=${FILES_ROOT:-$DATA_ROOT/files}
case "$database" in ''|*[!a-z0-9_]*) exit 2;; esac
test -d "$files"
destination="/opt/opc/backups/$(date -u +%Y%m%dT%H%M%SZ)"
umask 077
mkdir -p "$destination"
compose stop backend
trap 'compose start backend' EXIT
compose exec --interactive=false -T -u postgres postgres pg_dump -U postgres -Fc "$database" > "$destination/opc.dump"
compose exec --interactive=false -T -u postgres postgres psql -U postgres -d "$database" -tAc "SELECT json_build_object('migrations',(SELECT count(*) FROM opc.schema_migrations),'accounts',(SELECT count(*) FROM opc.accounts),'requests',(SELECT count(*) FROM opc.requests),'messages',(SELECT count(*) FROM opc.messages),'files',(SELECT count(*) FROM opc.files))" > "$destination/counts.json"
tar -czf "$destination/files.tar.gz" -C "$files" .
cp /opt/opc/shared/site.env "$destination/site.env"
sha256sum "$destination/opc.dump" "$destination/files.tar.gz" "$destination/counts.json" > "$destination/SHA256SUMS"
printf 'Backup completed: %s\n' "$destination"
