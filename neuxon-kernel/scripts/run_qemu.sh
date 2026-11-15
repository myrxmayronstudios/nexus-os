#!/usr/bin/env bash
# ==============================================================================
# Neuxon OS: Zero-Latency 1-Bit Monochrome Operating System (v2.0)
# QEMU Bare-Metal Boot & VirtIO-GPU Test Runner
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "${SCRIPT_DIR}")"
BUILD_TARGET="${ROOT_DIR}/target/x86_64-neuxon_os/release/bootimage-neuxon-kernel.bin"

echo "======================================================================"
echo " Neuxon OS 2.0: Launching Bare-Metal x86_64 Kernel under QEMU"
echo " Configuration: SMP=4 cores, RAM=2048MB, VirtIO-GPU, macOS Dock & Top Bar"
echo "======================================================================"

if [ ! -f "${BUILD_TARGET}" ]; then
    echo "[*] Target image not found: ${BUILD_TARGET}"
    echo "[*] Compiling Neuxon OS and building bootable disk image..."
    cargo install bootimage --version "^0.9" || true
    cargo bootimage --release --target x86_64-neuxon_os.json --manifest-path kernel/Cargo.toml
fi

DISPLAY_FLAG=""
if command -v qemu-system-x86_64 &>/dev/null; then
    QEMU_HELP="$(qemu-system-x86_64 -display help 2>&1 || true)"
    if echo "${QEMU_HELP}" | grep -q "sdl"; then
        DISPLAY_FLAG="-display sdl"
    elif echo "${QEMU_HELP}" | grep -q "gtk"; then
        DISPLAY_FLAG="-display gtk"
    fi
fi

exec qemu-system-x86_64 \
    -drive format=raw,file="${BUILD_TARGET}" \
    -machine q35,accel=kvm:tcg \
    -cpu max \
    -smp 4 \
    -m 2048M \
    -vga none \
    -device virtio-gpu-pci \
    -device virtio-net-pci,netdev=net0 \
    -netdev user,id=net0 \
    -serial stdio \
    ${DISPLAY_FLAG} \
    -no-reboot
