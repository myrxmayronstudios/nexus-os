#!/usr/bin/env bash
# Neuxon OS - User Setup Script
# Creates and configures the 'neuxon' user account
set -euo pipefail

echo "=== Neuxon OS User Setup ==="

USERNAME="neuxon"
PASSWORD="neuxon"
HOME_DIR="/home/${USERNAME}"

# Create user if it doesn't exist
if ! id "${USERNAME}" &>/dev/null; then
    useradd -m -s /bin/bash -c "Neuxon OS User" "${USERNAME}"
    echo "[OK] Created user '${USERNAME}'"
else
    echo "[INFO] User '${USERNAME}' already exists"
fi

# Set password
echo "${USERNAME}:${PASSWORD}" | chpasswd
echo "[OK] Password set for '${USERNAME}'"

# Add to groups (create group if missing, skip if group doesn't exist on this system)
GROUPS=(sudo video audio input render netdev plugdev dialout)
for grp in "${GROUPS[@]}"; do
    if getent group "${grp}" &>/dev/null; then
        usermod -aG "${grp}" "${USERNAME}"
        echo "[OK] Added to group '${grp}'"
    else
        echo "[SKIP] Group '${grp}' does not exist"
    fi
done

# Set default shell to /bin/bash
chsh -s /bin/bash "${USERNAME}"

# Create home directory structure
mkdir -p "${HOME_DIR}/.config"
mkdir -p "${HOME_DIR}/.local/bin"
mkdir -p "${HOME_DIR}/.local/share"
echo "[OK] Created home directory structure"

# Configure sudoers entry
# To require a password instead, change NOPASSWD:ALL to ALL
# e.g.: neuxon ALL=(ALL:ALL) ALL
cat > /etc/sudoers.d/010-neuxon << 'SUDOEOF'
# Neuxon OS - User sudo configuration
# This grants passwordless sudo for convenience on a single-user embedded system.
# To require a password, replace "NOPASSWD:ALL" with "ALL"
# e.g.: neuxon ALL=(ALL:ALL) ALL
neuxon ALL=(ALL:ALL) NOPASSWD:ALL
SUDOEOF
chmod 0440 /etc/sudoers.d/010-neuxon
echo "[OK] Configured sudoers (NOPASSWD)"

# Create .bashrc
cat > "${HOME_DIR}/.bashrc" << 'BASHRCEOF'
# ~/.bashrc - Neuxon OS
# Executed for interactive non-login shells

# If not running interactively, don't do anything
case $- in
    *i*) ;;
      *) return;;
esac

# History configuration
HISTCONTROL=ignoreboth
HISTSIZE=1000
HISTFILESIZE=2000
shopt -s histappend

# Check window size after each command
shopt -s checkwinsize

# Monochrome prompt: [user@hostname:directory]$
PS1='\[\e[0;37m\][\u@\h:\w]\$\[\e[0m\] '

# Aliases
alias ls='ls --color=auto'
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'
alias df='df -h'
alias du='du -h'
alias free='free -h'

# PATH - include user local bin and system local bin
export PATH="${HOME}/.local/bin:/usr/local/bin:${PATH}"

# Source bash-completion if available
if ! shopt -oq posix; then
    if [ -f /usr/share/bash-completion/bash_completion ]; then
        . /usr/share/bash-completion/bash_completion
    elif [ -f /etc/bash_completion ]; then
        . /etc/bash_completion
    fi
fi

# Run fastfetch on interactive non-login shell, but not on tty1
# (tty1 is reserved for the desktop session / display manager)
if command -v fastfetch &>/dev/null; then
    current_tty=$(tty 2>/dev/null || echo "")
    if [[ "${current_tty}" != "/dev/tty1" ]]; then
        fastfetch
    fi
    unset current_tty
fi
BASHRCEOF
echo "[OK] Created .bashrc"

# Set ownership of everything in home directory
chown -R "${USERNAME}:${USERNAME}" "${HOME_DIR}"
echo "[OK] Set ownership of ${HOME_DIR} to ${USERNAME}:${USERNAME}"

echo "=== User setup complete ==="
