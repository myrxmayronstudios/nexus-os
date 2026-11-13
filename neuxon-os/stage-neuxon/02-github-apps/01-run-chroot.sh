#!/usr/bin/env bash
###############################################################################
# STAGE 02: GitHub Applications Provisioning
# Runs INSIDE chroot (rootfs is /)
###############################################################################
set -euo pipefail

echo "[STAGE-02] ============================================"
echo "[STAGE-02] Installing GitHub-sourced ARM64 applications"
echo "[STAGE-02] ============================================"

export DEBIAN_FRONTEND=noninteractive

# --------------------------------------------------------------------------
# 1. Install prerequisites for fetching and unpacking assets
# --------------------------------------------------------------------------
echo "[STAGE-02] Installing build & unpacking tools..."
apt-get update -qq
apt-get install -y --no-install-recommends \
    curl \
    wget \
    jq \
    unzip \
    tar \
    xz-utils \
    file \
    ca-certificates \
    libglib2.0-0 \
    fdisk

echo "[STAGE-02] Prerequisite packages installed"

# --------------------------------------------------------------------------
# 2. Resilient GitHub Release Installer Function
# --------------------------------------------------------------------------
# install_github_release <owner/repo> [bin_name] [custom_asset_pattern]
install_github_release() {
    local repo="$1"
    local bin_name="${2:-$(basename "${repo}")}"
    local custom_pattern="${3:-}"

    echo "[STAGE-02] ----------------------------------------------------"
    echo "[STAGE-02] Resolving GitHub release: ${repo} (bin: ${bin_name})"
    echo "[STAGE-02] ----------------------------------------------------"

    local auth_header=()
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        auth_header=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
        echo "[STAGE-02] Using authenticated GitHub API request"
    fi

    local api_url="https://api.github.com/repos/${repo}/releases/latest"
    local release_json=""
    release_json=$(curl -sSL --fail "${auth_header[@]}" -H "Accept: application/vnd.github+json" "${api_url}" 2>/dev/null || true)

    if [[ -z "${release_json}" ]] || ! echo "${release_json}" | jq -e '.tag_name' >/dev/null 2>&1; then
        echo "[STAGE-02] WARNING: Failed to fetch latest release metadata for ${repo}."
        echo "[STAGE-02] WARNING: Continuing build without ${bin_name}..."
        return 0
    fi

    local tag_name
    tag_name=$(echo "${release_json}" | jq -r '.tag_name // "latest"')
    echo "[STAGE-02] Discovered release: ${tag_name}"

    # Asset pattern candidates for aarch64 / arm64 Linux
    local -a patterns=()
    if [[ -n "${custom_pattern}" ]]; then
        patterns+=("${custom_pattern}")
    fi
    patterns+=(
        "(aarch64|arm64).*\\.deb$"
        "(aarch64-unknown-linux-musl|aarch64-unknown-linux-gnu).*\\.(tar\\.gz|tar\\.xz|zip)$"
        "(linux[-_]arm64|linux[-_]aarch64|arm64[-_]linux|aarch64[-_]linux).*\\.(tar\\.gz|tar\\.xz|zip)$"
        "(aarch64|arm64).*\\.(tar\\.gz|tar\\.xz|zip)$"
        "(linux[-_]arm64|linux[-_]aarch64|arm64|aarch64)$"
    )

    local download_url=""
    local asset_name=""

    for pat in "${patterns[@]}"; do
        local match
        match=$(echo "${release_json}" | jq -r --arg p "${pat}" '
            [.assets[] | select(.name | test($p; "i"))] | .[0] // empty | "\(.browser_download_url) \(.name)"
        ' 2>/dev/null || true)

        if [[ -n "${match}" ]]; then
            download_url=$(echo "${match}" | awk '{print $1}')
            asset_name=$(echo "${match}" | awk '{print $2}')
            break
        fi
    done

    if [[ -z "${download_url}" ]]; then
        echo "[STAGE-02] WARNING: No matching ARM64 asset for ${repo}. Assets found:"
        echo "${release_json}" | jq -r '.assets[].name' 2>/dev/null | head -n 10 | sed 's/^/  - /' || true
        return 0
    fi

    echo "[STAGE-02] Downloading ${asset_name} ..."
    local tmp_dir
    tmp_dir=$(mktemp -d "/tmp/gh_${bin_name}_XXXXXX")
    local dest_file="${tmp_dir}/${asset_name}"

    if ! curl -sSL --fail "${auth_header[@]}" -o "${dest_file}" "${download_url}"; then
        echo "[STAGE-02] WARNING: Download failed from ${download_url}. Skipping."
        rm -rf "${tmp_dir}"
        return 0
    fi

    # Handle installation by archive format
    case "${asset_name}" in
        *.deb)
            echo "[STAGE-02] Installing .deb package..."
            dpkg -i "${dest_file}" 2>/dev/null || apt-get install -f -y --no-install-recommends
            ;;
        *.tar.gz|*.tgz)
            echo "[STAGE-02] Unpacking .tar.gz archive..."
            tar -xzf "${dest_file}" -C "${tmp_dir}"
            ;;
        *.tar.xz)
            echo "[STAGE-02] Unpacking .tar.xz archive..."
            tar -xJf "${dest_file}" -C "${tmp_dir}"
            ;;
        *.zip)
            echo "[STAGE-02] Unzipping .zip archive..."
            unzip -q -o "${dest_file}" -d "${tmp_dir}"
            ;;
        *)
            chmod +x "${dest_file}"
            cp "${dest_file}" "/usr/local/bin/${bin_name}"
            ;;
    esac

    # If it was an archive, locate the binary
    if [[ "${asset_name}" != *.deb ]]; then
        local target_path
        target_path=$(find "${tmp_dir}" -type f -name "${bin_name}" -perm /111 | head -n 1 || true)
        if [[ -z "${target_path}" ]]; then
            target_path=$(find "${tmp_dir}" -type f -name "${bin_name}" | head -n 1 || true)
        fi
        if [[ -z "${target_path}" ]]; then
            # Fallback: locate any ELF executable inside the extracted directory
            target_path=$(find "${tmp_dir}" -type f -perm /111 ! -name "*.sh" ! -name "*.so*" | head -n 1 || true)
        fi

        if [[ -n "${target_path}" ]] && [[ -f "${target_path}" ]]; then
            cp "${target_path}" "/usr/local/bin/${bin_name}"
            chmod 755 "/usr/local/bin/${bin_name}"
            echo "[STAGE-02] Installed ${bin_name} to /usr/local/bin/${bin_name}"
        else
            echo "[STAGE-02] WARNING: Could not find binary '${bin_name}' in extracted files from ${asset_name}"
        fi
    fi

    rm -rf "${tmp_dir}"
    return 0
}

# --------------------------------------------------------------------------
# 3. Core Terminal & Shell Apps
# --------------------------------------------------------------------------
echo "[STAGE-02] Provisioning Core Terminal & Shell apps..."

# fastfetch (system info)
install_github_release "fastfetch-cli/fastfetch" "fastfetch" "(linux-aarch64|aarch64.*linux).*\\.deb$"

# starship (monochrome prompt)
install_github_release "starship/starship" "starship" "aarch64-unknown-linux-musl.*\\.tar\\.gz$"

# zellij (terminal workspace multiplexer)
install_github_release "zellij-org/zellij" "zellij" "aarch64-unknown-linux-musl.*\\.tar\\.gz$"

# zoxide (smarter cd command)
install_github_release "ajeetdsouza/zoxide" "zoxide" "aarch64-unknown-linux-musl.*\\.tar\\.gz$"

# fzf (fuzzy finder)
install_github_release "junegunn/fzf" "fzf" "linux_arm64.*\\.tar\\.gz$"

# bat (syntax-highlighted cat)
install_github_release "sharkdp/bat" "bat" "aarch64-unknown-linux-musl.*\\.tar\\.gz$"

# eza (modern ls replacement)
install_github_release "eza-community/eza" "eza" "aarch64-unknown-linux-musl.*\\.tar\\.gz$"

# fd (fast file search)
install_github_release "sharkdp/fd" "fd" "aarch64-unknown-linux-musl.*\\.tar\\.gz$"

# ripgrep (fast text search)
install_github_release "BurntSushi/ripgrep" "rg" "aarch64-unknown-linux-musl.*\\.tar\\.gz$"

# --------------------------------------------------------------------------
# 4. Development, File Management & System Monitoring
# --------------------------------------------------------------------------
echo "[STAGE-02] Provisioning Development & System Monitoring apps..."

# yazi (terminal file manager)
install_github_release "yazi-rs/yazi" "yazi" "aarch64-unknown-linux-musl.*\\.zip$"

# helix (modern modal editor)
install_github_release "helix-editor/helix" "hx" "aarch64-linux.*\\.tar\\.xz$"

# micro (modern terminal editor)
install_github_release "zyedidia/micro" "micro" "linux-arm64.*\\.tar\\.gz$"

# lazygit (terminal git UI)
install_github_release "jesseduffield/lazygit" "lazygit" "Linux_arm64.*\\.tar\\.gz$"

# lazydocker (terminal docker UI)
install_github_release "jesseduffield/lazydocker" "lazydocker" "Linux_arm64.*\\.tar\\.gz$"

# btop (hardware monitor)
install_github_release "aristocratos/btop" "btop" "aarch64-linux-musl.*\\.tbz$"

# bottom (btm lightweight hardware graph)
install_github_release "ClementTsang/bottom" "btm" "aarch64-unknown-linux-musl.*\\.tar\\.gz$"

# --------------------------------------------------------------------------
# 5. Media, Networking, Utilities & Custom Control Center
# --------------------------------------------------------------------------
echo "[STAGE-02] Provisioning Media, Networking & Utilities..."

# kew (ultra-lightweight terminal music player)
install_github_release "ravachol/kew" "kew" "aarch64.*\\.tar\\.gz$"

# croc (encrypted P2P file transfer)
install_github_release "schollz/croc" "croc" "Linux-ARM64.*\\.tar\\.gz$"

# gum (interactive shell scripts & dialogs)
install_github_release "charmbracelet/gum" "gum" "Linux_arm64.*\\.tar\\.gz$"

# min (minimalist web browser)
install_github_release "minbrowser/min" "min" "arm64.*\\.deb$"

# --------------------------------------------------------------------------
# 6. Fallback checks for core CLI utilities
# --------------------------------------------------------------------------
echo "[STAGE-02] Checking fallbacks for essential CLI tools..."
if ! command -v rg &>/dev/null; then
    apt-get install -y --no-install-recommends ripgrep 2>/dev/null || true
fi

if ! command -v fd &>/dev/null; then
    apt-get install -y --no-install-recommends fd-find 2>/dev/null || true
    if command -v fdfind &>/dev/null && [ ! -e /usr/local/bin/fd ]; then
        ln -sf "$(command -v fdfind)" /usr/local/bin/fd
    fi
fi

if ! command -v bat &>/dev/null; then
    apt-get install -y --no-install-recommends bat 2>/dev/null || true
    if command -v batcat &>/dev/null && [ ! -e /usr/local/bin/bat ]; then
        ln -sf "$(command -v batcat)" /usr/local/bin/bat
    fi
fi

if ! command -v fzf &>/dev/null; then
    apt-get install -y --no-install-recommends fzf 2>/dev/null || true
fi

# --------------------------------------------------------------------------
# 7. Install Desktop Shortcuts for Preloaded Applications
# --------------------------------------------------------------------------
echo "[STAGE-02] Installing application desktop launchers..."
mkdir -p /usr/share/applications

# Neuxon Control Center
if [ -f /tmp/neuxon-config/desktop/neuxon-control.desktop ]; then
    cp /tmp/neuxon-config/desktop/neuxon-control.desktop /usr/share/applications/
fi

# Yazi
cat > /usr/share/applications/yazi.desktop << 'EOF'
[Desktop Entry]
Name=Yazi File Manager
Comment=Blazing-fast terminal file manager
Exec=foot -T "Yazi" -e yazi
Icon=system-file-manager
Terminal=false
Type=Application
Categories=System;FileManager;Utility;
EOF

# BTOP
cat > /usr/share/applications/btop.desktop << 'EOF'
[Desktop Entry]
Name=BTOP Monitor
Comment=Resource monitor in monochrome
Exec=foot -T "BTOP Monitor" -e btop
Icon=utilities-system-monitor
Terminal=false
Type=Application
Categories=System;Monitor;
EOF

# Bottom (BTM)
cat > /usr/share/applications/btm.desktop << 'EOF'
[Desktop Entry]
Name=Bottom Hardware Graph
Comment=Lightweight terminal resource graph
Exec=foot -T "Bottom (BTM)" -e btm
Icon=utilities-system-monitor
Terminal=false
Type=Application
Categories=System;Monitor;
EOF

# Micro
cat > /usr/share/applications/micro.desktop << 'EOF'
[Desktop Entry]
Name=Micro Editor
Comment=Terminal text editor
Exec=foot -T "Micro Editor" -e micro %F
Icon=text-editor
Terminal=false
Type=Application
Categories=Utility;TextEditor;
EOF

# Helix
cat > /usr/share/applications/helix.desktop << 'EOF'
[Desktop Entry]
Name=Helix Editor
Comment=Post-modern modal text editor
Exec=foot -T "Helix Editor" -e hx %F
Icon=text-editor
Terminal=false
Type=Application
Categories=Development;TextEditor;
EOF

# LazyGit
cat > /usr/share/applications/lazygit.desktop << 'EOF'
[Desktop Entry]
Name=LazyGit
Comment=Terminal UI for git commands
Exec=foot -T "LazyGit" -e lazygit
Icon=git
Terminal=false
Type=Application
Categories=Development;
EOF

# Kew Music Player
cat > /usr/share/applications/kew.desktop << 'EOF'
[Desktop Entry]
Name=Kew Music Player
Comment=Lightweight terminal music player
Exec=foot -T "Kew Music Player" -e kew
Icon=multimedia-audio-player
Terminal=false
Type=Application
Categories=AudioVideo;Audio;Player;
EOF

# Update desktop database
update-desktop-database /usr/share/applications 2>/dev/null || true

# --------------------------------------------------------------------------
# 8. Clean up
# --------------------------------------------------------------------------
apt-get clean
rm -rf /var/lib/apt/lists/* /tmp/gh_*

echo "[STAGE-02] ============================================"
echo "[STAGE-02] GitHub Applications provisioning completed"
echo "[STAGE-02] ============================================"
