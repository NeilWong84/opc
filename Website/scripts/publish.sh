set -eu
tag='__RELEASE_TAG__'
phase='__DEPLOY_PHASE__'
archive="/tmp/opc-website-$tag.tar.gz"
echo '__ARCHIVE_SHA256__'"  $archive" | sha256sum -c -
previous=$(readlink -f /opt/opc/current)
case "$previous" in /opt/opc/releases/*) ;; *) echo 'Unexpected source directory'; exit 1;; esac
release="/opt/opc/releases/$tag"
if [ "$phase" = publish ]; then
    test -d "$release/Website/dist"
else
    test ! -e "$release"
    cp -a "$previous" "$release"
    tar -xzf "$archive" -C "$release"
fi
cd "$release"
backup="/opt/opc/shared/site.before-$tag.env"
if [ "$phase" != publish ]; then
    test ! -e "$backup"
    cp -p /opt/opc/shared/site.env "$backup"
fi
before=$(docker inspect --format '{{.Id}}:{{.State.StartedAt}}' opc-test-postgres-1 opc-test-backend-1)
export ADMIN_IMAGE_TAG="$tag" WEBSITE_IMAGE_TAG="$tag" ADMIN_PUBLIC_ORIGIN='https://admin.opcapp.art/'
docker compose --env-file /opt/opc/shared/site.env -f Deploy/compose.yaml config --quiet
if [ "$phase" != publish ]; then
    docker compose --env-file /opt/opc/shared/site.env -f Deploy/compose.yaml --progress plain build website admin > "/opt/opc/shared/website-build-$tag.log" 2>&1
    tail -n 12 "/opt/opc/shared/website-build-$tag.log"
fi
if [ "$phase" = stage ]; then
    echo "Staged $tag: images ready; live containers unchanged."
    exit 0
fi
# Existing port 80 already serves HTTP-01 for any host; retain the separate IP certificate.
if [ ! -s /opt/opc/shared/letsencrypt/live/opc-domains/fullchain.pem ]; then
    docker run --rm \
        -v /opt/opc/shared/letsencrypt:/etc/letsencrypt \
        -v /opt/opc/shared/acme:/var/www/acme \
        certbot/certbot:v5.4.0 certonly --non-interactive \
        --cert-name opc-domains -d www.opcapp.art -d admin.opcapp.art \
        --webroot --webroot-path /var/www/acme
fi
# Only these two presentation containers are replaced; no backend/PG operations.
rollback() {
    result=$?
    if [ "$result" != 0 ]; then
        echo 'Restoring previous public/admin configuration.'
        cp -p "$backup" /opt/opc/shared/site.env
        unset ADMIN_IMAGE_TAG WEBSITE_IMAGE_TAG ADMIN_PUBLIC_ORIGIN
        if docker compose --env-file "$backup" -f "$previous/Deploy/compose.yaml" config --services | grep -qx website; then
            docker compose --env-file "$backup" -f "$previous/Deploy/compose.yaml" up -d --no-deps website admin nginx || true
        else
            docker compose --env-file "$backup" -f "$previous/Deploy/compose.yaml" up -d --no-deps admin nginx || true
        fi
        ln -sfn "$previous" /opt/opc/current
    fi
    exit "$result"
}
trap rollback EXIT
docker compose --env-file /opt/opc/shared/site.env -f Deploy/compose.yaml up -d --no-deps website admin
for service in website admin; do
    count=0
    while [ "$(docker inspect --format '{{.State.Health.Status}}' "opc-test-$service-1")" != healthy ]; do
        count=$((count+1)); test "$count" -lt 30; sleep 1
    done
done
docker run --rm --network opc-test_edge --entrypoint nginx \
    -v "$release/Deploy/nginx/default.conf:/etc/nginx/conf.d/default.conf:ro" \
    -v "$release/Deploy/nginx/proxy_params:/etc/nginx/opc_proxy_params:ro" \
    -v "$release/Deploy/nginx/api_locations:/etc/nginx/opc_api_locations:ro" \
    -v /opt/opc/shared/letsencrypt:/etc/letsencrypt:ro nginx:1.28-alpine -t
docker compose --env-file /opt/opc/shared/site.env -f Deploy/compose.yaml up -d --no-deps nginx
python3 - "$tag" <<'PY'
import pathlib,sys
p=pathlib.Path('/opt/opc/shared/site.env')
lines=[line for line in p.read_text().splitlines() if not line.startswith(('ADMIN_IMAGE_TAG=','WEBSITE_IMAGE_TAG=','ADMIN_PUBLIC_ORIGIN='))]
lines += ['ADMIN_IMAGE_TAG='+sys.argv[1],'WEBSITE_IMAGE_TAG='+sys.argv[1],'ADMIN_PUBLIC_ORIGIN=https://admin.opcapp.art/']
p.write_text('\n'.join(lines)+'\n')
PY
ln -sfn "$release" /opt/opc/current
after=$(docker inspect --format '{{.Id}}:{{.State.StartedAt}}' opc-test-postgres-1 opc-test-backend-1)
test "$before" = "$after"
curl --fail --silent --show-error https://43.165.191.156/health/ready
curl --fail --silent --show-error https://www.opcapp.art/ja/ -o "/opt/opc/shared/website-check-$tag.html"
grep -q 'OPC' "/opt/opc/shared/website-check-$tag.html"
curl --fail --silent --show-error https://admin.opcapp.art/ -o "/opt/opc/shared/admin-check-$tag.html"
grep -q 'id="app"' "/opt/opc/shared/admin-check-$tag.html"
docker compose --env-file /opt/opc/shared/site.env -f Deploy/compose.yaml ps --format '{{.Service}} {{.State}} {{.Health}}'
echo "Published https://www.opcapp.art/ and https://admin.opcapp.art/; backend/PG IDs and start times unchanged. Previous source: $previous"
trap - EXIT
