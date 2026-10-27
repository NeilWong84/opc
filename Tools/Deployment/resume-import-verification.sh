set -eu
cd /opt/opc/current
stage=/opt/opc/shared/migration-20261026
chown -R 10001:10001 "$stage"
docker compose --env-file /opt/opc/shared/site.env -f Deploy/compose.yaml --profile tools run --rm --no-deps --interactive=false -T --entrypoint python -v "$stage:/migration:ro" migrate /migration/verify-import.py > "$stage/verification.json"
cat "$stage/verification.json"
