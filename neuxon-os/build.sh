#!/usr/bin/env bash
###############################################################################
# build.sh — Neuxon OS Main Build Orchestrator
###############################################################################
# Assembles a complete Neuxon OS image for the Raspberry Pi 3B+ (BCM2837B0,
# aarch64) from Debian Bookworm arm64 packages.
#
# Requirements:
#   - Must be run as root on a Debian/Ubuntu x86_64 host (or inside Docker)
#   - QEMU user-static + binfmt-support for arm64 emulation
#
# Usage:
#   sudo ./build.sh
###############################################################################
set -euo pipefail

# ---------------------------------------------------------------------------
# Project paths
# ---------------------------------------------------------------------------
BUILD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${BUILD_DIR}/work"
ROOTFS_DIR="${WORK_DIR}/rootfs"
BOOT_DIR="${ROOTFS_DIR}/boot/firmware"
OUTPUT_DIR="${BUILD_DIR}/output"

# ---------------------------------------------------------------------------
# Image configuration
# ---------------------------------------------------------------------------
IMG_NAME="Neuxon-OS-rpi3bplus-arm64"
IMG_SIZE="4G"
BOOT_SIZE="256M"

# ---------------------------------------------------------------------------
# Default user credentials (override via environment)
# ---------------------------------------------------------------------------
USERNAME="${USERNAME:-neuxon}"
PASSWORD="${PASSWORD:-neuxon}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"

# ---------------------------------------------------------------------------
# Export variables for child scripts
# ---------------------------------------------------------------------------
export BUILD_DIR WORK_DIR ROOTFS_DIR BOOT_DIR OUTPUT_DIR
export IMG_NAME IMG_SIZE BOOT_SIZE
export USERNAME PASSWORD GITHUB_TOKEN
export DEBIAN_FRONTEND=noninteractive

# ---------------------------------------------------------------------------
# Source shared helper functions
# ---------------------------------------------------------------------------
source "${BUILD_DIR}/scripts/common.sh"

# ---------------------------------------------------------------------------
# Register the cleanup trap on EXIT and ERR
# ---------------------------------------------------------------------------
trap cleanup EXIT ERR

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------
log_info "============================================================"
log_info " Neuxon OS Build System"
log_info "============================================================"
log_info "Image    : ${IMG_NAME}"
log_info "Size     : ${IMG_SIZE} (boot: ${BOOT_SIZE})"
log_info "User     : ${USERNAME}"
log_info "Work dir : ${WORK_DIR}"
log_info "Output   : ${OUTPUT_DIR}"
if [[ -n "${GITHUB_TOKEN}" ]]; then
    log_info "GitHub API Token: Configured (authenticated)"
else
    log_warn "GitHub API Token: Unset (unauthenticated API calls may be rate-limited)"
fi
log_info "============================================================"

check_root
ensure_deps
verify_qemu_binfmt

# ---------------------------------------------------------------------------
# Prepare working directories
# ---------------------------------------------------------------------------
mkdir -p "${WORK_DIR}" "${ROOTFS_DIR}" "${OUTPUT_DIR}"

# ===== STAGE 00: Bootstrap =================================================
log_info "============================================================"
log_info " Stage 00: Bootstrap (debootstrap arm64)"
log_info "============================================================"
bash "${BUILD_DIR}/stage-neuxon/00-bootstrap/01-run.sh"

# ===== Mount chroot virtual filesystems ====================================
log_info "============================================================"
log_info " Mounting chroot filesystems"
log_info "============================================================"
mount_chroot "${ROOTFS_DIR}"

# Stage configuration files into chroot
log_info "Staging Neuxon configurations into chroot..."
mkdir -p "${ROOTFS_DIR}/tmp/neuxon-config"
cp -r "${BUILD_DIR}/config"/* "${ROOTFS_DIR}/tmp/neuxon-config/"

# Ensure /boot/firmware exists in rootfs
mkdir -p "${ROOTFS_DIR}/boot/firmware"

# ===== STAGE 01: Base System ===============================================
log_info "============================================================"
log_info " Stage 01: Base System Configuration"
log_info "============================================================"
run_in_chroot "${BUILD_DIR}/stage-neuxon/01-base-system/01-run-chroot.sh"

# ===== STAGE 02: GitHub Apps ===============================================
log_info "============================================================"
log_info " Stage 02: GitHub Applications"
log_info "============================================================"
run_in_chroot "${BUILD_DIR}/stage-neuxon/02-github-apps/01-run-chroot.sh"

# ===== STAGE 03: Desktop ===================================================
log_info "============================================================"
log_info " Stage 03: Desktop Environment"
log_info "============================================================"
run_in_chroot "${BUILD_DIR}/stage-neuxon/03-desktop/01-run-chroot.sh"

# ===== STAGE 04: Branding ==================================================
log_info "============================================================"
log_info " Stage 04: Branding & Theming"
log_info "============================================================"
run_in_chroot "${BUILD_DIR}/stage-neuxon/04-branding/01-run-chroot.sh"

# ===== Unmount chroot ======================================================
log_info "============================================================"
log_info " Unmounting chroot filesystems"
log_info "============================================================"
unmount_chroot "${ROOTFS_DIR}"

# ===== STAGE 05: Finalize ==================================================
log_info "============================================================"
log_info " Stage 05: Image Assembly & Compression"
log_info "============================================================"
bash "${BUILD_DIR}/stage-neuxon/05-finalize/01-run.sh"

# ---------------------------------------------------------------------------
# Remove the cleanup trap — build completed successfully
# ---------------------------------------------------------------------------
trap - EXIT ERR

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
IMG_XZ="${OUTPUT_DIR}/${IMG_NAME}.img.xz"
ISO_FILE="${OUTPUT_DIR}/${IMG_NAME}.iso"
CHECKSUM_FILE="${OUTPUT_DIR}/checksums.txt"

log_info ""
log_info "============================================================"
log_info " BUILD COMPLETE"
log_info "============================================================"
log_info ""

if [[ -f "${IMG_XZ}" ]]; then
    log_info "  Image (xz) : ${IMG_XZ}"
    log_info "               $(du -h "${IMG_XZ}" | cut -f1)"
fi

if [[ -f "${ISO_FILE}" ]]; then
    log_info "  ISO        : ${ISO_FILE}"
    log_info "               $(du -h "${ISO_FILE}" | cut -f1)"
fi

if [[ -f "${CHECKSUM_FILE}" ]]; then
    log_info "  Checksums  : ${CHECKSUM_FILE}"
    log_info ""
    cat "${CHECKSUM_FILE}" | while IFS= read -r line; do
        log_info "    ${line}"
    done
fi

log_info ""
log_info "Default credentials: ${USERNAME} / ${PASSWORD}"
log_info "============================================================"
