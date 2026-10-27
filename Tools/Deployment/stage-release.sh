set -eu
archive=${1:?Archive path required}
digest=${2:?SHA256 required}
tag=${3:?Release tag required}
origin=${4:?HTTPS origin required}
case "$tag" in ''|*[!a-z0-9.-]*|.|..) exit 2;; esac
case "$digest" in ''|*[!a-f0-9]*) exit 2;; esac
[ "${#digest}" -eq 64 ]
release="/opt/opc/releases/$tag"
printf '%s  %s\n' "$digest" "$archive" | sha256sum -c -
test ! -e "$release"
install -d -m 0755 "$release"
tar -xzf "$archive" -C "$release"
cd "$release"
if [ ! -e /opt/opc/shared/site.env ]; then
    python3 Tools/Deployment/prepare-host.py --origin "$origin" --tag "$tag"
fi
# Build the requested release without changing the currently running configuration.
export IMAGE_TAG="$tag" ADMIN_IMAGE_TAG="$tag" WEBSITE_IMAGE_TAG="$tag" PUBLIC_ORIGIN="$origin"
docker compose --env-file /opt/opc/shared/site.env -f Deploy/compose.yaml config --quiet
docker compose --env-file /opt/opc/shared/site.env -f Deploy/compose.yaml --progress plain build backend admin website
