set -eu
umask 077
old=/opt/opc/releases/20261026-01
new=/opt/opc/releases/20261026-02
backup=/opt/opc/shared/site.pre-migration.env
test "$(readlink -f /opt/opc/current)" = "$old"
test ! -e "$backup"
test -s /opt/opc/shared/migration-20261026/verification.json
cd "$old"
compose() { docker compose --env-file /opt/opc/shared/site.env -f Deploy/compose.yaml "$@"; }
test "$(compose exec --interactive=false -T -u postgres postgres psql -U postgres -d opc_test -tAc 'SELECT count(*) FROM opc.requests')" = 0
compose stop backend
cp /opt/opc/shared/site.env "$backup"
install -m 600 /opt/opc/shared/migration-site.env /opt/opc/shared/site.env
ln -sfn "$new" /opt/opc/current
cd "$new"
if ! compose up -d --wait --wait-timeout 180 backend admin nginx; then
    install -m 600 "$backup" /opt/opc/shared/site.env
    ln -sfn "$old" /opt/opc/current
    cd "$old"
    compose up -d --wait --wait-timeout 180 backend admin nginx
    printf 'Cutover failed and previous environment restored.\n'
    exit 1
fi
compose ps
compose exec --interactive=false -T -u postgres postgres psql -U postgres -d opc_migrated_20261026 -tAc "SELECT json_build_object('accounts',(SELECT count(*) FROM opc.accounts),'requests',(SELECT count(*) FROM opc.requests),'engagements',(SELECT count(*) FROM opc.engagements),'messages',(SELECT count(*) FROM opc.messages),'files',(SELECT count(*) FROM opc.files))"
printf 'Cutover complete; old database and files retained.\n'
