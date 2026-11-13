#!/usr/bin/env bash
###############################################################################
# STAGE 04: Branding & Theming
# Runs INSIDE chroot (rootfs is /)
###############################################################################
set -euo pipefail

echo "[STAGE-04] ============================================"
echo "[STAGE-04] Applying Neuxon OS Branding & Monochrome Themes"
echo "[STAGE-04] ============================================"

CONFIG_DIR="/tmp/neuxon-config"

# --------------------------------------------------------------------------
# 1. OS Release & Identification
# --------------------------------------------------------------------------
echo "[STAGE-04] Installing /etc/os-release and identification files..."
if [ -f "${CONFIG_DIR}/branding/os-release" ]; then
    cp "${CONFIG_DIR}/branding/os-release" /etc/os-release
    cp "${CONFIG_DIR}/branding/os-release" /usr/lib/os-release
    echo "[STAGE-04]   Installed /etc/os-release"
fi

if [ -f "${CONFIG_DIR}/branding/issue" ]; then
    cp "${CONFIG_DIR}/branding/issue" /etc/issue
    cp "${CONFIG_DIR}/branding/issue" /etc/issue.net
    echo "[STAGE-04]   Installed /etc/issue and /etc/issue.net"
fi

if [ -f "${CONFIG_DIR}/branding/motd" ]; then
    cp "${CONFIG_DIR}/branding/motd" /etc/motd
    echo "[STAGE-04]   Installed /etc/motd"
fi

# --------------------------------------------------------------------------
# 2. Fastfetch System & User Configuration
# --------------------------------------------------------------------------
echo "[STAGE-04] Installing Fastfetch configuration..."
if [ -f "${CONFIG_DIR}/branding/fastfetch/config.jsonc" ]; then
    mkdir -p /etc/fastfetch
    cp "${CONFIG_DIR}/branding/fastfetch/config.jsonc" /etc/fastfetch/config.jsonc

    mkdir -p /home/neuxon/.config/fastfetch /etc/skel/.config/fastfetch
    cp "${CONFIG_DIR}/branding/fastfetch/config.jsonc" /home/neuxon/.config/fastfetch/config.jsonc
    cp "${CONFIG_DIR}/branding/fastfetch/config.jsonc" /etc/skel/.config/fastfetch/config.jsonc

    echo "[STAGE-04]   Installed fastfetch config"
fi

# --------------------------------------------------------------------------
# 3. Procedural Wallpapers Generation & Installation
# --------------------------------------------------------------------------
echo "[STAGE-04] Processing Neuxon wallpapers..."
mkdir -p /usr/share/backgrounds/neuxon

if [ -d "${CONFIG_DIR}/branding/wallpapers" ]; then
    cp -r "${CONFIG_DIR}/branding/wallpapers"/* /usr/share/backgrounds/neuxon/

    # Convert SVG wallpapers to PNG if rsvg-convert or magick is present
    for svg in /usr/share/backgrounds/neuxon/*.svg; do
        if [ -f "${svg}" ]; then
            png="${svg%.svg}.png"
            if [ ! -f "${png}" ]; then
                if command -v rsvg-convert &>/dev/null; then
                    rsvg-convert -w 1920 -h 1080 "${svg}" -o "${png}" 2>/dev/null || true
                    echo "[STAGE-04]   Converted ${svg} -> ${png} via rsvg-convert"
                elif command -v magick &>/dev/null; then
                    magick "${svg}" "${png}" 2>/dev/null || true
                    echo "[STAGE-04]   Converted ${svg} -> ${png} via ImageMagick"
                fi
            fi
        fi
    done
fi

# Ensure default wallpaper exists
if [ -f /usr/share/backgrounds/neuxon/neuxon-geometric-01.png ]; then
    ln -sfn /usr/share/backgrounds/neuxon/neuxon-geometric-01.png /usr/share/backgrounds/neuxon/default.png
elif [ -f /usr/share/backgrounds/neuxon/neuxon-geometric-01.svg ]; then
    ln -sfn /usr/share/backgrounds/neuxon/neuxon-geometric-01.svg /usr/share/backgrounds/neuxon/default.svg
fi

echo "[STAGE-04] Wallpapers configured in /usr/share/backgrounds/neuxon/"

# --------------------------------------------------------------------------
# 4. Plymouth Monochrome Boot Splash Theme
# --------------------------------------------------------------------------
echo "[STAGE-04] Configuring Plymouth monochrome boot splash theme..."

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y --no-install-recommends plymouth plymouth-themes

PLYMOUTH_DIR="/usr/share/plymouth/themes/neuxon"
mkdir -p "${PLYMOUTH_DIR}"

if [ -d "${CONFIG_DIR}/branding/plymouth/neuxon" ]; then
    cp -r "${CONFIG_DIR}/branding/plymouth/neuxon"/* "${PLYMOUTH_DIR}/"
    echo "[STAGE-04]   Copied Plymouth theme files to ${PLYMOUTH_DIR}"
fi

# Set Neuxon as active plymouth theme
mkdir -p /etc/plymouth
cat > /etc/plymouth/plymouthd.conf << 'EOF'
[Daemon]
Theme=neuxon
ShowDelay=0
DeviceTimeout=8
EOF

if command -v plymouth-set-default-theme &>/dev/null; then
    plymouth-set-default-theme -R neuxon 2>/dev/null || true
fi

# Update initramfs for Plymouth
if command -v update-initramfs &>/dev/null; then
    echo "[STAGE-04] Updating initramfs for Plymouth..."
    update-initramfs -u -k all 2>/dev/null || true
fi

# --------------------------------------------------------------------------
# 5. TUI Applications Monochrome Theming (btop, micro, yazi, mako, etc.)
# --------------------------------------------------------------------------
echo "[STAGE-04] Installing TUI application configurations and themes..."

# btop
if [ -d "${CONFIG_DIR}/desktop/btop" ]; then
    mkdir -p /home/neuxon/.config/btop/themes
    mkdir -p /etc/skel/.config/btop/themes
    mkdir -p /usr/local/share/btop/themes
    mkdir -p /usr/share/btop/themes

    if [ -f "${CONFIG_DIR}/desktop/btop/btop.conf" ]; then
        cp "${CONFIG_DIR}/desktop/btop/btop.conf" /home/neuxon/.config/btop/btop.conf
        cp "${CONFIG_DIR}/desktop/btop/btop.conf" /etc/skel/.config/btop/btop.conf
    fi

    for tfile in "${CONFIG_DIR}/desktop/btop/themes"/*; do
        if [ -f "${tfile}" ]; then
            cp "${tfile}" /home/neuxon/.config/btop/themes/
            cp "${tfile}" /etc/skel/.config/btop/themes/
            cp "${tfile}" /usr/local/share/btop/themes/ 2>/dev/null || true
            cp "${tfile}" /usr/share/btop/themes/ 2>/dev/null || true
        fi
    done
    echo "[STAGE-04]   Installed btop monochrome theme and settings"
fi

# micro
if [ -f "${CONFIG_DIR}/desktop/micro/settings.json" ]; then
    mkdir -p /home/neuxon/.config/micro /etc/skel/.config/micro
    cp "${CONFIG_DIR}/desktop/micro/settings.json" /home/neuxon/.config/micro/settings.json
    cp "${CONFIG_DIR}/desktop/micro/settings.json" /etc/skel/.config/micro/settings.json
    echo "[STAGE-04]   Installed micro editor monochrome settings"
fi

# yazi
if [ -f "${CONFIG_DIR}/desktop/yazi/theme.toml" ]; then
    mkdir -p /home/neuxon/.config/yazi /etc/skel/.config/yazi
    cp "${CONFIG_DIR}/desktop/yazi/theme.toml" /home/neuxon/.config/yazi/theme.toml
    cp "${CONFIG_DIR}/desktop/yazi/theme.toml" /etc/skel/.config/yazi/theme.toml
    echo "[STAGE-04]   Installed yazi monochrome theme"
fi

# mako
if [ -f "${CONFIG_DIR}/desktop/mako/config" ]; then
    mkdir -p /home/neuxon/.config/mako /etc/skel/.config/mako
    cp "${CONFIG_DIR}/desktop/mako/config" /home/neuxon/.config/mako/config
    cp "${CONFIG_DIR}/desktop/mako/config" /etc/skel/.config/mako/config
    echo "[STAGE-04]   Installed mako monochrome configuration"
fi

# labwc themerc-override
if [ -f "${CONFIG_DIR}/desktop/labwc/themerc-override" ]; then
    mkdir -p /home/neuxon/.config/labwc /etc/skel/.config/labwc
    cp "${CONFIG_DIR}/desktop/labwc/themerc-override" /home/neuxon/.config/labwc/themerc-override
    cp "${CONFIG_DIR}/desktop/labwc/themerc-override" /etc/skel/.config/labwc/themerc-override
    echo "[STAGE-04]   Installed labwc themerc-override"
fi

# --------------------------------------------------------------------------
# 6. Finalize ownership & permissions
# --------------------------------------------------------------------------
echo "[STAGE-04] Finalizing ownership and permissions..."
chown -R neuxon:neuxon /home/neuxon
chmod 700 /home/neuxon

apt-get clean
rm -rf /var/lib/apt/lists/*

echo "[STAGE-04] ============================================"
echo "[STAGE-04] Branding stage completed successfully"
echo "[STAGE-04] ============================================"
