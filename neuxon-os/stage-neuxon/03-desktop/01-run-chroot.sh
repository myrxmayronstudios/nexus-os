#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# STAGE 03: Desktop Environment Installation
# Runs INSIDE chroot (rootfs is /)
# ============================================================================

echo "[STAGE-03] ============================================"
echo "[STAGE-03] Installing desktop environment"
echo "[STAGE-03] ============================================"

export DEBIAN_FRONTEND=noninteractive

# --------------------------------------------------------------------------
# Update package lists
# --------------------------------------------------------------------------
echo "[STAGE-03] Running apt-get update ..."
apt-get update -y

# --------------------------------------------------------------------------
# Install Wayland and Labwc
# --------------------------------------------------------------------------
echo "[STAGE-03] Installing Labwc and Wayland components ..."
apt-get install -y --no-install-recommends \
    labwc \
    wlr-randr \
    seatd \
    xwayland

echo "[STAGE-03] Labwc and Wayland installed"

# --------------------------------------------------------------------------
# Install Waybar
# --------------------------------------------------------------------------
echo "[STAGE-03] Installing Waybar ..."
apt-get install -y --no-install-recommends \
    waybar \
    fonts-font-awesome

echo "[STAGE-03] Waybar installed"

# --------------------------------------------------------------------------
# Install Fuzzel (application launcher)
# --------------------------------------------------------------------------
echo "[STAGE-03] Installing Fuzzel ..."
apt-get install -y --no-install-recommends \
    fuzzel

echo "[STAGE-03] Fuzzel installed"

# --------------------------------------------------------------------------
# Install Foot terminal
# --------------------------------------------------------------------------
echo "[STAGE-03] Installing Foot terminal ..."
apt-get install -y --no-install-recommends \
    foot

echo "[STAGE-03] Foot installed"

# --------------------------------------------------------------------------
# Install supporting packages
# --------------------------------------------------------------------------
echo "[STAGE-03] Installing supporting packages ..."
apt-get install -y --no-install-recommends \
    grim \
    slurp \
    wl-clipboard \
    libnotify-bin \
    mako-notifier \
    polkitd \
    pkexec \
    dbus-x11 \
    xdg-utils \
    desktop-file-utils \
    shared-mime-info

echo "[STAGE-03] Supporting packages installed"

# --------------------------------------------------------------------------
# Install fonts (minimal set)
# --------------------------------------------------------------------------
echo "[STAGE-03] Installing fonts ..."
apt-get install -y --no-install-recommends \
    fonts-dejavu-core \
    fonts-hack \
    fonts-noto-core

echo "[STAGE-03] Fonts installed"

# --------------------------------------------------------------------------
# Install GTK3 and basic GUI libraries
# --------------------------------------------------------------------------
echo "[STAGE-03] Installing GTK3 and GUI libraries ..."
apt-get install -y --no-install-recommends \
    libgtk-3-0 \
    gtk-update-icon-cache \
    adwaita-icon-theme

echo "[STAGE-03] GTK3 and GUI libraries installed"

# --------------------------------------------------------------------------
# Install Mesa/GPU drivers for VideoCore IV (vc4)
# --------------------------------------------------------------------------
echo "[STAGE-03] Installing Mesa/GPU drivers ..."
apt-get install -y --no-install-recommends \
    mesa-utils \
    libgl1-mesa-dri

echo "[STAGE-03] Mesa/GPU drivers installed"

# --------------------------------------------------------------------------
# Create neuxon user (if not exists)
# --------------------------------------------------------------------------
echo "[STAGE-03] Setting up neuxon user ..."

if ! id -u neuxon &>/dev/null; then
    useradd -m -s /bin/bash -G sudo,video,audio,input,render,netdev,plugdev neuxon
    echo "[STAGE-03] Created user 'neuxon'"
else
    echo "[STAGE-03] User 'neuxon' already exists, ensuring group membership ..."
    usermod -aG sudo,video,audio,input,render,netdev,plugdev neuxon
fi

# Set password
echo "neuxon:neuxon" | chpasswd
echo "[STAGE-03] Password set for neuxon"

# Allow neuxon to use sudo without password (for convenience on embedded device)
echo "neuxon ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/neuxon
chmod 440 /etc/sudoers.d/neuxon
echo "[STAGE-03] Sudo configured for neuxon"

# Ensure home directory exists
mkdir -p /home/neuxon
echo "[STAGE-03] User setup complete"

# --------------------------------------------------------------------------
# Copy desktop configuration files
# --------------------------------------------------------------------------
echo "[STAGE-03] Copying desktop configuration files ..."

CONFIG_SRC="/tmp/neuxon-config/desktop"
CONFIG_DST="/home/neuxon/.config"

mkdir -p "${CONFIG_DST}"

# Labwc config
if [ -d "${CONFIG_SRC}/labwc" ]; then
    mkdir -p "${CONFIG_DST}/labwc"
    cp -r "${CONFIG_SRC}/labwc"/* "${CONFIG_DST}/labwc/"
    echo "[STAGE-03]   Installed labwc config"
else
    echo "[STAGE-03]   WARNING: ${CONFIG_SRC}/labwc not found"
fi

# Waybar config
if [ -d "${CONFIG_SRC}/waybar" ]; then
    mkdir -p "${CONFIG_DST}/waybar"
    cp -r "${CONFIG_SRC}/waybar"/* "${CONFIG_DST}/waybar/"
    echo "[STAGE-03]   Installed waybar config"
else
    echo "[STAGE-03]   WARNING: ${CONFIG_SRC}/waybar not found"
fi

# Fuzzel config
if [ -d "${CONFIG_SRC}/fuzzel" ]; then
    mkdir -p "${CONFIG_DST}/fuzzel"
    cp -r "${CONFIG_SRC}/fuzzel"/* "${CONFIG_DST}/fuzzel/"
    echo "[STAGE-03]   Installed fuzzel config"
else
    echo "[STAGE-03]   WARNING: ${CONFIG_SRC}/fuzzel not found"
fi

# Foot config
if [ -d "${CONFIG_SRC}/foot" ]; then
    mkdir -p "${CONFIG_DST}/foot"
    cp -r "${CONFIG_SRC}/foot"/* "${CONFIG_DST}/foot/"
    echo "[STAGE-03]   Installed foot config"
else
    echo "[STAGE-03]   WARNING: ${CONFIG_SRC}/foot not found"
fi

# GTK-3.0 config
if [ -d "${CONFIG_SRC}/gtk-3.0" ]; then
    mkdir -p "${CONFIG_DST}/gtk-3.0"
    cp -r "${CONFIG_SRC}/gtk-3.0"/* "${CONFIG_DST}/gtk-3.0/"
    echo "[STAGE-03]   Installed gtk-3.0 config"
else
    echo "[STAGE-03]   WARNING: ${CONFIG_SRC}/gtk-3.0 not found"
fi

# GTK-4.0 config
if [ -d "${CONFIG_SRC}/gtk-4.0" ]; then
    mkdir -p "${CONFIG_DST}/gtk-4.0"
    cp -r "${CONFIG_SRC}/gtk-4.0"/* "${CONFIG_DST}/gtk-4.0/"
    echo "[STAGE-03]   Installed gtk-4.0 config"
else
    echo "[STAGE-03]   WARNING: ${CONFIG_SRC}/gtk-4.0 not found"
fi

echo "[STAGE-03] Desktop configuration files installed"

# --------------------------------------------------------------------------
# Install neuxon-session.sh
# --------------------------------------------------------------------------
echo "[STAGE-03] Installing neuxon-session.sh ..."

if [ -f "${CONFIG_SRC}/neuxon-session.sh" ]; then
    cp "${CONFIG_SRC}/neuxon-session.sh" /usr/local/bin/neuxon-session.sh
elif [ -f "/tmp/neuxon-config/neuxon-session.sh" ]; then
    cp "/tmp/neuxon-config/neuxon-session.sh" /usr/local/bin/neuxon-session.sh
else
    # Create a default session script if none provided
    cat > /usr/local/bin/neuxon-session.sh << 'SESSIONEOF'
#!/usr/bin/env bash
# Neuxon Desktop Session Launcher

# Set XDG runtime directory
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
mkdir -p "${XDG_RUNTIME_DIR}"
chmod 0700 "${XDG_RUNTIME_DIR}"

# Set Wayland-specific environment
export XDG_SESSION_TYPE=wayland
export XDG_CURRENT_DESKTOP=labwc
export XDG_SESSION_DESKTOP=labwc

# GPU driver hints for RPi
export MESA_GL_VERSION_OVERRIDE=3.3
export WLR_RENDERER=gles2

# DBus session
if command -v dbus-run-session &>/dev/null; then
    exec dbus-run-session -- labwc -s "waybar & mako"
else
    exec labwc -s "waybar & mako"
fi
SESSIONEOF
    echo "[STAGE-03]   Created default neuxon-session.sh"
fi

chmod +x /usr/local/bin/neuxon-session.sh
echo "[STAGE-03] neuxon-session.sh installed"

# --------------------------------------------------------------------------
# Create .bash_profile for auto-start on tty1
# --------------------------------------------------------------------------
echo "[STAGE-03] Configuring auto-start on tty1 ..."

cat > /home/neuxon/.bash_profile << 'EOF'
# ~/.bash_profile - Neuxon OS

# Source .bashrc if it exists
if [ -f "${HOME}/.bashrc" ]; then
    . "${HOME}/.bashrc"
fi

# Auto-start Wayland session on tty1
if [ -z "${WAYLAND_DISPLAY}" ] && [ "$(tty)" = "/dev/tty1" ]; then
    exec /usr/local/bin/neuxon-session.sh
fi
EOF

echo "[STAGE-03] .bash_profile created"

# --------------------------------------------------------------------------
# Configure .bashrc with fastfetch
# --------------------------------------------------------------------------
echo "[STAGE-03] Configuring .bashrc ..."

cat > /home/neuxon/.bashrc << 'BASHRCEOF'
# ~/.bashrc - Neuxon OS

# If not running interactively, don't do anything
case $- in
    *i*) ;;
      *) return;;
esac

# History settings
HISTCONTROL=ignoreboth
HISTSIZE=1000
HISTFILESIZE=2000
shopt -s histappend

# Check window size after each command
shopt -s checkwinsize

# Enable color support
if [ -x /usr/bin/dircolors ]; then
    test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
    alias ls='ls --color=auto'
    alias grep='grep --color=auto'
    alias fgrep='fgrep --color=auto'
    alias egrep='egrep --color=auto'
fi

# Aliases
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'

# Use fd instead of find if available
if command -v fd &>/dev/null; then
    alias find='fd'
fi

# Use rg instead of grep for searching if available
if command -v rg &>/dev/null; then
    alias search='rg'
fi

# Use micro as default editor if available
if command -v micro &>/dev/null; then
    export EDITOR=micro
    export VISUAL=micro
elif command -v nano &>/dev/null; then
    export EDITOR=nano
    export VISUAL=nano
fi

# Custom prompt
PS1='\[\033[38;5;245m\]\u\[\033[0m\]@\[\033[1;37m\]neuxon\[\033[0m\] \[\033[38;5;245m\]\w\[\033[0m\] \$ '

# Enable bash completion
if ! shopt -oq posix; then
    if [ -f /usr/share/bash-completion/bash_completion ]; then
        . /usr/share/bash-completion/bash_completion
    elif [ -f /etc/bash_completion ]; then
        . /etc/bash_completion
    fi
fi

# Display fastfetch on non-tty1 interactive shells
if command -v fastfetch &>/dev/null; then
    if [ "$(tty)" != "/dev/tty1" ]; then
        fastfetch
    fi
fi
BASHRCEOF

echo "[STAGE-03] .bashrc configured"

# --------------------------------------------------------------------------
# Configure autologin on tty1
# --------------------------------------------------------------------------
echo "[STAGE-03] Configuring autologin on tty1 ..."

mkdir -p /etc/systemd/system/getty@tty1.service.d

cat > /etc/systemd/system/getty@tty1.service.d/override.conf << 'EOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin neuxon --noclear %I $TERM
EOF

echo "[STAGE-03] Autologin configured for tty1"

# --------------------------------------------------------------------------
# Set ownership of home directory
# --------------------------------------------------------------------------
echo "[STAGE-03] Setting ownership of /home/neuxon ..."
chown -R neuxon:neuxon /home/neuxon
echo "[STAGE-03] Ownership set"

# --------------------------------------------------------------------------
# Update caches
# --------------------------------------------------------------------------
echo "[STAGE-03] Updating icon cache and desktop database ..."

gtk-update-icon-cache /usr/share/icons/Adwaita 2>/dev/null || true
update-desktop-database /usr/share/applications 2>/dev/null || true

echo "[STAGE-03] Caches updated"

# --------------------------------------------------------------------------
# Clean up
# --------------------------------------------------------------------------
echo "[STAGE-03] Cleaning apt cache ..."
apt-get clean
rm -rf /var/lib/apt/lists/*

echo "[STAGE-03] ============================================"
echo "[STAGE-03] Desktop environment installation completed"
echo "[STAGE-03] ============================================"
