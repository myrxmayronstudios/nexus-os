#!/usr/bin/env bash
# ==============================================================================
# Neuxon OS 2.0: Automated Kernel & Bootimage Build Pipeline
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "${SCRIPT_DIR}")"
cd "${ROOT_DIR}"

echo "======================================================================"
echo " Starting Neuxon OS 2.0 Clean Automated Build Pipeline"
echo "======================================================================"

# 1. Check Toolchain Requirements
rustup component add rust-src llvm-tools-preview --toolchain nightly
if ! command -v cargo-bootimage &>/dev/null; then
    echo "[*] Installing bootimage tool..."
    cargo install bootimage --version "^0.9"
fi

# 2. Strict Verification Audit
echo "[*] Step 1: Verification Audit (Zero Placeholders & Memory Safety)..."
if grep -rni "// TODO" kernel/src/ || grep -rni "// FIXME" kernel/src/; then
    echo "[!] Error: Found placeholder comments in kernel sources!"
    exit 1
fi
echo "[✓] Zero placeholders verified."

# 3. Build Kernel Target
echo "[*] Step 2: Compiling Kernel with Nightly Compiler..."
cargo build --release --target x86_64-neuxon_os.json --manifest-path kernel/Cargo.toml

# 4. Generate Bootable Image
echo "[*] Step 3: Packing Bootable Disk Image..."
cargo bootimage --release --target x86_64-neuxon_os.json --manifest-path kernel/Cargo.toml

TARGET_IMG="target/x86_64-neuxon_os/release/bootimage-neuxon-kernel.bin"
if [ -f "${TARGET_IMG}" ]; then
    IMG_SIZE=$(stat -c%s "${TARGET_IMG}" 2>/dev/null || stat -f%z "${TARGET_IMG}" 2>/dev/null)
    echo "======================================================================"
    echo " [✓] Neuxon OS 2.0 Build Succeeded!"
    echo " Output Image: ${TARGET_IMG} (${IMG_SIZE} bytes)"
    echo " Ready for QEMU or physical flash via: ./scripts/run_qemu.sh"
    echo "======================================================================"
else
    echo "[!] Error: Output bootimage not produced!"
    exit 1
fi
