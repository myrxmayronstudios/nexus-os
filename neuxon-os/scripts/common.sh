#!/usr/bin/env bash
###############################################################################
# scripts/common.sh — Shared helper functions for the Neuxon OS build system
###############################################################################
# Sourced by build.sh and stage scripts; not executed directly.
###############################################################################
set -euo pipefail

# ---------------------------------------------------------------------------
# Logging & Terminal Colors
# ---------------------------------------------------------------------------
_CLR_RESET="\033[0m"
_CLR_GREEN="\033[1;32m"
_CLR_YELLOW="\033[1;33m"
_CLR_RED="\033[1;31m"
_CLR_CYAN="\033[1;36m"

_timestamp() {
    date "+%Y-%m-%d %H:%M:%S"
}

log_info() {
    printf "${_CLR_GREEN}[INFO]${_CLR_RESET}  ${_CLR_CYAN}%s${_CLR_RESET}  %s\n" "$(_timestamp)" "$*"
}

log_warn() {
    printf "${_CLR_YELLOW}[WARN]${_CLR_RESET}  ${_CLR_CYAN}%s${_CLR_RESET}  %s\n" "$(_timestamp)" "$*" >&2
}

log_error() {
    printf "${_CLR_RED}[ERROR]${_CLR_RESET} ${_CLR_CYAN}%s${_CLR_RESET}  %s\n" "$(_timestamp)" "$*" >&2
}

# ---------------------------------------------------------------------------
# check_root — Abort if not running as root
# ---------------------------------------------------------------------------
check_root() {
    if [[ "$(id -u)" -ne 0 ]]; then
        log_error "This script must be run as root (or via sudo)."
        exit 1
    fi
}

# ---------------------------------------------------------------------------
# ensure_deps — Install host build dependencies if missing
# ---------------------------------------------------------------------------
ensure_deps() {
    local -a deps=(
        debootstrap
        binfmt-support
        xz-utils
        dosfstools
        e2fsprogs
        parted
        kpartx
        xorriso
        mtools
        git
        curl
        wget
        ca-certificates
        rsync
        jq
        unzip
        file
    )

    log_info "Checking host dependencies..."
    local missing=()
    for pkg in "${deps[@]}"; do
        if ! dpkg -s "${pkg}" &>/dev/null; then
            missing+=("${pkg}")
        fi
    done

    # Check for QEMU arm64 static binary
    if ! command -v qemu-aarch64-static &>/dev/null && [[ ! -f /usr/bin/qemu-aarch64-static ]]; then
        if apt-cache show qemu-user-static &>/dev/null; then
            missing+=("qemu-user-static")
        else
            missing+=("qemu-user-binfmt")
        fi
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_info "Installing missing packages: ${missing[*]}"
        apt-get update -qq
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${missing[@]}" || {
            apt-get install -y -qq qemu-user-binfmt 2>/dev/null || true
        }
    else
        log_info "All host dependencies are satisfied."
    fi
}

# ---------------------------------------------------------------------------
# verify_qemu_binfmt — Ensure aarch64 binfmt registration is active
# ---------------------------------------------------------------------------
verify_qemu_binfmt() {
    log_info "Verifying QEMU aarch64 binfmt support..."
    if [[ ! -f /proc/sys/fs/binfmt_misc/qemu-aarch64 ]] && [[ ! -f /proc/sys/fs/binfmt_misc/aarch64 ]]; then
        log_warn "binfmt qemu-aarch64 not registered. Attempting to register..."
        if command -v update-binfmts &>/dev/null; then
            update-binfmts --enable qemu-aarch64 2>/dev/null || true
        fi
        if [[ ! -f /proc/sys/fs/binfmt_misc/qemu-aarch64 ]] && [[ ! -f /proc/sys/fs/binfmt_misc/aarch64 ]]; then
            if command -v docker &>/dev/null; then
                docker run --rm --privileged multiarch/qemu-user-static --reset -p yes 2>/dev/null || true
            fi
        fi
    fi

    if [[ ! -f /proc/sys/fs/binfmt_misc/qemu-aarch64 ]] && [[ ! -f /proc/sys/fs/binfmt_misc/aarch64 ]]; then
        log_error "ARM64 binfmt support is unavailable. Please install qemu-user-static."
        return 1
    fi
    log_info "QEMU aarch64 binfmt: OK"
}

# ---------------------------------------------------------------------------
# mount_chroot — Bind-mount virtual filesystems into the rootfs
# ---------------------------------------------------------------------------
mount_chroot() {
    local rootfs="${1:?mount_chroot: ROOTFS_DIR is required}"

    log_info "Mounting chroot filesystems in ${rootfs}..."

    mkdir -p "${rootfs}/dev" "${rootfs}/dev/pts" "${rootfs}/proc" "${rootfs}/sys" "${rootfs}/tmp"

    mountpoint -q "${rootfs}/dev"     || mount --bind /dev "${rootfs}/dev"
    mountpoint -q "${rootfs}/dev/pts" || mount --bind /dev/pts "${rootfs}/dev/pts"
    mountpoint -q "${rootfs}/proc"    || mount -t proc proc "${rootfs}/proc"
    mountpoint -q "${rootfs}/sys"     || mount -t sysfs sysfs "${rootfs}/sys"
    mountpoint -q "${rootfs}/tmp"     || mount -t tmpfs tmpfs "${rootfs}/tmp"

    # Copy the host DNS resolver so packages can fetch from the network
    if [[ -e "${rootfs}/etc/resolv.conf" ]] || [[ -L "${rootfs}/etc/resolv.conf" ]]; then
        mv "${rootfs}/etc/resolv.conf" "${rootfs}/etc/resolv.conf.bak" 2>/dev/null || true
    fi
    cp -L /etc/resolv.conf "${rootfs}/etc/resolv.conf"

    # Ensure /boot/firmware exists and is clean
    mkdir -p "${rootfs}/boot/firmware"
}

# ---------------------------------------------------------------------------
# unmount_chroot — Safely unmount all chroot bind mounts (reverse order)
# ---------------------------------------------------------------------------
unmount_chroot() {
    local rootfs="${1:?unmount_chroot: ROOTFS_DIR is required}"

    log_info "Unmounting chroot filesystems from ${rootfs}..."

    # Restore original resolv.conf
    if [[ -e "${rootfs}/etc/resolv.conf.bak" ]]; then
        mv "${rootfs}/etc/resolv.conf.bak" "${rootfs}/etc/resolv.conf" 2>/dev/null || true
    fi

    local -a mounts=(
        "${rootfs}/tmp"
        "${rootfs}/sys"
        "${rootfs}/proc"
        "${rootfs}/dev/pts"
        "${rootfs}/dev"
    )

    for mnt in "${mounts[@]}"; do
        if mountpoint -q "${mnt}" 2>/dev/null; then
            umount -lf "${mnt}" 2>/dev/null || log_warn "Failed to unmount ${mnt}"
        fi
    done
}

# ---------------------------------------------------------------------------
# cleanup_mounts — Emergency cleanup of chroot bind mounts and loop devices
# ---------------------------------------------------------------------------
cleanup_mounts() {
    local rootfs="${1:-${ROOTFS_DIR:-}}"
    if [[ -n "${rootfs}" ]] && [[ -d "${rootfs}" ]]; then
        unmount_chroot "${rootfs}" 2>/dev/null || true
    fi
    if [[ -n "${LOOP_DEV:-}" ]]; then
        kpartx -d "${LOOP_DEV}" 2>/dev/null || true
        losetup -d "${LOOP_DEV}" 2>/dev/null || true
        LOOP_DEV=""
    fi
}

# ---------------------------------------------------------------------------
# run_in_chroot — Copy a script into the rootfs and execute it inside chroot
# ---------------------------------------------------------------------------
run_in_chroot() {
    local script_path="${1:?run_in_chroot: script path is required}"
    local rootfs="${ROOTFS_DIR:?run_in_chroot: ROOTFS_DIR must be set}"

    if [[ ! -f "${script_path}" ]]; then
        log_error "Chroot script not found: ${script_path}"
        return 1
    fi

    local script_name
    script_name="$(basename "${script_path}")"
    local chroot_script="/tmp/_neuxon_${script_name}"

    log_info "Running in chroot: ${script_path}"

    # Copy the script into the rootfs
    cp "${script_path}" "${rootfs}${chroot_script}"
    chmod 755 "${rootfs}${chroot_script}"

    # Copy host qemu static binary into chroot if needed
    if [[ ! -f "${rootfs}/usr/bin/qemu-aarch64-static" ]] && command -v qemu-aarch64-static &>/dev/null; then
        cp "$(command -v qemu-aarch64-static)" "${rootfs}/usr/bin/qemu-aarch64-static"
    fi

    # Forward GITHUB_TOKEN and core parameters into chroot
    chroot "${rootfs}" /usr/bin/env \
        USERNAME="${USERNAME:-neuxon}" \
        PASSWORD="${PASSWORD:-neuxon}" \
        IMG_NAME="${IMG_NAME:-Neuxon-OS-rpi3bplus-arm64}" \
        BOOT_DIR="/boot/firmware" \
        GITHUB_TOKEN="${GITHUB_TOKEN:-}" \
        DEBIAN_FRONTEND=noninteractive \
        bash -e "${chroot_script}"

    # Clean up script inside chroot
    rm -f "${rootfs}${chroot_script}"
}

# ---------------------------------------------------------------------------
# cleanup — Main build error & exit trap
# ---------------------------------------------------------------------------
cleanup() {
    local exit_code=$?
    if [[ ${exit_code} -ne 0 ]]; then
        log_error "Build failed with exit code ${exit_code}. Performing cleanup..."
    fi

    cleanup_mounts "${ROOTFS_DIR:-}"

    if [[ ${exit_code} -ne 0 ]]; then
        log_error "Build terminated abnormally. Cleaned up mounts and loop devices."
    fi
}
