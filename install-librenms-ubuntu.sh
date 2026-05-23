#!/bin/bash
# Install LibreNMS on Ubuntu 24.04 (matches aiman@server setup)
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root: sudo $0"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DB_PASS="${LIBRENMS_DB_PASS:-librenms_lab_pass_change_me}"
APP_URL="${LIBRENMS_APP_URL:-http://$(hostname -I | awk '{print $1}')}"

echo "=== LibreNMS install for Ubuntu 24.04 ==="
echo "APP_URL will be: $APP_URL"

apt update
apt install -y apache2 mariadb-server libapache2-mod-php8.3 \
  php8.3-cli php8.3-mysql php8.3-gd php8.3-snmp php8.3-mbstring \
  php8.3-xml php8.3-curl php8.3-zip php8.3-bcmath php8.3-intl \
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

if [ ! -f /opt/librenms/.env ]; then
  cp "$SCRIPT_DIR/config/env.example" /opt/librenms/.env
  sed -i "s|APP_URL=.*|APP_URL=${APP_URL}|" /opt/librenms/.env
  sed -i "s|DB_PASSWORD=.*|DB_PASSWORD=${DB_PASS}|" /opt/librenms/.env
  chown librenms:librenms /opt/librenms/.env
fi

sudo -u librenms composer install --no-dev -d /opt/librenms
sudo -u librenms php /opt/librenms/artisan key:generate --force
sudo -u librenms php /opt/librenms/artisan migrate --force
sudo -u librenms php /opt/librenms/artisan config:cache

cp "$SCRIPT_DIR/config/librenms.conf" /etc/apache2/sites-available/librenms.conf
a2ensite librenms.conf
a2enmod rewrite headers
a2dissite 000-default.conf 2>/dev/null || true
systemctl restart apache2

cp "$SCRIPT_DIR/config/librenms-scheduler.service" /etc/systemd/system/
cp "$SCRIPT_DIR/config/librenms-scheduler.timer" /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now librenms-scheduler.timer

echo ""
echo "=== Install complete ==="
echo "Open: $APP_URL"
echo "Create admin user in the web UI."
echo "DB password: $DB_PASS (change in /opt/librenms/.env)"
echo "Add GNS3 router: bash $SCRIPT_DIR/scripts/fix-librenms-graphs.sh"
