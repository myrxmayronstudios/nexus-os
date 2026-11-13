#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# STAGE 05: Finalize & Disk Image Generation
# Runs on HOST (after chroot unmount)
# ============================================================================

_stage05_cleanup() {
    local exit_code=$?
    if [[ ${exit_code} -ne 0 ]]; then
        echo "[STAGE-05] ERROR: Finalize stage failed with exit code ${exit_code}."
    fi
}
trap _stage05_cleanup EXIT ERR

echo "[STAGE-05] ============================================"
echo "[STAGE-05] Cleaning rootfs and creating delivery images"
echo "[STAGE-05] ============================================"

: "${ROOTFS_DIR:?STAGE 05: ROOTFS_DIR is required}"
: "${BUILD_DIR:?STAGE 05: BUILD_DIR is required}"
: "${OUTPUT_DIR:?STAGE 05: OUTPUT_DIR is required}"
: "${IMG_NAME:?STAGE 05: IMG_NAME is required}"

# --------------------------------------------------------------------------
# 1. Clean up temporary files in rootfs
# --------------------------------------------------------------------------
echo "[STAGE-05] Cleaning temporary build artifacts from rootfs..."

# Remove staging configs and temporary directories
rm -rf "${ROOTFS_DIR}/tmp/neuxon-config"
rm -rf "${ROOTFS_DIR}/tmp"/*
rm -rf "${ROOTFS_DIR}/var/cache/apt/archives"/*
rm -rf "${ROOTFS_DIR}/var/lib/apt/lists"/*

# Remove host qemu-aarch64-static binary from final image
if [ -f "${ROOTFS_DIR}/usr/bin/qemu-aarch64-static" ]; then
    rm -f "${ROOTFS_DIR}/usr/bin/qemu-aarch64-static"
    echo "[STAGE-05] Removed qemu-aarch64-static from final rootfs"
fi

# Ensure DNS resolver is clean
if [ -f "${ROOTFS_DIR}/etc/resolv.conf.bak" ]; then
    mv "${ROOTFS_DIR}/etc/resolv.conf.bak" "${ROOTFS_DIR}/etc/resolv.conf"
fi

# --------------------------------------------------------------------------
# 2. Build partitioned disk image and compress to .img.xz
# --------------------------------------------------------------------------
echo "[STAGE-05] Calling create-image.sh to produce partitioned .img.xz ..."
bash "${BUILD_DIR}/scripts/create-image.sh"

# --------------------------------------------------------------------------
# 3. Build ISO image deliverable
# --------------------------------------------------------------------------
echo "[STAGE-05] Calling create-iso.sh to produce .iso ..."
bash "${BUILD_DIR}/scripts/create-iso.sh"

echo "[STAGE-05] ============================================"
echo "[STAGE-05] Finalize stage completed successfully"
echo "[STAGE-05] ============================================"
trap - EXIT ERR
