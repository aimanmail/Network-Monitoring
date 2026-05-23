# Network Monitoring Lab — LibreNMS + GNS3 SNMP

Repo: [github.com/aimanmail/Network-Monitoring](https://github.com/aimanmail/Network-Monitoring)

Share this with friends to install the **same LibreNMS stack** used in Lab 3.

> **Important:** This repo does **not** include LibreNMS source code.  
> The install script pulls the official app from [librenms/librenms](https://github.com/librenms/librenms.git).

---

## Can my friend just run this and everything works?

**No — not with zero setup.** But they can avoid manual LibreNMS installation.

| Automated by this repo | Friend still must do |
|------------------------|----------------------|
| Install Apache, PHP, MariaDB, SNMP tools | Have **Ubuntu 24.04** server |
| Clone & configure LibreNMS | Set server IP (e.g. `192.168.67.2`) |
| Apache vhost + poller timer | Run **one install command** (below) |
| Scripts to add/poll GNS3 router | Set up **GNS3 lab** (R1 + SNMP) |
| | Create **admin login** in web UI (first visit) |
| | Fix **network/ARP** if same IP conflict issues |

**Minimum friend workflow (~15–30 min):**

```bash
# 1) On fresh Ubuntu 24.04
git clone https://github.com/aimanmail/Network-Monitoring.git
cd Network-Monitoring
sudo LIBRENMS_APP_URL=http://THEIR_SERVER_IP ./install-librenms-ubuntu.sh

# 2) Open browser → create admin user
# 3) After GNS3 R1 is running with SNMP:
bash scripts/fix-librenms-graphs.sh
```

LibreNMS web UI will be up after step 1. **Graphs appear** after step 3 (GNS3 + SNMP + poll).

---

## Your current server (`aiman@192.168.67.2`)

| Item | Value |
|------|--------|
| OS | Ubuntu 24.04.4 LTS (noble) |
| Hostname | `server` |
| LibreNMS IP | `192.168.67.2/24` (interface `ens33`) |
| LibreNMS version | **26.5.1** (git clone at `/opt/librenms`) |
| Web server | **Apache 2** + **PHP 8.3** |
| Database | **MariaDB** (`librenms` / user `librenms`) |
| Poller | **systemd timer** `librenms-scheduler.timer` (every minute) |
| Admin user | `admin` / `admin@lab.local` |
| Monitored device | GNS3 R1 `192.168.67.1` SNMP v2c `public` |

---

## Network layout (Lab 3)

```
Ubuntu LibreNMS  192.168.67.2  (ens33)
GNS3 Router R1   192.168.67.1  (Fa0/0)
GNS3 VM host     192.168.67.128
Windows/VMware   NOT .1 (avoid IP conflict)
Topology: Cloud1(eth0) → R1 FastEthernet0/0 direct
```

---

## Quick install (Ubuntu 24.04)

Run on a fresh Ubuntu server:

```bash
git clone https://github.com/aimanmail/Network-Monitoring.git
cd Network-Monitoring
chmod +x install-librenms-ubuntu.sh scripts/*.sh
sudo ./install-librenms-ubuntu.sh
```

Then configure GNS3 R1 SNMP and add device in LibreNMS UI.

---

## Manual install (matches your server)

### 1. Packages

```bash
sudo apt update
sudo apt install -y apache2 mariadb-server libapache2-mod-php8.3 \
  php8.3-cli php8.3-mysql php8.3-gd php8.3-snmp php8.3-mbstring \
  php8.3-xml php8.3-curl php8.3-zip php8.3-bcmath php8.3-intl \
  composer git snmp snmp-mibs-downloader rrdtool nmap acl curl
```

### 2. Clone LibreNMS (official GitHub)

```bash
sudo mkdir -p /opt/librenms
sudo git clone https://github.com/librenms/librenms.git /opt/librenms
sudo chown -R librenms:librenms /opt/librenms
sudo usermod -a -G librenms www-data
sudo setfacl -d -m g::rwx /opt/librenms/rrd /opt/librenms/logs /opt/librenms/bootstrap/cache/ /opt/librenms/storage/
sudo setfacl -R -m g::rwx /opt/librenms/rrd /opt/librenms/logs /opt/librenms/bootstrap/cache/ /opt/librenms/storage/
```

### 3. Create `librenms` user & MariaDB

```bash
sudo useradd librenms -d /opt/librenms -M -r -s /bin/bash
sudo mysql <<'SQL'
CREATE DATABASE librenms CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'librenms'@'localhost' IDENTIFIED BY 'CHANGE_ME_STRONG_PASSWORD';
GRANT ALL PRIVILEGES ON librenms.* TO 'librenms'@'localhost';
FLUSH PRIVILEGES;
SQL
```

### 4. LibreNMS `.env`

```bash
sudo cp /opt/librenms/.env.example /opt/librenms/.env
sudo -u librenms nano /opt/librenms/.env
# Set: DB_DATABASE, DB_USERNAME, DB_PASSWORD, APP_URL=http://YOUR_SERVER_IP
sudo -u librenms /opt/librenms/lnms key:generate
```

### 5. Install PHP dependencies & DB schema

```bash
cd /opt/librenms
sudo -u librenms composer install --no-dev
sudo -u librenms php artisan migrate --force
sudo -u librenms php artisan config:cache
```

### 6. Apache vhost

Copy `config/librenms.conf` to `/etc/apache2/sites-available/librenms.conf`:

```bash
sudo cp config/librenms.conf /etc/apache2/sites-available/librenms.conf
sudo a2ensite librenms.conf
sudo a2enmod rewrite headers
sudo a2dissite 000-default.conf
sudo systemctl restart apache2
```

### 7. Scheduler (systemd timer — same as your server)

```bash
sudo cp config/librenms-scheduler.service /etc/systemd/system/
sudo cp config/librenms-scheduler.timer /etc/systemd/system/
sudo systemctl enable --now librenms-scheduler.timer
```

### 8. First login

Open `http://YOUR_SERVER_IP/` → create admin account.

### 9. Add GNS3 router

On Ubuntu (before LibreNMS poll):

```bash
# Fix ARP if needed (router MAC)
sudo ip neigh replace 192.168.67.1 lladdr c2:01:0b:71:00:00 dev ens33 nud permanent
snmpwalk -v2c -c public 192.168.67.1 system
```

In LibreNMS UI or CLI:

```bash
cd /opt/librenms
sudo -u librenms ./lnms device:add 192.168.67.1 --v2c --community public --force
sudo -u librenms ./lnms device:discover 192.168.67.1
sudo -u librenms ./lnms device:poll 192.168.67.1
```

Or run: `bash scripts/fix-librenms-graphs.sh`

---

## Router SNMP config (GNS3 R1)

```
snmp-server view ALL iso included
snmp-server community public view ALL RO
snmp-server contact "Ahmad Aiman - Network Admin"
snmp-server location Kuala Lumpur
snmp-server ifindex persist
```

---

## Files in this repo

| File | Purpose |
|------|---------|
| `install-librenms-ubuntu.sh` | Automated install script |
| `config/librenms.conf` | Apache virtual host |
| `config/librenms-scheduler.*` | Systemd poller timer |
| `config/env.example` | `.env` template (no secrets) |
| `scripts/fix-librenms-graphs.sh` | Fix ARP + discover + poll R1 |
| `scripts/verify-snmp-lab.sh` | Verification checklist |
| `docs/GNS3-LAB3-WORKFLOW.md` | GNS3 topology & troubleshooting |

---

## Push to GitHub (for your friend)

```bash
cd librenms-lab-setup
git init
git add .
git commit -m "LibreNMS + GNS3 Lab 3 setup for Ubuntu 24.04"
git remote add origin https://github.com/aimanmail/Network-Monitoring.git
git push -u origin main
```

**Do NOT commit:** `.env` with real passwords, `APP_KEY`, database dumps, or `/opt/librenms/` itself.

---

## Known issues (from your lab)

1. **IP conflict:** Do not use `192.168.67.1` on Windows/VMware — that's R1.
2. **ARP:** Ubuntu must resolve `.1` to MAC `c2:01:0b:71:00:00`.
3. **GNS3:** Use Cloud → R1 direct; keep R1 running; `auto_close: false`.
4. **Graphs:** Ping alone is not enough — run discover + poll; check `/opt/librenms/rrd/192.168.67.1/`.
