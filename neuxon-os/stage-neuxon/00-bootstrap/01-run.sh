#!/usr/bin/env bash
set -euo pipefail

_stage00_cleanup() {
    local exit_code=$?
    if [[ ${exit_code} -ne 0 ]]; then
        echo "[STAGE-00] ERROR: Bootstrap stage failed with exit code ${exit_code}."
    fi
}
trap _stage00_cleanup EXIT ERR

# ============================================================================
# STAGE 00: Bootstrap - Debootstrap arm64 rootfs
# Runs on HOST (not in chroot)
# ============================================================================

echo "[STAGE-00] ============================================"
echo "[STAGE-00] Starting Debootstrap for arm64 rootfs"
echo "[STAGE-00] ============================================"

# Validate required environment variables
if [ -z "${ROOTFS_DIR:-}" ]; then
    echo "[STAGE-00] ERROR: ROOTFS_DIR is not set"
    exit 1
fi

if [ -z "${WORK_DIR:-}" ]; then
    echo "[STAGE-00] ERROR: WORK_DIR is not set"
    exit 1
fi

echo "[STAGE-00] ROOTFS_DIR: ${ROOTFS_DIR}"
echo "[STAGE-00] WORK_DIR:   ${WORK_DIR}"

# Ensure the rootfs directory exists
mkdir -p "${ROOTFS_DIR}"

# Run debootstrap to create a minimal arm64 Debian Bookworm rootfs
echo "[STAGE-00] Running debootstrap --arch=arm64 --variant=minbase ..."
echo "[STAGE-00] Mirror: http://deb.debian.org/debian"
echo "[STAGE-00] Suite:  bookworm"
echo "[STAGE-00] Include: ca-certificates, apt-transport-https, gnupg, wget, curl"

debootstrap \
    --arch=arm64 \
    --variant=minbase \
    --include=ca-certificates,apt-transport-https,gnupg,wget,curl \
    bookworm \
    "${ROOTFS_DIR}" \
    http://deb.debian.org/debian

if [ $? -ne 0 ]; then
    echo "[STAGE-00] ERROR: debootstrap failed!"
    exit 1
fi

echo "[STAGE-00] Debootstrap completed successfully"

# Copy qemu-aarch64-static into the rootfs for chroot functionality
echo "[STAGE-00] Setting up qemu-aarch64-static for cross-architecture chroot ..."

QEMU_SRC="/usr/bin/qemu-aarch64-static"
QEMU_DST="${ROOTFS_DIR}/usr/bin/qemu-aarch64-static"

if [ -f "${QEMU_SRC}" ]; then
    cp "${QEMU_SRC}" "${QEMU_DST}"
    chmod 755 "${QEMU_DST}"
    echo "[STAGE-00] Copied qemu-aarch64-static to rootfs"
else
    echo "[STAGE-00] WARNING: ${QEMU_SRC} not found on host!"
    echo "[STAGE-00] Attempting to find qemu-aarch64-static in PATH ..."
    QEMU_FOUND=$(which qemu-aarch64-static 2>/dev/null || true)
    if [ -n "${QEMU_FOUND}" ]; then
        cp "${QEMU_FOUND}" "${QEMU_DST}"
        chmod 755 "${QEMU_DST}"
        echo "[STAGE-00] Copied qemu-aarch64-static from ${QEMU_FOUND} to rootfs"
    else
        echo "[STAGE-00] ERROR: qemu-aarch64-static not found anywhere!"
        echo "[STAGE-00] Install qemu-user-static: apt-get install qemu-user-static binfmt-support"
        exit 1
    fi
fi

# Verify the rootfs looks sane
echo "[STAGE-00] Verifying rootfs structure ..."
for dir in bin etc lib sbin usr var; do
    if [ ! -d "${ROOTFS_DIR}/${dir}" ]; then
        echo "[STAGE-00] ERROR: Expected directory ${ROOTFS_DIR}/${dir} not found!"
        exit 1
    fi
done

echo "[STAGE-00] Rootfs structure verified OK"

# Show rootfs size
ROOTFS_SIZE=$(du -sh "${ROOTFS_DIR}" | cut -f1)
echo "[STAGE-00] Current rootfs size: ${ROOTFS_SIZE}"

echo "[STAGE-00] ============================================"
echo "[STAGE-00] Bootstrap stage completed successfully"
echo "[STAGE-00] ============================================"
