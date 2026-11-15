#!/usr/bin/env bash
###############################################################################
# STAGE 03: Desktop Environment Installation
# Runs INSIDE chroot (rootfs is /)
###############################################################################
set -euo pipefail

echo "[STAGE-03] ============================================"
echo "[STAGE-03] Installing desktop environment & Wayland components"
echo "[STAGE-03] ============================================"

export DEBIAN_FRONTEND=noninteractive

# --------------------------------------------------------------------------
# 1. Update package lists
# --------------------------------------------------------------------------
echo "[STAGE-03] Running apt-get update ..."
apt-get update -y

# --------------------------------------------------------------------------
# 2. Install Wayland and Labwc
# --------------------------------------------------------------------------
echo "[STAGE-03] Installing Labwc and Wayland components ..."
apt-get install -y --no-install-recommends \
    labwc \
    wlr-randr \
    seatd \
    xwayland \
    swaybg \
    swaylock

echo "[STAGE-03] Labwc and Wayland installed"

# --------------------------------------------------------------------------
# 3. Install Waybar & Audio Subsystem
# --------------------------------------------------------------------------
echo "[STAGE-03] Installing Waybar & Audio Subsystem ..."
apt-get install -y --no-install-recommends \
    waybar \
    fonts-font-awesome \
    pipewire \
    wireplumber

echo "[STAGE-03] Waybar and audio installed"

# --------------------------------------------------------------------------
# 4. Install Fuzzel & Foot terminal
# --------------------------------------------------------------------------
echo "[STAGE-03] Installing Fuzzel and Foot terminal ..."
apt-get install -y --no-install-recommends \
    fuzzel \
    foot

echo "[STAGE-03] Fuzzel and Foot installed"

# --------------------------------------------------------------------------
# 5. Install supporting utilities, polkit, and image tools
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
    shared-mime-info \
    librsvg2-bin \
    imagemagick \
    mpv

echo "[STAGE-03] Supporting packages installed"

# --------------------------------------------------------------------------
# 6. Install fonts & themes
# --------------------------------------------------------------------------
echo "[STAGE-03] Installing fonts & theme icons ..."
apt-get install -y --no-install-recommends \
    fonts-jetbrains-mono \
    fonts-dejavu-core \
    fonts-hack \
    fonts-noto-core \
    papirus-icon-theme \
    adwaita-icon-theme \
    libgtk-3-0 \
    gtk-update-icon-cache

echo "[STAGE-03] Fonts and themes installed"

# --------------------------------------------------------------------------
# 7. Install Mesa / GPU drivers for VideoCore IV
# --------------------------------------------------------------------------
echo "[STAGE-03] Installing Mesa/GPU drivers for VideoCore IV ..."
apt-get install -y --no-install-recommends \
    mesa-utils \
    libgl1-mesa-dri

echo "[STAGE-03] Mesa/GPU drivers installed"

# --------------------------------------------------------------------------
# 7b. Install Chromium Browser & GUI Utilities
# --------------------------------------------------------------------------
echo "[STAGE-03] Installing Chromium browser, GUI file manager, and editor ..."
apt-get install -y --no-install-recommends \
    chromium \
    pcmanfm \
    mousepad 2>/dev/null || \
apt-get install -y --no-install-recommends \
    pcmanfm \
    mousepad 2>/dev/null || true

echo "[STAGE-03] Browser and GUI utilities provisioned" 

# --------------------------------------------------------------------------
# 8. Set up neuxon user
# --------------------------------------------------------------------------
echo "[STAGE-03] Setting up neuxon user ..."

if ! id -u neuxon &>/dev/null; then
    useradd -m -s /bin/bash -G sudo,video,audio,input,render,netdev,plugdev neuxon
    echo "[STAGE-03] Created user 'neuxon'"
else
    echo "[STAGE-03] User 'neuxon' already exists, ensuring group membership ..."
    usermod -aG sudo,video,audio,input,render,netdev,plugdev neuxon
fi

echo "neuxon:neuxon" | chpasswd
echo "[STAGE-03] Password set for neuxon"

# Passwordless sudo for convenience on embedded appliance
echo "neuxon ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/neuxon
chmod 440 /etc/sudoers.d/neuxon

mkdir -p /home/neuxon/.config /etc/skel/.config
echo "[STAGE-03] User setup complete"

# --------------------------------------------------------------------------
# 9. Copy desktop configuration files (to /home/neuxon and /etc/skel)
# --------------------------------------------------------------------------
echo "[STAGE-03] Copying desktop configuration files ..."

CONFIG_SRC="/tmp/neuxon-config/desktop"

for target_dir in /home/neuxon/.config /etc/skel/.config; do
    mkdir -p "${target_dir}"

    for mod in labwc waybar fuzzel foot gtk-3.0 gtk-4.0 mako btop swaylock starship zellij helix bottom; do
        if [ -d "${CONFIG_SRC}/${mod}" ]; then
            mkdir -p "${target_dir}/${mod}"
            cp -r "${CONFIG_SRC}/${mod}"/* "${target_dir}/${mod}/"
        fi
    done
done

# Install MPV system configuration
mkdir -p /etc/mpv
if [ -f /tmp/neuxon-config/system/mpv/mpv.conf ]; then
    cp /tmp/neuxon-config/system/mpv/mpv.conf /etc/mpv/mpv.conf
    echo "[STAGE-03] Installed /etc/mpv/mpv.conf"
fi

# --------------------------------------------------------------------------
# 10. Install Custom Preloaded Utilities & Desktop Launchers
# --------------------------------------------------------------------------
echo "[STAGE-03] Installing Neuxon utilities and launchers..."

for util in neuxon-control neuxon-hud neuxon-browser neuxon-btop-gadget neuxon-zram-status neuxon-volume-status; do
    if [ -f "${CONFIG_SRC}/${util}" ]; then
        cp "${CONFIG_SRC}/${util}" "/usr/local/bin/${util}"
        chmod 755 "/usr/local/bin/${util}"
        echo "[STAGE-03] Installed /usr/local/bin/${util}"
    fi
done

# Install all .desktop application launchers into /usr/share/applications/
mkdir -p /usr/share/applications
for df in "${CONFIG_SRC}"/*.desktop "${CONFIG_SRC}/applications"/*.desktop; do
    if [ -f "${df}" ]; then
        cp "${df}" /usr/share/applications/
        echo "[STAGE-03] Installed $(basename "${df}")"
    fi
done

# --------------------------------------------------------------------------
# 11. Install neuxon-session.sh
# --------------------------------------------------------------------------
echo "[STAGE-03] Installing neuxon-session.sh ..."

if [ -f "${CONFIG_SRC}/neuxon-session.sh" ]; then
    cp "${CONFIG_SRC}/neuxon-session.sh" /usr/local/bin/neuxon-session.sh
else
    cat > /usr/local/bin/neuxon-session.sh << 'SESSIONEOF'
#!/usr/bin/env bash
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
mkdir -p "${XDG_RUNTIME_DIR}"
chmod 0700 "${XDG_RUNTIME_DIR}"

export XDG_SESSION_TYPE=wayland
export XDG_CURRENT_DESKTOP=labwc
export XDG_SESSION_DESKTOP=labwc
export MESA_GL_VERSION_OVERRIDE=3.3
export WLR_RENDERER=gles2

if command -v dbus-run-session &>/dev/null; then
    exec dbus-run-session -- labwc
else
    exec labwc
fi
SESSIONEOF
fi

chmod 755 /usr/local/bin/neuxon-session.sh
echo "[STAGE-03] neuxon-session.sh installed"

# --------------------------------------------------------------------------
# 12. Configure auto-start on tty1 (.bash_profile)
# --------------------------------------------------------------------------
echo "[STAGE-03] Configuring auto-start on tty1 ..."

cat > /home/neuxon/.bash_profile << 'EOF'
# ~/.bash_profile - Neuxon OS
if [ -f "${HOME}/.bashrc" ]; then
    . "${HOME}/.bashrc"
fi

# Auto-start Wayland session on tty1
if [ -z "${WAYLAND_DISPLAY}" ] && [ "$(tty)" = "/dev/tty1" ]; then
    exec /usr/local/bin/neuxon-session.sh
fi
EOF

cp /home/neuxon/.bash_profile /etc/skel/.bash_profile

# --------------------------------------------------------------------------
# 13. Configure .bashrc (Starship, Fastfetch, Zoxide, Aliases)
# --------------------------------------------------------------------------
echo "[STAGE-03] Configuring .bashrc with Starship & Fastfetch..."

cat > /home/neuxon/.bashrc << 'BASHRCEOF'
# ~/.bashrc - Neuxon OS
case $- in
    *i*) ;;
      *) return;;
esac

HISTCONTROL=ignoreboth
HISTSIZE=2000
HISTFILESIZE=4000
shopt -s histappend checkwinsize

# Colored commands
alias ls='ls --color=auto'
alias grep='grep --color=auto'
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'

# Modern CLI alternatives
if command -v eza &>/dev/null; then
    alias ls='eza --icons=never'
    alias ll='eza -lh --icons=never'
    alias la='eza -a --icons=never'
fi

if command -v bat &>/dev/null; then
    alias cat='bat --paging=never'
fi

if command -v fd &>/dev/null; then
    alias find='fd'
fi

if command -v rg &>/dev/null; then
    alias grep='rg'
fi

if command -v micro &>/dev/null; then
    export EDITOR=micro
    export VISUAL=micro
elif command -v hx &>/dev/null; then
    export EDITOR=hx
    export VISUAL=hx
fi

# Initialize Zoxide
if command -v zoxide &>/dev/null; then
    eval "$(zoxide init bash)"
fi

# Initialize Starship Prompt or Fallback
if command -v starship &>/dev/null; then
    eval "$(starship init bash)"
else
    PS1='\[\033[1;37m\]◆ \[\033[38;5;245m\]\u@neuxon \[\033[1;37m\]\w \[\033[0m\]\$ '
fi

# Fastfetch banner on interactive non-tty1 terminal
if command -v fastfetch &>/dev/null; then
    if [ "$(tty)" != "/dev/tty1" ]; then
        fastfetch
    fi
fi
BASHRCEOF

cp /home/neuxon/.bashrc /etc/skel/.bashrc

# --------------------------------------------------------------------------
# 14. Autologin on tty1
# --------------------------------------------------------------------------
echo "[STAGE-03] Configuring autologin on tty1 ..."
mkdir -p /etc/systemd/system/getty@tty1.service.d

cat > /etc/systemd/system/getty@tty1.service.d/override.conf << 'EOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin neuxon --noclear %I $TERM
EOF

# --------------------------------------------------------------------------
# 15. Set Ownership & Finalize Caches
# --------------------------------------------------------------------------
echo "[STAGE-03] Setting ownership of /home/neuxon ..."
chown -R neuxon:neuxon /home/neuxon
chmod 700 /home/neuxon

update-desktop-database /usr/share/applications 2>/dev/null || true
gtk-update-icon-cache /usr/share/icons/Papirus-Dark 2>/dev/null || true

apt-get clean
rm -rf /var/lib/apt/lists/*

echo "[STAGE-03] ============================================"
echo "[STAGE-03] Desktop environment installation completed"
echo "[STAGE-03] ============================================"
