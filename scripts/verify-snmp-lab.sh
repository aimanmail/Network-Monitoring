#!/bin/bash
# Verify SNMP lab — uses YOUR server/router IPs from lab.env
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ -f "$REPO_DIR/config/lab.env" ]; then
  # shellcheck source=/dev/null
  source "$REPO_DIR/config/lab.env"
fi

ROUTER_IP="${ROUTER_IP:-192.168.67.1}"
ROUTER_MAC="${ROUTER_MAC:-c2:01:0b:71:00:00}"
SNMP_COMM="${SNMP_COMMUNITY:-public}"

SERVER_IP="$(hostname -I | awk '{print $1}')"
IFACE="${LAB_IFACE:-$(ip -4 route get "$ROUTER_IP" 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}')}"
IFACE="${IFACE:-eth0}"

echo "=== SNMP lab verification ==="
echo "This server IP:  $SERVER_IP"
echo "Router IP:     $ROUTER_IP"
echo "Interface:     $IFACE"
echo ""

echo "--- ARP (expect $ROUTER_MAC) ---"
ip neigh show "$ROUTER_IP" || true

echo "--- Ping router ---"
ping -c 3 -W 2 "$ROUTER_IP"

echo "--- Nmap UDP 161 ---"
sudo nmap -sU -p 161 "$ROUTER_IP" 2>&1 | grep -E '161|open|Host' || true

echo "--- SNMP walk ---"
snmpwalk -v2c -c "$SNMP_COMM" "$ROUTER_IP" .1.3.6.1.2.1.1 2>&1 | head -8

echo "=== Verification complete ==="
