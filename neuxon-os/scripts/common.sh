#!/usr/bin/env bash
###############################################################################
# scripts/common.sh — Shared helper functions for the Neuxon OS build system
###############################################################################
# Sourced by build.sh; not executed directly.
###############################################################################

# ---------------------------------------------------------------------------
# Logging
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
        qemu-user-static
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
    )

    log_info "Checking host dependencies..."
    local missing=()
    for pkg in "${deps[@]}"; do
        if ! dpkg -s "${pkg}" &>/dev/null; then
            missing+=("${pkg}")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_info "Installing missing packages: ${missing[*]}"
        apt-get update -qq
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${missing[@]}"
    else
        log_info "All host dependencies are satisfied."
    fi
}

# ---------------------------------------------------------------------------
# mount_chroot — Bind-mount virtual filesystems into the rootfs
# ---------------------------------------------------------------------------
mount_chroot() {
    local rootfs="${1:?mount_chroot: ROOTFS_DIR is required}"

    log_info "Mounting chroot filesystems in ${rootfs}..."

    mount --bind /dev          "${rootfs}/dev"
    mount --bind /dev/pts      "${rootfs}/dev/pts"
    mount -t proc proc         "${rootfs}/proc"
    mount -t sysfs sysfs       "${rootfs}/sys"
    mount -t tmpfs tmpfs       "${rootfs}/tmp"

    # Copy the host DNS resolver so packages can fetch from the network
    if [[ -e "${rootfs}/etc/resolv.conf" ]] || [[ -L "${rootfs}/etc/resolv.conf" ]]; then
        mv "${rootfs}/etc/resolv.conf" "${rootfs}/etc/resolv.conf.bak" 2>/dev/null || true
    fi
    cp -L /etc/resolv.conf "${rootfs}/etc/resolv.conf"
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

    # Export variables so they are available inside the chroot
    chroot "${rootfs}" /usr/bin/env \
        USERNAME="${USERNAME}" \
        PASSWORD="${PASSWORD}" \
        IMG_NAME="${IMG_NAME}" \
        BOOT_DIR="/boot/firmware" \
        DEBIAN_FRONTEND=noninteractive \
        bash -e "${chroot_script}"

    # Clean up
    rm -f "${rootfs}${chroot_script}"
}

# ---------------------------------------------------------------------------
# cleanup — Trap handler: unmount chroot + detach loops on error
# ---------------------------------------------------------------------------
cleanup() {
    local exit_code=$?
    if [[ ${exit_code} -ne 0 ]]; then
        log_error "Build failed with exit code ${exit_code}. Cleaning up..."
    fi

    # Attempt to unmount chroot mounts
    if [[ -n "${ROOTFS_DIR:-}" ]] && [[ -d "${ROOTFS_DIR}" ]]; then
        unmount_chroot "${ROOTFS_DIR}" 2>/dev/null || true
    fi

    # Detach any lingering loopback devices created by kpartx
    if [[ -n "${LOOP_DEV:-}" ]]; then
        kpartx -d "${LOOP_DEV}" 2>/dev/null || true
        losetup -d "${LOOP_DEV}" 2>/dev/null || true
        log_info "Detached loopback device ${LOOP_DEV}"
    fi

    if [[ ${exit_code} -ne 0 ]]; then
        log_error "Cleanup complete. Please investigate the error above."
    fi
}
