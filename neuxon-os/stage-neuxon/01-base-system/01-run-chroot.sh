#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# STAGE 01: Base System Configuration
# Runs INSIDE chroot (rootfs is /)
# ============================================================================

echo "[STAGE-01] ============================================"
echo "[STAGE-01] Configuring base system"
echo "[STAGE-01] ============================================"

# --------------------------------------------------------------------------
# Hostname
# --------------------------------------------------------------------------
echo "[STAGE-01] Setting hostname to 'neuxon' ..."
echo "neuxon" > /etc/hostname
cat > /etc/hosts << 'EOF'
127.0.0.1	localhost
127.0.1.1	neuxon

# IPv6
::1		localhost ip6-localhost ip6-loopback
ff02::1		ip6-allnodes
ff02::2		ip6-allrouters
EOF
echo "[STAGE-01] Hostname configured"

# --------------------------------------------------------------------------
# Locale
# --------------------------------------------------------------------------
echo "[STAGE-01] Configuring locale (en_US.UTF-8) ..."
if [ -f /etc/locale.gen ]; then
    sed -i 's/^# *en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
else
    echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
fi

apt-get update -qq
apt-get install -y --no-install-recommends locales
locale-gen en_US.UTF-8

cat > /etc/default/locale << 'EOF'
LANG=en_US.UTF-8
LC_ALL=en_US.UTF-8
EOF

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
echo "[STAGE-01] Locale configured"

# --------------------------------------------------------------------------
# Timezone
# --------------------------------------------------------------------------
echo "[STAGE-01] Setting timezone to UTC ..."
ln -sf /usr/share/zoneinfo/UTC /etc/localtime
echo "UTC" > /etc/timezone
if command -v dpkg-reconfigure &>/dev/null; then
    dpkg-reconfigure -f noninteractive tzdata 2>/dev/null || true
fi
echo "[STAGE-01] Timezone set to UTC"

# --------------------------------------------------------------------------
# Raspberry Pi APT Repository
# --------------------------------------------------------------------------
echo "[STAGE-01] Adding Raspberry Pi apt repository ..."

# Download and install the raspberrypi-archive-keyring
KEYRING_URL="https://archive.raspberrypi.com/debian/pool/main/r/raspberrypi-archive-keyring/raspberrypi-archive-keyring_2021.1.1+rpt1_all.deb"
KEYRING_DEB="/tmp/raspberrypi-archive-keyring.deb"

echo "[STAGE-01] Downloading raspberrypi-archive-keyring ..."
wget -q -O "${KEYRING_DEB}" "${KEYRING_URL}"
dpkg -i "${KEYRING_DEB}"
rm -f "${KEYRING_DEB}"

# Create raspi.list source
cat > /etc/apt/sources.list.d/raspi.list << 'EOF'
deb http://archive.raspberrypi.com/debian/ bookworm main
EOF

echo "[STAGE-01] Raspberry Pi repository added"

# --------------------------------------------------------------------------
# Update package lists
# --------------------------------------------------------------------------
echo "[STAGE-01] Running apt-get update ..."
apt-get update -y

# --------------------------------------------------------------------------
# Install essential packages
# --------------------------------------------------------------------------
echo "[STAGE-01] Installing essential packages ..."

export DEBIAN_FRONTEND=noninteractive

apt-get install -y --no-install-recommends \
    linux-image-rpi-v8 \
    raspi-firmware \
    firmware-brcm80211 \
    systemd \
    systemd-sysv \
    dbus \
    udev \
    kmod \
    sudo \
    openssh-server \
    locales \
    console-setup \
    iproute2 \
    iputils-ping \
    wpasupplicant \
    rfkill \
    network-manager \
    fdisk \
    dosfstools \
    e2fsprogs \
    initramfs-tools \
    apt-utils \
    bash-completion \
    htop \
    nano \
    less \
    man-db \
    bzip2 \
    xz-utils \
    zstd \
    psmisc \
    lsof \
    procps

echo "[STAGE-01] Essential packages installed"

# Lock core raspberry pi kernel and firmware packages
echo "[STAGE-01] Locking core raspberry pi kernel and firmware packages ..."
apt-mark hold linux-image-rpi-v8 raspi-firmware firmware-brcm80211
echo "[STAGE-01] Core packages locked"

# --------------------------------------------------------------------------
# ZRAM setup
# --------------------------------------------------------------------------
echo "[STAGE-01] Configuring ZRAM ..."

# Copy ZRAM setup script
if [ -f /tmp/neuxon-config/system/zram-setup.sh ]; then
    cp /tmp/neuxon-config/system/zram-setup.sh /usr/local/sbin/zram-setup.sh
    chmod +x /usr/local/sbin/zram-setup.sh
    echo "[STAGE-01] Installed zram-setup.sh to /usr/local/sbin/"
else
    echo "[STAGE-01] WARNING: /tmp/neuxon-config/system/zram-setup.sh not found"
fi

# Copy ZRAM systemd service
if [ -f /tmp/neuxon-config/system/neuxon-zram.service ]; then
    cp /tmp/neuxon-config/system/neuxon-zram.service /etc/systemd/system/neuxon-zram.service
    echo "[STAGE-01] Installed neuxon-zram.service"
else
    echo "[STAGE-01] WARNING: /tmp/neuxon-config/system/neuxon-zram.service not found"
fi

echo "[STAGE-01] ZRAM configured"

# --------------------------------------------------------------------------
# System configuration files
# --------------------------------------------------------------------------
echo "[STAGE-01] Copying system configuration files ..."

# Sysctl configuration
if [ -f /tmp/neuxon-config/system/sysctl-neuxon.conf ]; then
    cp /tmp/neuxon-config/system/sysctl-neuxon.conf /etc/sysctl.d/99-neuxon.conf
    echo "[STAGE-01] Installed sysctl config to /etc/sysctl.d/99-neuxon.conf"
else
    echo "[STAGE-01] WARNING: /tmp/neuxon-config/system/sysctl-neuxon.conf not found"
fi

# Boot configuration & /boot vs /boot/firmware compatibility
mkdir -p /boot/firmware
if [ ! -e /boot/rpi-firmware ]; then
    ln -sfn /boot/firmware /boot/rpi-firmware 2>/dev/null || true
fi

if [ -f /tmp/neuxon-config/boot/config.txt ]; then
    cp /tmp/neuxon-config/boot/config.txt /boot/firmware/config.txt
    echo "[STAGE-01] Installed /boot/firmware/config.txt"
else
    echo "[STAGE-01] WARNING: /tmp/neuxon-config/boot/config.txt not found"
fi

if [ -f /tmp/neuxon-config/boot/cmdline.txt ]; then
    cp /tmp/neuxon-config/boot/cmdline.txt /boot/firmware/cmdline.txt
    echo "[STAGE-01] Installed /boot/firmware/cmdline.txt"
else
    echo "[STAGE-01] WARNING: /tmp/neuxon-config/boot/cmdline.txt not found"
fi

echo "[STAGE-01] System configuration files installed"

# --------------------------------------------------------------------------
# /etc/fstab
# --------------------------------------------------------------------------
echo "[STAGE-01] Generating /etc/fstab ..."

cat > /etc/fstab << 'EOF'
# <file system>       <mount point>   <type>  <options>                             <dump>  <pass>
PARTUUID=2ba4ee16-02  /               ext4    defaults,noatime,commit=60            0       1
PARTUUID=2ba4ee16-01  /boot/firmware  vfat    defaults,flush                        0       2
tmpfs                 /tmp            tmpfs   defaults,nosuid,nodev,size=128M       0       0
tmpfs                 /var/log        tmpfs   defaults,nosuid,nodev,noexec,size=32M 0       0
tmpfs                 /var/tmp        tmpfs   defaults,nosuid,nodev,size=64M        0       0
EOF

echo "[STAGE-01] /etc/fstab generated"

# --------------------------------------------------------------------------
# Enable required systemd services
# --------------------------------------------------------------------------
echo "[STAGE-01] Enabling systemd services ..."

systemctl enable NetworkManager.service 2>/dev/null || true
systemctl enable ssh.service 2>/dev/null || true
systemctl enable neuxon-zram.service 2>/dev/null || true

# Enable CPU performance governor service
if [ -f /tmp/neuxon-config/system/neuxon-performance.service ]; then
    cp /tmp/neuxon-config/system/neuxon-performance.service /etc/systemd/system/neuxon-performance.service
    systemctl enable neuxon-performance.service 2>/dev/null || true
    echo "[STAGE-01] Enabled neuxon-performance.service"
fi

echo "[STAGE-01] Required services enabled"

# --------------------------------------------------------------------------
# Disable and mask unnecessary services
# --------------------------------------------------------------------------
echo "[STAGE-01] Disabling unnecessary services ..."

SERVICES_TO_DISABLE=(
    bluetooth.service
    ModemManager.service
    avahi-daemon.service
    triggerhappy.service
    cups.service
    cups-browsed.service
    apt-daily.service
    apt-daily-upgrade.service
    apt-daily.timer
    apt-daily-upgrade.timer
    man-db.timer
    e2scrub_all.timer
    e2scrub_reap.service
)

for svc in "${SERVICES_TO_DISABLE[@]}"; do
    systemctl disable "${svc}" 2>/dev/null || true
    echo "[STAGE-01]   Disabled: ${svc}"
done

SERVICES_TO_MASK=(
    ModemManager.service
    avahi-daemon.service
    triggerhappy.service
    cups.service
    cups-browsed.service
    apt-daily.service
    apt-daily-upgrade.service
    apt-daily.timer
    apt-daily-upgrade.timer
    man-db.timer
    e2scrub_all.timer
    e2scrub_reap.service
)

for svc in "${SERVICES_TO_MASK[@]}"; do
    systemctl mask "${svc}" 2>/dev/null || true
    echo "[STAGE-01]   Masked: ${svc}"
done

echo "[STAGE-01] Unnecessary services disabled and masked"

# --------------------------------------------------------------------------
# Configure journald
# --------------------------------------------------------------------------
echo "[STAGE-01] Configuring journald (volatile, 16M max) ..."

mkdir -p /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/neuxon.conf << 'EOF'
[Journal]
Storage=volatile
SystemMaxUse=16M
RuntimeMaxUse=16M
EOF

echo "[STAGE-01] Journald configured"

# --------------------------------------------------------------------------
# Kernel modules
# --------------------------------------------------------------------------
echo "[STAGE-01] Setting up kernel module loading ..."

mkdir -p /etc/modules-load.d

cat > /etc/modules-load.d/neuxon.conf << 'EOF'
# BCM2837B0 VideoCore IV GPU
vc4
# V3D driver
v3d
# I2C bus
i2c-dev
# SPI bus
spi-bcm2835
# Sound
snd-bcm2835
EOF

echo "[STAGE-01] Kernel modules configured"

# --------------------------------------------------------------------------
# Clean up
# --------------------------------------------------------------------------
echo "[STAGE-01] Cleaning apt cache ..."
apt-get clean
rm -rf /var/lib/apt/lists/*

echo "[STAGE-01] ============================================"
echo "[STAGE-01] Base system configuration completed"
echo "[STAGE-01] ============================================"
