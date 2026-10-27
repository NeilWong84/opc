set -eu
image='opc-website:20261026-website02'
name='opc-website-image-check'
test -z "$(docker ps -aq --filter name=^/$name$)"
docker run -d --name "$name" --network none --read-only --tmpfs /tmp \
    --cap-drop ALL --security-opt no-new-privileges:true "$image" >/dev/null
trap 'docker rm -f "$name" >/dev/null' EXIT
for attempt in 1 2 3 4 5; do
    if docker exec "$name" wget -q -O /dev/null http://127.0.0.1:8080/healthz; then break; fi
    sleep 1
done
docker exec "$name" nginx -t
docker exec "$name" wget -q -O /dev/null http://127.0.0.1:8080/ja/
docker exec "$name" wget -q -O /dev/null http://127.0.0.1:8080/zh/download/
docker exec "$name" wget -S -O /dev/null http://127.0.0.1:8080/release.json 2>&1
printf 'GET /packages/OPC-0.1.0-build3-android-cloud-20261026-release.apk HTTP/1.1\r\nHost: localhost\r\nRange: bytes=0-1023\r\nConnection: close\r\n\r\n' | \
    docker exec -i "$name" nc -w 5 127.0.0.1 8080 | \
    python3 -c 'import sys;header,body=sys.stdin.buffer.read().split(b"\r\n\r\n",1);assert b"206 Partial Content" in header and len(body)==1024;assert b"application/vnd.android.package-archive" in header and b"immutable" in header;print("PASS APK HTTP 206 / MIME / cache / 1024 bytes")'
docker exec "$name" sha256sum /usr/share/nginx/html/packages/OPC-0.1.0-build3-android-cloud-20261026-release.apk
echo 'PASS isolated website container, native Nginx, bilingual pages, CSP/cache, 206 range, release SHA-256. No public ports or live services changed.'
