#!/bin/bash
# Fix LibreNMS graphs for GNS3 router — uses YOUR lab IPs from lab.env
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Load user lab settings (copy config/lab.env.example -> config/lab.env)
if [ -f "$REPO_DIR/config/lab.env" ]; then
  # shellcheck source=/dev/null
  source "$REPO_DIR/config/lab.env"
elif [ -f "$REPO_DIR/lab.env" ]; then
  # shellcheck source=/dev/null
  source "$REPO_DIR/lab.env"
fi

ROUTER_IP="${ROUTER_IP:-${GNS3_ROUTER_IP:-192.168.67.1}}"
ROUTER_MAC="${ROUTER_MAC:-${GNS3_ROUTER_MAC:-c2:01:0b:71:00:00}}"
SNMP_COMM="${SNMP_COMMUNITY:-public}"
LIBRENMS="${LIBRENMS_PATH:-/opt/librenms}"

echo "=== LibreNMS graph fix for router $ROUTER_IP ==="
echo "Server IP(s): $(hostname -I 2>/dev/null || true)"

IFACE="${LAB_IFACE:-$(ip -4 route get "$ROUTER_IP" 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}')}"
IFACE="${IFACE:-eth0}"
echo "Using interface: $IFACE"

sudo ip neigh replace "$ROUTER_IP" lladdr "$ROUTER_MAC" dev "$IFACE" nud permanent
ip neigh show "$ROUTER_IP"

echo "--- SNMP test ---"
if ! snmpget -v2c -c "$SNMP_COMM" "$ROUTER_IP" .1.3.6.1.2.1.1.1.0 -t 5; then
  echo "ERROR: SNMP failed to $ROUTER_IP. Check ROUTER_IP, ROUTER_MAC, and GNS3 topology."
  exit 1
fi

if [ ! -f /etc/cron.d/librenms ] && [ -f "$LIBRENMS/dist/librenms.cron" ]; then
  sudo cp "$LIBRENMS/dist/librenms.cron" /etc/cron.d/librenms
fi
sudo systemctl enable librenms-scheduler.timer 2>/dev/null || true
sudo systemctl start librenms-scheduler.timer 2>/dev/null || true

sudo chown -R librenms:librenms "$LIBRENMS/rrd" "$LIBRENMS/logs" 2>/dev/null || true
sudo chmod -R 775 "$LIBRENMS/rrd" 2>/dev/null || true

cd "$LIBRENMS"

echo "Adding/updating device $ROUTER_IP..."
sudo -u librenms ./lnms device:add "$ROUTER_IP" --v2c --community "$SNMP_COMM" --force 2>&1 || \
sudo -u librenms ./lnms device:add "$ROUTER_IP" --version v2c --community "$SNMP_COMM" --force 2>&1 || true

echo "--- Discovery ---"
sudo -u librenms ./lnms device:discover "$ROUTER_IP" 2>&1 | tail -12

echo "--- Poll ---"
sudo -u librenms ./lnms device:poll "$ROUTER_IP" 2>&1 | tail -15

echo "--- RRD files ---"
ls -la "$LIBRENMS/rrd/$ROUTER_IP/" 2>/dev/null | head -12 || echo "No RRD dir yet"

echo ""
echo "=== Done. Open LibreNMS -> Devices -> $ROUTER_IP -> Graphs ==="
