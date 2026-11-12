#!/usr/bin/env bash
set -euo pipefail

# Neuxon OS - Disable and Mask Unnecessary Services
# Reduces memory usage and speeds up boot time

echo "=== Neuxon OS Service Optimizer ==="

# Services to disable (if they exist)
DISABLE_SERVICES=(
    bluetooth.service
    hciuart.service
    ModemManager.service
    avahi-daemon.service
    avahi-daemon.socket
    triggerhappy.service
    triggerhappy.socket
    cups.service
    cups-browsed.service
    apt-daily.service
    apt-daily.timer
    apt-daily-upgrade.service
    apt-daily-upgrade.timer
    man-db.timer
    e2scrub_all.timer
    e2scrub_reap.service
    fstrim.timer
    motd-news.timer
    phpsessionclean.timer
    remote-fs.target
    systemd-timesyncd.service
)

# Services to mask completely
MASK_SERVICES=(
    ModemManager.service
    avahi-daemon.service
    cups.service
    cups-browsed.service
    triggerhappy.service
)

for svc in "${DISABLE_SERVICES[@]}"; do
    if systemctl list-unit-files "${svc}" &>/dev/null; then
        echo "[DISABLE] ${svc}"
        systemctl disable "${svc}" 2>/dev/null || true
    fi
done

for svc in "${MASK_SERVICES[@]}"; do
    echo "[MASK] ${svc}"
    systemctl mask "${svc}" 2>/dev/null || true
done

# Configure journald for minimal logging
mkdir -p /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/neuxon.conf << 'JOURNALEOF'
[Journal]
Storage=volatile
SystemMaxUse=16M
RuntimeMaxUse=16M
MaxLevelStore=warning
MaxLevelSyslog=warning
MaxLevelKMsg=warning
MaxLevelConsole=warning
Compress=yes
JOURNALEOF

echo "[DONE] Services optimized for Neuxon OS"
