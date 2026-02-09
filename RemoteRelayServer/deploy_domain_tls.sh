#!/usr/bin/env bash
# Deploy AirCatch relay with domain + TLS (Nginx + Let's Encrypt).
# Usage:
#   ./deploy_domain_tls.sh --domain relay.qai88.com --email you@example.com [--node-port 8080]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOMAIN=""
EMAIL=""
NODE_PORT="8080"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --domain)
      DOMAIN="${2:-}"
      shift 2
      ;;
    --email)
      EMAIL="${2:-}"
      shift 2
      ;;
    --node-port)
      NODE_PORT="${2:-8080}"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$DOMAIN" || -z "$EMAIL" ]]; then
  cat <<EOF
Usage:
  ./deploy_domain_tls.sh --domain relay.qai88.com --email you@example.com [--node-port 8080]
EOF
  exit 1
fi

if [[ "$EUID" -ne 0 ]]; then
  echo "Run as root (or: sudo $0 ...)" >&2
  exit 1
fi

echo "==> Installing system packages"
apt-get update -y
apt-get install -y nginx certbot python3-certbot-nginx nodejs npm curl

echo "==> Installing relay app"
install -d -m 755 /opt/aircatch-relay
cp "$SCRIPT_DIR/server.js" /opt/aircatch-relay/server.js
cp "$SCRIPT_DIR/package.json" /opt/aircatch-relay/package.json
if [[ -f "$SCRIPT_DIR/package-lock.json" ]]; then
  cp "$SCRIPT_DIR/package-lock.json" /opt/aircatch-relay/package-lock.json
fi

pushd /opt/aircatch-relay >/dev/null
if [[ -f package-lock.json ]]; then
  npm ci --omit=dev
else
  npm install --omit=dev
fi
popd >/dev/null

echo "==> Creating systemd service"
cat >/etc/systemd/system/aircatch-relay.service <<EOF
[Unit]
Description=AirCatch Relay Server
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/aircatch-relay
ExecStart=/usr/bin/node /opt/aircatch-relay/server.js
Environment=NODE_ENV=production
Environment=PORT=${NODE_PORT}
Restart=always
RestartSec=3
User=root
Group=root

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now aircatch-relay

echo "==> Configuring nginx reverse proxy"
cat >/etc/nginx/sites-available/aircatch-relay <<EOF
server {
    listen 80;
    server_name ${DOMAIN};

    location / {
        proxy_pass http://127.0.0.1:${NODE_PORT};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

ln -sf /etc/nginx/sites-available/aircatch-relay /etc/nginx/sites-enabled/aircatch-relay
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl reload nginx

echo "==> Requesting TLS certificate"
certbot --nginx --non-interactive --agree-tos --redirect -m "$EMAIL" -d "$DOMAIN"

echo "==> Deployment complete"
echo "Relay URL: wss://${DOMAIN}"
echo "Health: https://${DOMAIN}/health"
echo
echo "Useful commands:"
echo "  systemctl status aircatch-relay --no-pager"
echo "  journalctl -u aircatch-relay -f"
