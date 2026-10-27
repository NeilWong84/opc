set -eu
cd /opt/opc/current
compose() { docker compose --env-file /opt/opc/shared/site.env -f Deploy/compose.yaml "$@"; }
database=opc_restore_verification_20261026
test "$(compose exec --interactive=false -T -u postgres postgres psql -U postgres -d postgres -tAc "SELECT count(*) FROM pg_database WHERE datname='opc_restore_verification_20261026'")" = 0
backup=$(find /opt/opc/backups -name files.tar.gz -printf '%h\n' | sort | tail -n 1)
test -s "$backup/opc.dump"
test -s "$backup/files.tar.gz"
sha256sum -c "$backup/SHA256SUMS"
compose exec --interactive=false -T -u postgres postgres createdb -U postgres -T template0 "$database"
trap 'compose exec --interactive=false -T -u postgres postgres dropdb -U postgres "$database"' EXIT
cat "$backup/opc.dump" | compose exec -T -u postgres postgres pg_restore -U postgres --exit-on-error -d "$database"
actual=$(compose exec --interactive=false -T -u postgres postgres psql -U postgres -d "$database" -tAc "SELECT json_build_object('migrations',(SELECT count(*) FROM opc.schema_migrations),'accounts',(SELECT count(*) FROM opc.accounts),'requests',(SELECT count(*) FROM opc.requests),'messages',(SELECT count(*) FROM opc.messages),'files',(SELECT count(*) FROM opc.files))")
test "$actual" = "$(cat "$backup/counts.json")"
printf 'Restored counts: %s\n' "$actual"
test "$(tar -tzf "$backup/files.tar.gz" | sed '/\/$/d' | wc -l)" = "$(compose exec --interactive=false -T -u postgres postgres psql -U postgres -d "$database" -tAc 'SELECT count(*) FROM opc.files')"
printf 'PASS isolated PostgreSQL backup restore; original database retained.\n'
