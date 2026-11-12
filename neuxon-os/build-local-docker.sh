#!/usr/bin/env bash
###############################################################################
# build-local-docker.sh — Build Neuxon OS in a Docker container
###############################################################################
# This script builds the Neuxon OS image using Docker, so you do not need an
# ARM host or root access on your workstation.  Docker handles QEMU emulation.
#
# Prerequisites:
#   - Docker installed and running
#   - Internet access (for downloading packages)
#
# Usage:
#   ./build-local-docker.sh
###############################################################################
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
DOCKER_IMAGE="neuxon-os-builder:latest"
CONTAINER_NAME="neuxon-os-build-$$"
OUTPUT_DIR="${SCRIPT_DIR}/output"

# Colors
CLR_RESET="\033[0m"
CLR_GREEN="\033[1;32m"
CLR_CYAN="\033[1;36m"
CLR_RED="\033[1;31m"

_log() { printf "${CLR_GREEN}[DOCKER]${CLR_RESET} ${CLR_CYAN}%s${CLR_RESET} %s\n" "$(date "+%Y-%m-%d %H:%M:%S")" "$*"; }
_err() { printf "${CLR_RED}[DOCKER]${CLR_RESET} ${CLR_CYAN}%s${CLR_RESET} %s\n" "$(date "+%Y-%m-%d %H:%M:%S")" "$*" >&2; }

# ---------------------------------------------------------------------------
# Cleanup on exit
# ---------------------------------------------------------------------------
_cleanup() {
    local ec=$?
    if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}\$" 2>/dev/null; then
        _log "Removing build container: ${CONTAINER_NAME}"
        docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true
    fi
    if [[ ${ec} -ne 0 ]]; then
        _err "Build failed. Check the Docker logs above."
    fi
}
trap _cleanup EXIT

# ---------------------------------------------------------------------------
# Pre-flight
# ---------------------------------------------------------------------------
if ! command -v docker &>/dev/null; then
    _err "Docker is not installed or not in PATH."
    exit 1
fi

if ! docker info &>/dev/null; then
    _err "Docker daemon is not running, or you lack permissions."
    _err "Try: sudo usermod -aG docker \$USER   (then re-login)"
    exit 1
fi

# ---------------------------------------------------------------------------
# Register QEMU binfmt handlers (idempotent, requires --privileged)
# ---------------------------------------------------------------------------
_log "Registering QEMU binfmt handlers for arm64..."
docker run --rm --privileged multiarch/qemu-user-static --reset -p yes 2>/dev/null || {
    _err "Failed to register binfmt handlers. Continuing — they may already be set."
}

# ---------------------------------------------------------------------------
# Build the Docker image
# ---------------------------------------------------------------------------
_log "Building Docker image: ${DOCKER_IMAGE}"
docker build -t "${DOCKER_IMAGE}" "${SCRIPT_DIR}"

# ---------------------------------------------------------------------------
# Create output directory
# ---------------------------------------------------------------------------
mkdir -p "${OUTPUT_DIR}"

# ---------------------------------------------------------------------------
# Run the build inside a container
# ---------------------------------------------------------------------------
_log "Starting build container: ${CONTAINER_NAME}"
_log "This will take a long time (ARM64 cross-compilation)..."

docker run \
    --name "${CONTAINER_NAME}" \
    --privileged \
    -v "${OUTPUT_DIR}:/build/output" \
    "${DOCKER_IMAGE}"

# ---------------------------------------------------------------------------
# List output artifacts
# ---------------------------------------------------------------------------
_log ""
_log "============================================================"
_log " BUILD COMPLETE"
_log "============================================================"
_log "Output directory: ${OUTPUT_DIR}"
_log ""

if [[ -d "${OUTPUT_DIR}" ]]; then
    ls -lh "${OUTPUT_DIR}/" 2>/dev/null | tail -n +2 | while IFS= read -r line; do
        _log "  ${line}"
    done
fi

_log ""
_log "Flash with:"
_log "  xz -dk output/Neuxon-OS-rpi3bplus-arm64.img.xz"
_log "  sudo dd if=output/Neuxon-OS-rpi3bplus-arm64.img of=/dev/sdX bs=4M status=progress conv=fsync"
_log "============================================================"

# Cleanup trap will remove the container
