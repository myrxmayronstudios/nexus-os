#!/usr/bin/env bash
###############################################################################
# scripts/setup-host-deps.sh — Install host dependencies for Neuxon OS build
###############################################################################
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
    echo "[ERROR] This script must be run as root (or via sudo)." >&2
    exit 1
fi

echo "=== Installing Neuxon OS Host Build Dependencies ==="

apt-get update -qq

DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    debootstrap \
    qemu-user-static \
    binfmt-support \
    xz-utils \
    dosfstools \
    e2fsprogs \
    parted \
    kpartx \
    xorriso \
    mtools \
    git \
    curl \
    wget \
    ca-certificates \
    rsync \
    fdisk \
    jq \
    systemd-container

# Ensure ARM64 binfmt registration is active
if command -v update-binfmts &>/dev/null; then
    update-binfmts --enable qemu-aarch64 2>/dev/null || true
fi

echo "=== Host build dependencies successfully installed ==="
