#!/bin/bash
# Fix LibreNMS graphs for GNS3 R1 (192.168.67.1)
# Run on Ubuntu LibreNMS server as aiman (sudo where needed)
set -euo pipefail

R1=192.168.67.1
COMM=public
LIBRENMS=/opt/librenms

echo "=== LibreNMS graph fix for $R1 ==="

# 1) Fix ARP to router MAC
IFACE=$(ip -4 route get "$R1" 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}')
IFACE="${IFACE:-eth0}"
echo "Using interface: $IFACE"
sudo ip neigh replace "$R1" lladdr c2:01:0b:71:00:00 dev "$IFACE" nud permanent
ip neigh show "$R1"

# 2) Verify SNMP
echo "--- SNMP test ---"
if ! snmpget -v2c -c "$COMM" "$R1" .1.3.6.1.2.1.1.1.0 -t 3; then
  echo "ERROR: SNMP failed. Fix connectivity first."
  exit 1
fi

# 3) Ensure poller cron / scheduler
if [ ! -f /etc/cron.d/librenms ] && [ -f "$LIBRENMS/dist/librenms.cron" ]; then
  echo "Installing LibreNMS cron..."
  sudo cp "$LIBRENMS/dist/librenms.cron" /etc/cron.d/librenms
fi
sudo systemctl enable librenms-scheduler.timer 2>/dev/null || true
sudo systemctl start librenms-scheduler.timer 2>/dev/null || true

# 4) Fix RRD permissions
sudo chown -R librenms:librenms "$LIBRENMS/rrd" "$LIBRENMS/logs" 2>/dev/null || true
sudo chmod -R 775 "$LIBRENMS/rrd" 2>/dev/null || true

cd "$LIBRENMS"

# 5) Check if device exists in DB
DEVICE_ID=$(sudo -u librenms ./lnms device:list 2>/dev/null | grep -F "$R1" | awk '{print $1}' | head -1 || true)

if [ -z "$DEVICE_ID" ]; then
  echo "Adding device $R1 to LibreNMS..."
  sudo -u librenms ./lnms device:add "$R1" --v2c --community "$COMM" --force 2>&1 || \
  sudo -u librenms ./lnms device:add "$R1" --version v2c --community "$COMM" --force 2>&1 || \
  sudo -u librenms php artisan device:add "$R1" --v2c --community "$COMM" --force 2>&1
  DEVICE_ID=$(sudo -u librenms ./lnms device:list 2>/dev/null | grep -F "$R1" | awk '{print $1}' | head -1)
else
  echo "Device exists: ID=$DEVICE_ID — updating SNMP..."
  sudo -u librenms ./lnms device:update "$R1" --v2c --community "$COMM" 2>/dev/null || true
fi

if [ -z "$DEVICE_ID" ]; then
  echo "WARN: device not in list; trying poll by hostname anyway..."
fi

# 6) Force discover + poll
echo "--- Discovery ---"
sudo -u librenms ./lnms device:discover "$R1" -v 2>&1 | tail -15

echo "--- Poll ---"
sudo -u librenms ./lnms device:poll "$R1" -v 2>&1 | tail -20

# 7) Show RRD files
echo "--- RRD files ---"
ls -la "$LIBRENMS/rrd/$R1/" 2>/dev/null | head -15 || echo "No RRD dir yet - check validate.php"

# 8) Device status
echo "--- Device status ---"
sudo -u librenms ./lnms device:list 2>/dev/null | grep -F "$R1" || true

echo ""
echo "=== Done. Refresh LibreNMS UI -> Devices -> $R1 -> Graphs / Ports ==="
