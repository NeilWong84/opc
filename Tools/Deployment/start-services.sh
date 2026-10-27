set -eu
cd /opt/opc/releases/20261026-01
compose() { docker compose --env-file /opt/opc/shared/site.env -f Deploy/compose.yaml "$@"; }
compose config --quiet
compose up -d --wait --wait-timeout 120 postgres
compose --profile tools run --rm --no-deps --interactive=false -T migrate
compose up -d --wait --wait-timeout 180 backend admin nginx
test ! -e /opt/opc/current
ln -s /opt/opc/releases/20261026-01 /opt/opc/current
compose ps
docker stats --no-stream --format '{{.Name}} {{.MemUsage}} {{.CPUPerc}}'
