#!/usr/bin/env bash
###############################################################################
# neuxon-expand-root.sh — Expand root partition to 100% of SD card on first boot
###############################################################################
set -euo pipefail

ROOT_DEV="$(findmnt -n -o SOURCE / || true)"
if [[ -z "${ROOT_DEV}" ]]; then
    exit 0
fi

if [[ "${ROOT_DEV}" =~ ^/dev/(mmcblk[0-9]+)p([0-9]+)$ ]]; then
    DISK_DEV="/dev/${BASH_REMATCH[1]}"
    PART_NUM="${BASH_REMATCH[2]}"
elif [[ "${ROOT_DEV}" =~ ^/dev/([a-z]+)([0-9]+)$ ]]; then
    DISK_DEV="/dev/${BASH_REMATCH[1]}"
    PART_NUM="${BASH_REMATCH[2]}"
else
    DISK_DEV=""
    PART_NUM=""
fi

if [[ -n "${DISK_DEV}" ]] && [[ -b "${DISK_DEV}" ]] && [[ -n "${PART_NUM}" ]]; then
    echo "[NEUXON-INIT] Expanding root partition on ${DISK_DEV} (part ${PART_NUM})..."
    parted -s "${DISK_DEV}" resizepart "${PART_NUM}" 100% 2>/dev/null || true
    partprobe "${DISK_DEV}" 2>/dev/null || true
    resize2fs "${ROOT_DEV}" 2>/dev/null || true
    echo "[NEUXON-INIT] Root filesystem expanded to fill SD card."
fi

systemctl disable neuxon-expand-root.service 2>/dev/null || true
