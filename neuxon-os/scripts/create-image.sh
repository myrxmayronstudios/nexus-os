#!/usr/bin/env bash
###############################################################################
# scripts/create-image.sh — Create the final Neuxon OS disk image
###############################################################################
# Called by stage-neuxon/05-finalize/01-run.sh after the rootfs is fully
# assembled. Produces a partitioned .img, compresses it to .img.xz, and
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
: "${BOOT_SIZE:=256M}"

IMG_FILE="${OUTPUT_DIR}/${IMG_NAME}.img"
IMG_XZ="${IMG_FILE}.xz"
CHECKSUM_FILE="${OUTPUT_DIR}/checksums.txt"

# Temporary mount points
MNT_ROOT="${OUTPUT_DIR}/mnt_root"
MNT_BOOT="${OUTPUT_DIR}/mnt_boot"

LOOP_DEV=""

# ---------------------------------------------------------------------------
# Cleanup helper — detach loop + unmount on error or exit
# ---------------------------------------------------------------------------
_image_cleanup() {
    local exit_code=$?
    if [[ ${exit_code} -ne 0 ]]; then
        log_warn "Image creation interrupted or failed (code ${exit_code}) — cleaning up..."
    fi
    umount "${MNT_ROOT}/boot/firmware" 2>/dev/null || true
    umount "${MNT_ROOT}" 2>/dev/null || true
    umount "${MNT_BOOT}" 2>/dev/null || true
    if [[ -n "${LOOP_DEV}" ]]; then
        kpartx -d "${LOOP_DEV}" 2>/dev/null || true
        losetup -d "${LOOP_DEV}" 2>/dev/null || true
        LOOP_DEV=""
    fi
    rm -rf "${MNT_ROOT}" "${MNT_BOOT}" 2>/dev/null || true
}
trap _image_cleanup EXIT ERR

# ---------------------------------------------------------------------------
# 1. Calculate required image size dynamically
#    Exact rootfs size + 65% safety buffer + 1GB headroom + 256MB boot partition
# ---------------------------------------------------------------------------
log_info "Calculating required image size from assembled rootfs..."
mkdir -p "${OUTPUT_DIR}"

ROOTFS_BYTES=$(du -sb "${ROOTFS_DIR}" | cut -f1)
BOOT_BYTES=$(( 256 * 1024 * 1024 ))
# Generous 65% + 1024MB safety buffer ensures ext4 inode tables, journals, and rsync never run out of space
SAFETY_BUFFER=$(( (ROOTFS_BYTES * 65 / 100) + (1024 * 1024 * 1024) ))
TOTAL_BYTES=$(( ROOTFS_BYTES + SAFETY_BUFFER + BOOT_BYTES + (64 * 1024 * 1024) ))

# Align to 128MB boundary
ALIGN_128M=$(( 128 * 1024 * 1024 ))
IMG_BYTES=$(( ((TOTAL_BYTES + ALIGN_128M - 1) / ALIGN_128M) * ALIGN_128M ))

log_info "Rootfs size  : $((ROOTFS_BYTES / 1024 / 1024)) MB"
log_info "Calculated   : $((IMG_BYTES / 1024 / 1024)) MB (with +65% + 1GB safety buffer & 256M boot)"
log_info "Creating sparse image file: ${IMG_FILE}"
truncate -s "${IMG_BYTES}" "${IMG_FILE}"

# ---------------------------------------------------------------------------
# 2. Partition the image (MBR / msdos label)
#    Partition 1: FAT32 boot (256 MB)
#    Partition 2: ext4  root (rest)
# ---------------------------------------------------------------------------
log_info "Partitioning image with MBR layout..."
parted -s "${IMG_FILE}" -- \
    mklabel msdos \
    mkpart primary fat32 4MiB "${BOOT_SIZE}" \
    mkpart primary ext4 "${BOOT_SIZE}" 100% \
    set 1 boot on \
    set 1 lba on

# Set deterministic MBR disk signature 0x2ba4ee16 so PARTUUID is always 2ba4ee16-01 / 2ba4ee16-02
log_info "Writing deterministic MBR disk signature (0x2ba4ee16)..."
printf '\x16\xee\xa4\x2b' | dd of="${IMG_FILE}" bs=1 seek=440 count=4 conv=notrunc

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

log_info "Formatting root partition (ext4, label=NEUXON-ROOT, reserved=1%)..."
mkfs.ext4 -L "NEUXON-ROOT" -m 1 -O "^metadata_csum,^64bit" -F "${PART_ROOT}"

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
log_info "Writing /etc/fstab inside image..."
cat > "${MNT_ROOT}/etc/fstab" <<'FSTAB'
# <filesystem>           <mount>         <type>  <options>                              <dump> <pass>
PARTUUID=2ba4ee16-02     /               ext4    defaults,noatime,commit=60             0      1
PARTUUID=2ba4ee16-01     /boot/firmware  vfat    defaults,flush                         0      2
tmpfs                    /tmp            tmpfs   defaults,nosuid,nodev,size=128M        0      0
tmpfs                    /var/log        tmpfs   defaults,nosuid,nodev,noexec,size=32M  0      0
tmpfs                    /var/tmp        tmpfs   defaults,nosuid,nodev,size=64M         0      0
FSTAB

# ---------------------------------------------------------------------------
# 8. Sync, unmount and optimize filesystem
# ---------------------------------------------------------------------------
log_info "Syncing and unmounting..."
sync
umount "${MNT_ROOT}/boot/firmware"
umount "${MNT_ROOT}"

# Run filesystem check and shrink to minimal size
log_info "Optimizing ext4 filesystem with e2fsck and resize2fs..."
e2fsck -f -y "${PART_ROOT}" || true
# Keep filesystem aligned with partition boundaries (do not shrink with -M)
# resize2fs -M "${PART_ROOT}" || true

# ---------------------------------------------------------------------------
# 9. Detach loopback
# ---------------------------------------------------------------------------
log_info "Detaching loopback device..."
kpartx -d "${LOOP_DEV}"
losetup -d "${LOOP_DEV}"
LOOP_DEV=""  # prevent double-detach in trap

rm -rf "${MNT_ROOT}" "${MNT_BOOT}"

# ---------------------------------------------------------------------------
# 10. Compress with multi-threaded xz
# ---------------------------------------------------------------------------
log_info "Compressing image with xz (multi-threaded -T0 -9)..."
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

# Remove trap on clean exit
trap - EXIT ERR
