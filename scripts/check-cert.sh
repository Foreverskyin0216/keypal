#!/usr/bin/env bash
#
# check-cert.sh — Check Let's Encrypt certificate expiry, renew if needed
#
# Usage:
#   check-cert.sh [domain]
#
# Domain defaults to PUBLIC_DOMAIN env var.
# Renews if cert expires within 30 days.
#
# Output: JSON with status, domain, expires_at, days_remaining
#

set -euo pipefail

DOMAIN="${1:-${PUBLIC_DOMAIN:-}}"
[ -n "$DOMAIN" ] || { jq -n '{status: "skip", message: "No domain configured (set PUBLIC_DOMAIN)"}'; exit 0; }

CERT_PATH="/etc/letsencrypt/live/${DOMAIN}/fullchain.pem"
RENEW_THRESHOLD=30  # days

result() {
  jq -n \
    --arg status "$1" \
    --arg domain "$DOMAIN" \
    --arg message "$2" \
    --arg expires_at "${3:-}" \
    --argjson days_remaining "${4:-null}" \
    '{status: $status, domain: $domain, message: $message, expires_at: $expires_at, days_remaining: $days_remaining}'
}

if [ ! -f "$CERT_PATH" ]; then
  result "warning" "No certificate found at ${CERT_PATH}" "" null
  exit 0
fi

# Get expiry date
EXPIRY=$(openssl x509 -enddate -noout -in "$CERT_PATH" 2>/dev/null | cut -d= -f2)
[ -n "$EXPIRY" ] || { result "error" "Cannot read certificate" "" null; exit 1; }

EXPIRY_EPOCH=$(date -d "$EXPIRY" +%s 2>/dev/null || date -j -f "%b %d %T %Y %Z" "$EXPIRY" +%s 2>/dev/null)
NOW_EPOCH=$(date +%s)
DAYS_LEFT=$(( (EXPIRY_EPOCH - NOW_EPOCH) / 86400 ))
EXPIRY_ISO=$(date -d "$EXPIRY" -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -j -f "%b %d %T %Y %Z" "$EXPIRY" -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)

if [ "$DAYS_LEFT" -le 0 ]; then
  result "error" "Certificate EXPIRED" "$EXPIRY_ISO" "$DAYS_LEFT"
  exit 1
elif [ "$DAYS_LEFT" -le "$RENEW_THRESHOLD" ]; then
  # Try to renew
  if command -v certbot >/dev/null 2>&1; then
    if sudo certbot renew --quiet 2>/dev/null; then
      sudo systemctl reload nginx 2>/dev/null || true
      result "ok" "Certificate renewed (was ${DAYS_LEFT} days from expiry)" "$EXPIRY_ISO" "$DAYS_LEFT"
    else
      result "warning" "Certificate expires in ${DAYS_LEFT} days — renewal failed" "$EXPIRY_ISO" "$DAYS_LEFT"
    fi
  else
    result "warning" "Certificate expires in ${DAYS_LEFT} days — certbot not installed" "$EXPIRY_ISO" "$DAYS_LEFT"
  fi
else
  result "ok" "Certificate valid (${DAYS_LEFT} days remaining)" "$EXPIRY_ISO" "$DAYS_LEFT"
fi
