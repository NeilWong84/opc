set -eu
test -L /opt/opc/current
test -s /opt/opc/shared/letsencrypt/live/opc/fullchain.pem
install -m 0750 /opt/opc/current/Tools/Deployment/renew-certificate.sh /opt/opc/renew-certificate.sh
cat > /etc/systemd/system/opc-certificate-renew.service <<'EOF'
[Unit]
Description=Renew OPC IP TLS certificate and reload its gateway
Requires=docker.service
After=docker.service network-online.target

[Service]
Type=oneshot
ExecStart=/opt/opc/renew-certificate.sh
TimeoutStartSec=10min
EOF
cat > /etc/systemd/system/opc-certificate-renew.timer <<'EOF'
[Unit]
Description=Check OPC six-day TLS certificate every six hours

[Timer]
OnBootSec=10min
OnUnitActiveSec=6h
RandomizedDelaySec=15min
Persistent=true

[Install]
WantedBy=timers.target
EOF
systemctl daemon-reload
systemctl enable --now opc-certificate-renew.timer
systemctl start opc-certificate-renew.service
systemctl show opc-certificate-renew.service -p Result -p ExecMainStatus
systemctl list-timers opc-certificate-renew.timer --no-pager
docker run --rm \
  -v /opt/opc/shared/letsencrypt:/etc/letsencrypt \
  -v /opt/opc/shared/acme:/var/www/acme \
  certbot/certbot:v5.4.0 renew --dry-run --no-random-sleep-on-renew --webroot --webroot-path /var/www/acme
