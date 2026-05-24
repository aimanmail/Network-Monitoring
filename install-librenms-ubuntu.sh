#!/bin/bash
# Install LibreNMS on Ubuntu 22.04+ — APP_URL uses THIS server's IP automatically
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root: sudo $0"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DB_PASS="${LIBRENMS_DB_PASS:-librenms}"

# Auto-detect server IP (first non-loopback IPv4), or override with LIBRENMS_APP_URL
detect_server_ip() {
  local ip
  ip=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}')
  if [ -z "$ip" ]; then
    ip=$(hostname -I | awk '{print $1}')
  fi
  echo "$ip"
}

SERVER_IP="$(detect_server_ip)"
APP_URL="${LIBRENMS_APP_URL:-http://${SERVER_IP}}"

echo "=== LibreNMS install for Ubuntu ==="
echo "Detected server IP: $SERVER_IP"
echo "APP_URL:            $APP_URL"
echo "(Override: sudo LIBRENMS_APP_URL=http://OTHER_IP $0)"

apt update
apt install -y apache2 mariadb-server libapache2-mod-php \
  php php-cli php-mysql php-gd php-snmp php-mbstring \
  php-xml php-curl php-zip php-bcmath php-intl \
  composer git snmp snmp-mibs-downloader rrdtool nmap acl curl

id librenms &>/dev/null || useradd librenms -d /opt/librenms -M -r -s /bin/bash

if [ ! -d /opt/librenms/.git ]; then
  git clone https://github.com/librenms/librenms.git /opt/librenms
fi

chown -R librenms:librenms /opt/librenms
usermod -a -G librenms www-data
setfacl -d -m g::rwx /opt/librenms/rrd /opt/librenms/logs /opt/librenms/bootstrap/cache/ /opt/librenms/storage/ 2>/dev/null || true
setfacl -R -m g::rwx /opt/librenms/rrd /opt/librenms/logs /opt/librenms/bootstrap/cache/ /opt/librenms/storage/ 2>/dev/null || true

mysql -e "CREATE DATABASE IF NOT EXISTS librenms CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
mysql -e "CREATE USER IF NOT EXISTS 'librenms'@'localhost' IDENTIFIED BY '${DB_PASS}';"
mysql -e "GRANT ALL PRIVILEGES ON librenms.* TO 'librenms'@'localhost'; FLUSH PRIVILEGES;"

if [ -f /opt/librenms/config.php ]; then
  echo "Existing LibreNMS installation detected (config.php present). Skipping wizard .env changes."
elif [ ! -f /opt/librenms/.env ]; then
  cp "$SCRIPT_DIR/config/env.example" /opt/librenms/.env
  sed -i "s|APP_URL=.*|APP_URL=${APP_URL}|" /opt/librenms/.env
  chown librenms:librenms /opt/librenms/.env
else
  # Fresh install: keep wizard enabled until setup finishes in the browser
  if grep -q '^INSTALL=' /opt/librenms/.env; then
    sed -i 's|^INSTALL=.*|INSTALL=true|' /opt/librenms/.env
  else
    echo 'INSTALL=true' >> /opt/librenms/.env
  fi
  chown librenms:librenms /opt/librenms/.env
fi

sudo -u librenms composer install --no-dev -d /opt/librenms
sudo -u librenms php /opt/librenms/artisan key:generate --force
sudo -u librenms php /opt/librenms/artisan config:clear
rm -f /opt/librenms/bootstrap/cache/config.php

cp "$SCRIPT_DIR/config/librenms.conf" /etc/apache2/sites-available/librenms.conf
a2ensite librenms.conf
a2enmod rewrite headers
a2dissite 000-default.conf 2>/dev/null || true
systemctl restart apache2

cp "$SCRIPT_DIR/config/librenms-scheduler.service" /etc/systemd/system/
cp "$SCRIPT_DIR/config/librenms-scheduler.timer" /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now librenms-scheduler.timer

# Create lab.env from example if missing (friend edits ROUTER_IP for their GNS3)
if [ ! -f "$SCRIPT_DIR/config/lab.env" ]; then
  cp "$SCRIPT_DIR/config/lab.env.example" "$SCRIPT_DIR/config/lab.env"
  echo "# LibreNMS server IP (auto): $SERVER_IP" >> "$SCRIPT_DIR/config/lab.env"
fi

chmod +x "$SCRIPT_DIR/scripts/"*.sh 2>/dev/null || true

echo ""
echo "=== Install complete ==="
echo "LibreNMS URL:  $APP_URL"
echo "Server IP:     $SERVER_IP"
echo ""
echo "Open the URL above in your browser to run the official LibreNMS setup wizard."
echo "You will be redirected to the wizard automatically (via /install)."
echo "If not, open: ${APP_URL}/install"
echo ""
echo "Use these database credentials in the wizard:"
echo "  Host:      localhost"
echo "  Database:  librenms"
echo "  Username:  librenms"
echo "  Password:  $DB_PASS"
echo "(Override password: sudo LIBRENMS_DB_PASS=yourpass ./install-librenms-ubuntu.sh)"
echo ""
echo "After the wizard completes, edit config/lab.env (ROUTER_IP, ROUTER_MAC) for YOUR GNS3 lab, then:"
echo "  bash $SCRIPT_DIR/scripts/fix-librenms-graphs.sh"
