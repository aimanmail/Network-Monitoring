# Network Monitoring Lab — LibreNMS + GNS3 SNMP

Repo: [github.com/aimanmail/Network-Monitoring](https://github.com/aimanmail/Network-Monitoring)

Install the same **LibreNMS + GNS3 SNMP lab** on **Ubuntu 22.04, 24.04, or 24.10+** — IPs are **auto-detected** or set in `config/lab.env` (not hardcoded to one lab). PHP packages use Ubuntu’s default `php` metapackages (no version-specific `php8.x` names).

> LibreNMS app is pulled from the official repo: [librenms/librenms](https://github.com/librenms/librenms.git)

---

## IP addressing — each user sets their own

| Setting | Where | Default / auto |
|---------|--------|----------------|
| **LibreNMS server IP** | Auto on install | Detected from this machine (`hostname -I` / default route) |
| **APP_URL** | Auto on install | `http://<detected-server-ip>` |
| **GNS3 router IP** | `config/lab.env` | `ROUTER_IP=192.168.67.1` (edit for your lab) |
| **Router MAC** | `config/lab.env` | `ROUTER_MAC=c2:01:0b:71:00:00` (from `show int f0/0` on R1) |
| **SNMP community** | `config/lab.env` | `SNMP_COMMUNITY=public` |

**Example — Friend A (different subnet):**
```bash
# config/lab.env
ROUTER_IP=10.10.10.1
ROUTER_MAC=c2:01:0b:71:00:00
SNMP_COMMUNITY=public
```

**Example — Friend B (same subnet as lab doc):**
```bash
ROUTER_IP=192.168.67.1
ROUTER_MAC=c2:01:0b:71:00:00
```

LibreNMS **never** uses the installer's IP — only **the IP of the machine where you run install**.

---

## Quick install

```bash
git clone https://github.com/aimanmail/Network-Monitoring.git
cd Network-Monitoring
chmod +x install-librenms-ubuntu.sh scripts/*.sh

# Installs LibreNMS using THIS server's IP automatically
sudo ./install-librenms-ubuntu.sh

# Optional: force a specific URL if auto-detect is wrong
# sudo LIBRENMS_APP_URL=http://10.0.0.50 ./install-librenms-ubuntu.sh
```

1. Open the printed URL in a browser → you are redirected to the **official LibreNMS setup wizard** (`/install`)  
   - Pre-install checks → database → admin user → finish  
   - Use the database credentials printed by the installer (empty `librenms` database)  
   - Direct link if needed: `http://<server-ip>/install`
2. Edit **`config/lab.env`** with **your** router IP and MAC  
3. After GNS3 R1 is running with SNMP:

```bash
bash scripts/fix-librenms-graphs.sh
```

Verify:

```bash
bash scripts/verify-snmp-lab.sh
```

---

## Configure your lab (`config/lab.env`)

```bash
cp config/lab.env.example config/lab.env
nano config/lab.env
```

```bash
ROUTER_IP=YOUR_ROUTER_IP          # e.g. 192.168.67.1
ROUTER_MAC=YOUR_ROUTER_MAC        # e.g. c2:01:0b:71:00:00
SNMP_COMMUNITY=public
# LAB_IFACE=ens33                 # optional, auto-detected if omitted
```

Get router MAC on R1 console:
```text
show interfaces FastEthernet0/0
```

---

## Reference topology (example lab — change IPs as needed)

```
Ubuntu LibreNMS   <YOUR_SERVER_IP>     (auto-detected on install)
GNS3 Router R1    <ROUTER_IP>          (set in lab.env)
Topology:         Cloud1(eth0) → R1 FastEthernet0/0 direct
```

**Rules:**
- Do **not** use the router IP on Windows/VMware (avoid `.1` conflict if router is `.1`)
- Use GNS3 **Cloud → Router** direct (not Ethernet Switch for SNMP path)
- Keep R1 **running** in GNS3

---

## Router SNMP config (GNS3 R1)

```
snmp-server view ALL iso included
snmp-server community public view ALL RO
snmp-server contact "Your Name - Network Admin"
snmp-server location Your City
snmp-server ifindex persist
```

---

## Files in this repo

| File | Purpose |
|------|---------|
| `install-librenms-ubuntu.sh` | Install LibreNMS stack; leaves web setup wizard for you |
| `config/lab.env.example` | **Your** router IP/MAC template |
| `config/env.example` | LibreNMS `.env` template |
| `config/librenms.conf` | Apache vhost |
| `config/librenms-scheduler.*` | Poller timer |
| `scripts/fix-librenms-graphs.sh` | Add/poll router from `lab.env` |
| `scripts/verify-snmp-lab.sh` | Test SNMP from `lab.env` |
| `scripts/test-wizard-flow.sh` | Validate web setup wizard is reachable (on server) |

---

## Environment variables (optional)

| Variable | Purpose |
|----------|---------|
| `LIBRENMS_APP_URL` | Override auto-detected LibreNMS URL |
| `LIBRENMS_DB_PASS` | MariaDB password (default: `librenms`) |
| `ROUTER_IP` / `ROUTER_MAC` | In `config/lab.env` — GNS3 router target |

---

## Troubleshooting

1. **Wrong LibreNMS URL** → re-run with `sudo LIBRENMS_APP_URL=http://YOUR_IP ./install-librenms-ubuntu.sh` or edit `/opt/librenms/.env`
2. **SNMP timeout** → check `config/lab.env`, ARP (`ip neigh show ROUTER_IP`), R1 running
3. **No graphs** → run `bash scripts/fix-librenms-graphs.sh`, check `/opt/librenms/rrd/<ROUTER_IP>/`

---

## Do not commit secrets

- `config/lab.env` (local IPs — use `.example` only in git)
- `/opt/librenms/.env` with real passwords
- `APP_KEY`, database dumps
