#!/usr/bin/env bash
#
# setup-ssl.sh — One-time setup: install nginx + certbot, get Let's Encrypt cert
#
# Usage:
#   sudo setup-ssl.sh <domain>
#
# Example:
#   sudo setup-ssl.sh foreverskyin.tw
#
# Prerequisites:
#   - Domain DNS A record pointing to this server's public IP
#   - Port 80 and 443 open in firewall / security list
#
# Output: JSON with status
#

set -euo pipefail

DOMAIN="${1:?Usage: setup-ssl.sh <domain>}"
NGINX_CONF="/etc/nginx/sites-available/${DOMAIN}"
NGINX_PROTO_DIR="/etc/nginx/conf.d/prototypes"

result() {
  jq -n --arg status "$1" --arg message "$2" '{status: $status, message: $message}'
  [ "$1" = "ok" ] && exit 0 || exit 1
}

[ "$(id -u)" = "0" ] || result "error" "Must run as root (use sudo)"

echo "==> Installing nginx and certbot..."
apt-get update -qq
apt-get install -y -qq nginx certbot python3-certbot-nginx > /dev/null

echo "==> Opening ports 80 and 443 in iptables..."
iptables -I INPUT -p tcp --dport 80 -j ACCEPT 2>/dev/null || true
iptables -I INPUT -p tcp --dport 443 -j ACCEPT 2>/dev/null || true
# Persist iptables rules
if command -v netfilter-persistent >/dev/null 2>&1; then
  netfilter-persistent save 2>/dev/null || true
fi

echo "==> Creating nginx config for ${DOMAIN}..."
mkdir -p "$NGINX_PROTO_DIR"

cat > "$NGINX_CONF" <<NGINX
server {
    listen 80;
    server_name ${DOMAIN};

    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl;
    server_name ${DOMAIN};

    ssl_certificate /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;

    include ${NGINX_PROTO_DIR}/*.conf;

    location / {
        return 200 'Keypal is running :)';
        add_header Content-Type text/plain;
    }
}
NGINX

# Enable site
ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

echo "==> Getting Let's Encrypt certificate..."
# Stop nginx temporarily for standalone cert (in case it's the first time)
systemctl stop nginx 2>/dev/null || true
certbot certonly --standalone -d "$DOMAIN" --non-interactive --agree-tos --register-unsafely-without-email || \
  result "error" "Certbot failed — check DNS and firewall"

echo "==> Starting nginx..."
nginx -t || result "error" "Nginx config test failed"
systemctl enable nginx
systemctl start nginx

echo "==> Setting up auto-renewal cron..."
# certbot auto-renewal is usually set up by the package, but ensure it
systemctl enable certbot.timer 2>/dev/null || \
  (crontab -l 2>/dev/null; echo "0 3 * * * certbot renew --quiet --post-hook 'systemctl reload nginx'") | sort -u | crontab -

result "ok" "SSL setup complete for ${DOMAIN}. Nginx running with HTTPS."
