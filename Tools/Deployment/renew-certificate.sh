#!/usr/bin/env bash
set -eu
cd /opt/opc/current
docker run --rm \
  -v /opt/opc/shared/letsencrypt:/etc/letsencrypt \
  -v /opt/opc/shared/acme:/var/www/acme \
  certbot/certbot:v5.4.0 renew --quiet --no-random-sleep-on-renew --webroot --webroot-path /var/www/acme
docker compose --env-file /opt/opc/shared/site.env -f Deploy/compose.yaml exec --interactive=false -T nginx nginx -t
docker compose --env-file /opt/opc/shared/site.env -f Deploy/compose.yaml exec --interactive=false -T nginx nginx -s reload
