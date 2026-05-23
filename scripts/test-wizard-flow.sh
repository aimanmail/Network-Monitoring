#!/bin/bash
# Validate fresh web setup wizard behavior (run on LibreNMS server after install)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=== Wizard flow validation ==="

fail() { echo "FAIL: $1"; exit 1; }

grep -q 'migrate --force' "$REPO_DIR/install-librenms-ubuntu.sh" && fail 'installer still runs migrate'
grep -q 'config:cache' "$REPO_DIR/install-librenms-ubuntu.sh" && fail 'installer still runs config:cache'
grep -q 'INSTALL=true' "$REPO_DIR/config/env.example" || fail 'env.example missing INSTALL=true'

if [ -f /opt/librenms/.env ]; then
  if grep -q '^INSTALL=' /opt/librenms/.env; then
    sudo sed -i 's|^INSTALL=.*|INSTALL=true|' /opt/librenms/.env
  else
    echo 'INSTALL=true' | sudo tee -a /opt/librenms/.env >/dev/null
  fi
  sudo rm -f /opt/librenms/config.php /opt/librenms/bootstrap/cache/config.php
  sudo -u librenms php /opt/librenms/artisan config:clear >/dev/null
fi

if command -v mysql >/dev/null; then
  TABLES=$(mysql -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='librenms';" 2>/dev/null || echo 0)
  MIG=$(mysql -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='librenms' AND table_name='migrations';" 2>/dev/null || echo 0)
  echo "librenms tables: $TABLES (migrations table present: $MIG)"
fi

if command -v curl >/dev/null && systemctl is-active --quiet apache2; then
  FINAL=$(curl -sL -o /dev/null -w '%{url_effective}' http://127.0.0.1/ 2>/dev/null || true)
  echo "GET / (follow redirects): ${FINAL:-unavailable}"
  echo "$FINAL" | grep -q 'install' || fail 'root URL does not reach install wizard'
fi

echo "PASS: wizard flow checks OK"
