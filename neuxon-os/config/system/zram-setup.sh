#!/usr/bin/env bash
# Neuxon OS - ZRAM Configuration Script
# Configures ZRAM swap for Raspberry Pi 3B+ (1GB RAM, 4 cores)
set -euo pipefail

echo "=== Neuxon OS ZRAM Setup ==="

# Load the zram kernel module
modprobe zram num_devices=4
echo "[OK] Loaded zram module with 4 devices"

# Calculate total ZRAM size as 100% of physical RAM
TOTAL_MEM_KB=$(awk '/^MemTotal:/ { print $2 }' /proc/meminfo)
TOTAL_ZRAM_KB=${TOTAL_MEM_KB}
echo "[INFO] Physical RAM: $(( TOTAL_MEM_KB / 1024 )) MB"
echo "[INFO] Total ZRAM allocation: $(( TOTAL_ZRAM_KB / 1024 )) MB"

# Number of CPU cores (4 for RPi 3B+)
NUM_CORES=4

# Each device gets 25% of total ZRAM allocation
PER_DEVICE_KB=$(( TOTAL_ZRAM_KB / NUM_CORES ))
PER_DEVICE_BYTES=$(( PER_DEVICE_KB * 1024 ))

echo "[INFO] Per-device ZRAM size: $(( PER_DEVICE_KB / 1024 )) MB"
echo "[INFO] Compression algorithm: zstd"

# Configure each zram device
for i in $(seq 0 $(( NUM_CORES - 1 ))); do
    DEVICE="/dev/zram${i}"
    SYSFS="/sys/block/zram${i}"

    # Set compression algorithm
    echo zstd > "${SYSFS}/comp_algorithm"

    # Set device size
    echo "${PER_DEVICE_BYTES}" > "${SYSFS}/disksize"

    # Create swap and enable with priority 100
    mkswap "${DEVICE}" > /dev/null 2>&1
    swapon -p 100 "${DEVICE}"

    echo "[OK] ${DEVICE}: $(( PER_DEVICE_KB / 1024 )) MB (zstd, priority 100)"
done

# Apply sysctl settings for ZRAM-optimized swapping
sysctl -w vm.swappiness=100 > /dev/null
sysctl -w vm.page-cluster=0 > /dev/null
sysctl -w vm.vfs_cache_pressure=50 > /dev/null

echo "[OK] sysctl: swappiness=100, page-cluster=0, vfs_cache_pressure=50"
echo "=== ZRAM setup complete ==="
