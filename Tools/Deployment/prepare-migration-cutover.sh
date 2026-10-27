set -eu
umask 077
archive=/tmp/opc-20261026-02.tar.gz
printf '%s  %s\n' '74115f2f174e998445165dbd4f96f03956dbb2fbc316ae2d9fd5867695880976' "$archive" | sha256sum -c -
release=/opt/opc/releases/20261026-02
test ! -e "$release"
mkdir -m 755 "$release"
tar --no-same-owner -xzf "$archive" -C "$release"
cat > /opt/opc/shared/migration-site.env <<'EOF'
PUBLIC_ORIGIN=https://43.165.191.156
IMAGE_TAG=20261026-02
DATA_ROOT=/opt/opc/shared
DATABASE_NAME=opc_migrated_20261026
FILES_ROOT=/opt/opc/shared/migration-20261026/files
EOF
cd "$release"
compose() { docker compose --env-file /opt/opc/shared/migration-site.env -f Deploy/compose.yaml "$@"; }
compose config --quiet
compose --progress plain build backend admin
compose --profile tools run --rm --no-deps --interactive=false -T migrate
printf 'New release built; migrated database permissions and migration checksums verified.\n'
