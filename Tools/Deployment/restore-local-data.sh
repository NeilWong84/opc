#!/usr/bin/env bash
# This one-time import creates a separate database and never overwrites opc_test.
set -eu
umask 077
cd /opt/opc/current
compose() { docker compose --env-file /opt/opc/shared/site.env -f Deploy/compose.yaml "$@"; }
stage=/opt/opc/shared/migration-20261026
test ! -e "$stage"
printf '%s  %s\n' '2c16586fe7ceb496e0e664e309ba054f3845f1b799c9248022e586d4c49c6417' /tmp/opc-data-20261026.tar.gz | sha256sum -c -
test "$(compose exec --interactive=false -T -u postgres postgres psql -U postgres -d postgres -tAc "SELECT count(*) FROM pg_database WHERE datname='opc_migrated_20261026'")" = 0
mkdir -m 700 "$stage"
tar --no-same-owner -xzf /tmp/opc-data-20261026.tar.gz -C "$stage"
install -m 600 /tmp/opc-verify-import-20261026.py "$stage/verify-import.py"
find "$stage" -type f -exec chmod 600 {} +
chown -R 10001:10001 "$stage"
chmod 700 "$stage/files"
compose exec --interactive=false -T -u postgres postgres createdb -U postgres -T template0 --encoding=UTF8 --locale-provider=builtin --builtin-locale=C.UTF-8 opc_migrated_20261026
cat "$stage/opc_integration.dump" | compose exec -T -u postgres postgres pg_restore -U postgres --no-owner --no-privileges --exit-on-error -d opc_migrated_20261026
compose exec --interactive=false -T -u postgres postgres psql -U postgres -d postgres -v ON_ERROR_STOP=1 -c "COMMENT ON DATABASE opc_migrated_20261026 IS 'opc.cloud-test.v1'"
compose --profile tools run --rm --no-deps --interactive=false -T --entrypoint python -v "$stage:/migration:ro" migrate /migration/verify-import.py > "$stage/verification.json"
cat "$stage/verification.json"
printf 'Isolated restore verified. Existing cloud application still uses its previous database.\n'
