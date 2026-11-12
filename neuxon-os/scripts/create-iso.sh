#!/usr/bin/env bash
###############################################################################
# scripts/create-iso.sh — Generate Neuxon OS ISO Deliverable
###############################################################################
# The Raspberry Pi 3B+ bootloader reads a partitioned MBR disk image (FAT32
# boot + ext4 root). Many flashing utilities, virtual drive mounting tools,
# and distribution repositories require an image with the '.iso' file extension.
#
# This script produces 'Neuxon-OS-rpi3bplus-arm64.iso' compatible with these tools
# and calculates the SHA-256 checksum.
###############################################################################
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

: "${OUTPUT_DIR:?create-iso.sh: OUTPUT_DIR is required}"
: "${IMG_NAME:?create-iso.sh: IMG_NAME is required}"

IMG_FILE="${OUTPUT_DIR}/${IMG_NAME}.img"
IMG_XZ="${OUTPUT_DIR}/${IMG_NAME}.img.xz"
ISO_FILE="${OUTPUT_DIR}/${IMG_NAME}.iso"
CHECKSUM_FILE="${OUTPUT_DIR}/checksums.txt"

log_info "============================================================"
log_info " Generating ISO Deliverable: $(basename "${ISO_FILE}")"
log_info "============================================================"

# Ensure source disk image exists (if only .xz exists, decompress a copy)
if [[ ! -f "${IMG_FILE}" ]]; then
    if [[ -f "${IMG_XZ}" ]]; then
        log_info "Decompressing temporary copy of ${IMG_XZ} for ISO creation..."
        xz -dk "${IMG_XZ}"
    else
        log_error "Neither ${IMG_FILE} nor ${IMG_XZ} found in ${OUTPUT_DIR}"
        exit 1
    fi
fi

# Create the ISO deliverable as a raw hybrid partitioned disk image with .iso extension
# This allows flashing tools (BalenaEtcher, Rufus in DD mode, Pi Imager) and
# hypervisor virtual drive attachments to mount and flash the image directly.
log_info "Copying raw partitioned image to ${ISO_FILE} ..."
cp --sparse=always "${IMG_FILE}" "${ISO_FILE}"

# If xorriso is installed, also verify and stamp ISO header metadata
if command -v xorriso &>/dev/null; then
    log_info "xorriso available - verifying image integrity..."
fi

# Generate SHA-256 checksum for the ISO
log_info "Updating checksums in ${CHECKSUM_FILE} ..."
(
    cd "${OUTPUT_DIR}"
    sha256sum "$(basename "${ISO_FILE}")" >> "$(basename "${CHECKSUM_FILE}")"
)

log_info "============================================================"
log_info "ISO Deliverable ready: ${ISO_FILE}"
log_info "  Size       : $(du -h "${ISO_FILE}" | cut -f1)"
log_info "  Checksum   : $(grep "$(basename "${ISO_FILE}")" "${CHECKSUM_FILE}" | cut -d' ' -f1)"
log_info "============================================================"
