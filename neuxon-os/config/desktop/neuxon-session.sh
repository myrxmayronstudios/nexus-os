#!/usr/bin/env bash
# ============================================================================
# Neuxon OS Desktop Session Launcher
# Platform: Raspberry Pi 3B+ (ARM64 Cortex-A53, VideoCore IV vc4-kms-v3d)
# ============================================================================
# Initializes Wayland environment, triggers Neuxon Doctor pre-flight check,
# silences TTY console bleed, and runs labwc inside a dbus session.
# ============================================================================

set -euo pipefail

# --- Silence TTY Bleed ---
clear
tput civis 2>/dev/null || true

# --- XDG Base Directories ---
export XDG_CONFIG_HOME="${HOME}/.config"
export XDG_DATA_HOME="${HOME}/.local/share"
export XDG_CACHE_HOME="${HOME}/.cache"
export XDG_STATE_HOME="${HOME}/.local/state"
export XDG_RUNTIME_DIR="/run/user/$(id -u)"

# --- Create runtime directory if it does not exist ---
if [ ! -d "${XDG_RUNTIME_DIR}" ]; then
    mkdir -p "${XDG_RUNTIME_DIR}" 2>/dev/null || sudo mkdir -p "${XDG_RUNTIME_DIR}"
    sudo chown "$(id -u):$(id -g)" "${XDG_RUNTIME_DIR}" 2>/dev/null || true
    sudo chmod 0700 "${XDG_RUNTIME_DIR}" 2>/dev/null || true
fi

# --- Wayland Session Type ---
export XDG_SESSION_TYPE=wayland
export XDG_CURRENT_DESKTOP=wlroots
export XDG_SESSION_DESKTOP=labwc

# --- Toolkit Wayland Backends ---
export GDK_BACKEND=wayland,x11
export QT_QPA_PLATFORM="wayland;xcb"
export QT_WAYLAND_DISABLE_WINDOWDECORATION=1
export SDL_VIDEODRIVER=wayland
export MOZ_ENABLE_WAYLAND=1
export CLUTTER_BACKEND=wayland
export ECORE_EVAS_ENGINE=wayland_shm
export ELECTRON_OZONE_PLATFORM_HINT=wayland
export TERM=foot

# --- VideoCore IV Workarounds (BCM2837B0 / RPi 3B+) ---
export WLR_NO_HARDWARE_CURSORS=1
export WLR_DRM_NO_ATOMIC=1
export WLR_RENDERER=pixman

# --- GTK Theme & Cursor ---
export GTK_THEME=Adwaita:dark
export XCURSOR_THEME=Adwaita
export XCURSOR_SIZE=16

# --- Pre-Flight Autonomous Self-Healing Diagnostic ---
if [ -x /usr/local/bin/neuxon-doctor ]; then
    /usr/local/bin/neuxon-doctor || true
fi

# --- Start Compositor with Clean Log Redirection (No TTY Bleed) ---
if command -v dbus-run-session &>/dev/null; then
    exec dbus-run-session -- labwc > /tmp/labwc.log 2>&1
else
    exec labwc > /tmp/labwc.log 2>&1
fi
