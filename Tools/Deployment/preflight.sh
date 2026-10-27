export LC_ALL=C
printf '\n[SYSTEM]\n'
uname -smr
cat /etc/os-release
id
nproc
free -m
df -hT /
printf '\n[LISTENERS]\n'
ss -lnt
printf '\n[RUNTIME]\n'
if command -v docker >/dev/null 2>&1; then
  docker version --format '{{.Server.Version}}'
  docker compose version
  docker ps --format '{{.Names}} {{.Image}} {{.Ports}}'
fi
printf '\n[FIREWALL]\n'
if command -v ufw >/dev/null 2>&1; then ufw status; fi
printf '\n[DEPLOYMENT DIRECTORY]\n'
if [ -e /opt/opc ]; then ls -ld /opt/opc; else printf 'New deployment directory available\n'; fi
printf '\n[HTTPS CONNECTIVITY]\n'
for endpoint in https://download.docker.com/linux/ubuntu/gpg https://registry-1.docker.io/v2/; do
  printf '%s ' "$endpoint"
  curl -sS -o /dev/null -w 'HTTP=%{http_code}\n' --connect-timeout 5 --max-time 10 "$endpoint" || true
done
