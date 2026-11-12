#!/usr/bin/env bash
# ============================================================================
# Neuxon OS Desktop Session Launcher
# ============================================================================
# This script initializes the Wayland environment and launches the labwc
# compositor. It is intended to be called from a TTY login or a display
# manager session entry.
# ============================================================================

set -euo pipefail

# --- XDG Base Directories ---
export XDG_CONFIG_HOME="${HOME}/.config"
export XDG_DATA_HOME="${HOME}/.local/share"
export XDG_CACHE_HOME="${HOME}/.cache"
export XDG_STATE_HOME="${HOME}/.local/state"
export XDG_RUNTIME_DIR="/run/user/$(id -u)"

# --- Create runtime directory if it does not exist ---
if [ ! -d "${XDG_RUNTIME_DIR}" ]; then
    sudo mkdir -p "${XDG_RUNTIME_DIR}"
    sudo chown "$(id -u):$(id -g)" "${XDG_RUNTIME_DIR}"
    sudo chmod 0700 "${XDG_RUNTIME_DIR}"
fi

# --- Wayland Session Type ---
export XDG_SESSION_TYPE=wayland
export XDG_CURRENT_DESKTOP=wlroots
export XDG_SESSION_DESKTOP=labwc

# --- Toolkit Wayland Backends ---
export GDK_BACKEND=wayland
export QT_QPA_PLATFORM=wayland
export QT_WAYLAND_DISABLE_WINDOWDECORATION=1
export SDL_VIDEODRIVER=wayland
export MOZ_ENABLE_WAYLAND=1
export CLUTTER_BACKEND=wayland
export ECORE_EVAS_ENGINE=wayland_shm

# --- VideoCore IV Workarounds (BCM2837B0 / RPi 3B+) ---
export WLR_NO_HARDWARE_CURSORS=1
export WLR_DRM_NO_ATOMIC=1
export WLR_RENDERER=pixman

# --- GTK Theme ---
export GTK_THEME=Adwaita:dark

# --- Cursor ---
export XCURSOR_THEME=Adwaita
export XCURSOR_SIZE=16

# --- Start the compositor ---
exec labwc
