#!/usr/bin/env bash
###############################################################################
# scripts/create-image.sh — Create the final Neuxon OS disk image
###############################################################################
# Called by stage-neuxon/05-finalize/01-run.sh after the rootfs is fully
# assembled.  Produces a partitioned .img, compresses it to .img.xz, and
# prints SHA-256 checksums.
###############################################################################
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# ---------------------------------------------------------------------------
# Expect these variables from the caller (build.sh / 05-finalize)
# ---------------------------------------------------------------------------
: "${ROOTFS_DIR:?create-image.sh: ROOTFS_DIR is required}"
: "${OUTPUT_DIR:?create-image.sh: OUTPUT_DIR is required}"
: "${IMG_NAME:?create-image.sh: IMG_NAME is required}"
: "${IMG_SIZE:?create-image.sh: IMG_SIZE is required}"
: "${BOOT_SIZE:?create-image.sh: BOOT_SIZE is required}"

IMG_FILE="${OUTPUT_DIR}/${IMG_NAME}.img"
IMG_XZ="${IMG_FILE}.xz"
CHECKSUM_FILE="${OUTPUT_DIR}/checksums.txt"

# Temporary mount points
MNT_ROOT="${OUTPUT_DIR}/mnt_root"
MNT_BOOT="${OUTPUT_DIR}/mnt_boot"

LOOP_DEV=""

# ---------------------------------------------------------------------------
# Cleanup helper — detach loop + unmount on error
# ---------------------------------------------------------------------------
_image_cleanup() {
    log_warn "Image creation interrupted — cleaning up..."
    umount "${MNT_BOOT}" 2>/dev/null || true
    umount "${MNT_ROOT}" 2>/dev/null || true
    if [[ -n "${LOOP_DEV}" ]]; then
        kpartx -d "${LOOP_DEV}" 2>/dev/null || true
        losetup -d "${LOOP_DEV}" 2>/dev/null || true
    fi
    rm -rf "${MNT_ROOT}" "${MNT_BOOT}" 2>/dev/null || true
}
trap _image_cleanup EXIT

# ---------------------------------------------------------------------------
# 1. Create sparse image file
# ---------------------------------------------------------------------------
log_info "Creating sparse image file: ${IMG_FILE} (${IMG_SIZE})"
mkdir -p "${OUTPUT_DIR}"
truncate -s "${IMG_SIZE}" "${IMG_FILE}"

# ---------------------------------------------------------------------------
# 2. Partition the image (MBR / msdos label)
#    Partition 1: FAT32 boot (256 MB)
#    Partition 2: ext4  root (rest)
# ---------------------------------------------------------------------------
log_info "Partitioning image..."
parted -s "${IMG_FILE}" -- \
    mklabel msdos \
    mkpart primary fat32 4MiB "${BOOT_SIZE}" \
    mkpart primary ext4 "${BOOT_SIZE}" 100% \
    set 1 boot on \
    set 1 lba on

# ---------------------------------------------------------------------------
# 3. Setup loopback with kpartx
# ---------------------------------------------------------------------------
log_info "Setting up loopback device..."
LOOP_DEV="$(losetup --find --show --partscan "${IMG_FILE}")"
log_info "Loopback device: ${LOOP_DEV}"

# kpartx creates /dev/mapper/<loop>p1, /dev/mapper/<loop>p2
kpartx -a -s "${LOOP_DEV}"

# Derive partition device paths
LOOP_BASE="$(basename "${LOOP_DEV}")"
PART_BOOT="/dev/mapper/${LOOP_BASE}p1"
PART_ROOT="/dev/mapper/${LOOP_BASE}p2"

# Wait for device nodes to appear
sleep 2
if [[ ! -b "${PART_BOOT}" ]] || [[ ! -b "${PART_ROOT}" ]]; then
    log_error "Partition device nodes not found: ${PART_BOOT}, ${PART_ROOT}"
    exit 1
fi

# ---------------------------------------------------------------------------
# 4. Format partitions
# ---------------------------------------------------------------------------
log_info "Formatting boot partition (FAT32, label=NEUXON-BOOT)..."
mkfs.vfat -F 32 -n "NEUXON-BOOT" "${PART_BOOT}"

log_info "Formatting root partition (ext4, label=NEUXON-ROOT)..."
mkfs.ext4 -L "NEUXON-ROOT" -O "^metadata_csum,^64bit" -F "${PART_ROOT}"

# ---------------------------------------------------------------------------
# 5. Mount partitions
# ---------------------------------------------------------------------------
mkdir -p "${MNT_ROOT}" "${MNT_BOOT}"
mount "${PART_ROOT}" "${MNT_ROOT}"
mkdir -p "${MNT_ROOT}/boot/firmware"
mount "${PART_BOOT}" "${MNT_ROOT}/boot/firmware"

# ---------------------------------------------------------------------------
# 6. Copy rootfs content
# ---------------------------------------------------------------------------
log_info "Copying root filesystem..."
rsync -aHAXx --exclude='boot/firmware/*' "${ROOTFS_DIR}/" "${MNT_ROOT}/"

log_info "Copying boot firmware files..."
if [[ -d "${ROOTFS_DIR}/boot/firmware" ]]; then
    rsync -aHAXx "${ROOTFS_DIR}/boot/firmware/" "${MNT_ROOT}/boot/firmware/"
fi

# ---------------------------------------------------------------------------
# 7. Write /etc/fstab inside the image
# ---------------------------------------------------------------------------
log_info "Writing /etc/fstab..."
cat > "${MNT_ROOT}/etc/fstab" <<'FSTAB'
# <filesystem>           <mount>         <type>  <options>                    <dump> <pass>
LABEL=NEUXON-ROOT        /               ext4    defaults,noatime             0      1
LABEL=NEUXON-BOOT        /boot/firmware  vfat    defaults,flush               0      2
tmpfs                    /tmp            tmpfs   defaults,nosuid,nodev        0      0
FSTAB

# ---------------------------------------------------------------------------
# 8. Sync and unmount
# ---------------------------------------------------------------------------
log_info "Syncing and unmounting..."
sync
umount "${MNT_ROOT}/boot/firmware"
umount "${MNT_ROOT}"

# ---------------------------------------------------------------------------
# 9. Detach loopback
# ---------------------------------------------------------------------------
log_info "Detaching loopback device..."
kpartx -d "${LOOP_DEV}"
losetup -d "${LOOP_DEV}"
LOOP_DEV=""  # prevent double-detach in trap

rm -rf "${MNT_ROOT}" "${MNT_BOOT}"

# ---------------------------------------------------------------------------
# 10. Compress with xz (keep original .img with -k for ISO packaging)
# ---------------------------------------------------------------------------
log_info "Compressing image with xz (this may take a while)..."
xz -T0 -9 -k --force "${IMG_FILE}"

# ---------------------------------------------------------------------------
# 11. Checksums
# ---------------------------------------------------------------------------
log_info "Generating SHA-256 checksums..."
(
    cd "${OUTPUT_DIR}"
    sha256sum "$(basename "${IMG_XZ}")" > "$(basename "${CHECKSUM_FILE}")"
)

log_info "============================================================"
log_info "Image created successfully!"
log_info "  Compressed : ${IMG_XZ}"
log_info "  Checksums  : ${CHECKSUM_FILE}"
log_info "  Size       : $(du -h "${IMG_XZ}" | cut -f1)"
log_info "============================================================"

# Remove trap — clean exit
trap - EXIT
