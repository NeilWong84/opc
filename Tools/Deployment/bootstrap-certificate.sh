set -eu
cd /opt/opc/releases/20261026-01
if [ -s /opt/opc/shared/letsencrypt/live/opc/fullchain.pem ]; then
  printf 'Existing OPC certificate retained.\n'
  exit 0
fi
docker run --detach --rm --name opc-test-acme-bootstrap \
  --label opc.managed=cloud-test \
  --publish 80:80 \
  -v "$PWD/Deploy/nginx/acme-bootstrap.conf:/etc/nginx/conf.d/default.conf:ro" \
  -v /opt/opc/shared/acme:/var/www/acme:ro \
  nginx:1.28-alpine
trap 'docker stop opc-test-acme-bootstrap >/dev/null' EXIT
docker run --rm \
  -v /opt/opc/shared/letsencrypt:/etc/letsencrypt \
  -v /opt/opc/shared/acme:/var/www/acme \
  certbot/certbot:v5.4.0 certonly --non-interactive --agree-tos \
  --register-unsafely-without-email --preferred-profile shortlived \
  --ip-address 43.165.191.156 --cert-name opc \
  --webroot --webroot-path /var/www/acme
