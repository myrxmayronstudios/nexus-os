#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# STAGE 02: GitHub Applications Provisioning
# Runs INSIDE chroot (rootfs is /)
# ============================================================================

echo "[STAGE-02] ============================================"
echo "[STAGE-02] Installing GitHub-sourced applications"
echo "[STAGE-02] ============================================"

# ╔════════════════════════════════════════════════════════════════╗
# ║  CUSTOM GITHUB REPOS - Add your own "owner/repo" entries     ║
# ║  below and they will be auto-installed during image build.   ║
# ║  Format: "owner/repo"                                        ║
# ║  The script will query GitHub Releases API for the latest    ║
# ║  aarch64/arm64 binary and install it to /usr/local/bin.      ║
# ╚════════════════════════════════════════════════════════════════╝
CUSTOM_GITHUB_REPOS=(
    # "example/tool"
)

# Default applications to install
DEFAULT_GITHUB_REPOS=(
    "fastfetch-cli/fastfetch"
    "aristocratos/btop"
    "zyedidia/micro"
    "jesseduffield/lazygit"
    "sharkdp/fd"
    "BurntSushi/ripgrep"
    "yazi-rs/yazi"
)

# Merge both arrays
ALL_REPOS=("${DEFAULT_GITHUB_REPOS[@]}" "${CUSTOM_GITHUB_REPOS[@]}")

# Track results
declare -A INSTALL_RESULTS
FAILED_APPS=()

export DEBIAN_FRONTEND=noninteractive

# --------------------------------------------------------------------------
# Install build dependencies
# --------------------------------------------------------------------------
echo "[STAGE-02] Installing build dependencies ..."
apt-get update -qq
apt-get install -y --no-install-recommends \
    build-essential \
    cmake \
    git \
    pkg-config \
    jq \
    unzip \
    file

echo "[STAGE-02] Build dependencies installed"

# --------------------------------------------------------------------------
# Helper: Generic GitHub release installer
# --------------------------------------------------------------------------
install_github_app() {
    local repo="$1"
    local repo_name
    repo_name=$(basename "${repo}")

    echo "[STAGE-02] ----------------------------------------"
    echo "[STAGE-02] Processing: ${repo}"
    echo "[STAGE-02] ----------------------------------------"

    # Query latest release
    local api_url="https://api.github.com/repos/${repo}/releases/latest"
    local release_json

    release_json=$(wget -q -O - "${api_url}" 2>/dev/null) || {
        echo "[STAGE-02] ERROR: Failed to query GitHub API for ${repo}"
        FAILED_APPS+=("${repo}")
        INSTALL_RESULTS["${repo}"]="FAILED (API query error)"
        return 1
    }

    local tag_name
    tag_name=$(echo "${release_json}" | jq -r '.tag_name // empty')
    if [ -z "${tag_name}" ]; then
        echo "[STAGE-02] ERROR: No release tag found for ${repo}"
        FAILED_APPS+=("${repo}")
        INSTALL_RESULTS["${repo}"]="FAILED (no release tag)"
        return 1
    fi

    echo "[STAGE-02] Latest release: ${tag_name}"

    # Check for special handler
    local handler_func="install_$(echo "${repo_name}" | tr '-' '_')"
    if declare -f "${handler_func}" > /dev/null 2>&1; then
        echo "[STAGE-02] Using special handler: ${handler_func}"
        "${handler_func}" "${repo}" "${release_json}" "${tag_name}"
        return $?
    fi

    # Generic handler: try to find an appropriate asset
    echo "[STAGE-02] Using generic installer for ${repo_name}"
    generic_install "${repo}" "${release_json}" "${tag_name}" "${repo_name}"
    return $?
}

# --------------------------------------------------------------------------
# Helper: Find and download the best matching asset
# --------------------------------------------------------------------------
find_asset_url() {
    local release_json="$1"
    local pattern="$2"

    echo "${release_json}" | jq -r \
        --arg pat "${pattern}" \
        '[.assets[] | select(.name | test($pat; "i"))] | .[0].browser_download_url // empty'
}

# --------------------------------------------------------------------------
# Generic installer
# --------------------------------------------------------------------------
generic_install() {
    local repo="$1"
    local release_json="$2"
    local tag_name="$3"
    local repo_name="$4"

    # Try .deb first
    local deb_url
    deb_url=$(find_asset_url "${release_json}" "(aarch64|arm64).*\\.deb$")
    if [ -n "${deb_url}" ]; then
        echo "[STAGE-02] Found .deb asset: ${deb_url}"
        local deb_file="/tmp/${repo_name}.deb"
        wget -q -O "${deb_file}" "${deb_url}" && \
        dpkg -i "${deb_file}" && \
        rm -f "${deb_file}" && {
            INSTALL_RESULTS["${repo}"]="${tag_name} (deb)"
            echo "[STAGE-02] Successfully installed ${repo_name} via .deb"
            return 0
        }
        rm -f "${deb_file}"
    fi

    # Try .tar.gz
    local targz_url
    targz_url=$(find_asset_url "${release_json}" "(aarch64|arm64).*linux.*\\.tar\\.gz$")
    if [ -z "${targz_url}" ]; then
        targz_url=$(find_asset_url "${release_json}" "linux.*(aarch64|arm64).*\\.tar\\.gz$")
    fi
    if [ -n "${targz_url}" ]; then
        echo "[STAGE-02] Found .tar.gz asset: ${targz_url}"
        local tmpdir="/tmp/${repo_name}-extract"
        mkdir -p "${tmpdir}"
        wget -q -O "/tmp/${repo_name}.tar.gz" "${targz_url}" && \
        tar -xzf "/tmp/${repo_name}.tar.gz" -C "${tmpdir}" && {
            local binary
            binary=$(find "${tmpdir}" -type f -name "${repo_name}" -o -type f -executable | head -1)
            if [ -n "${binary}" ] && file "${binary}" | grep -qi "executable\|ELF"; then
                cp "${binary}" "/usr/local/bin/${repo_name}"
                chmod +x "/usr/local/bin/${repo_name}"
                INSTALL_RESULTS["${repo}"]="${tag_name} (tar.gz)"
                echo "[STAGE-02] Successfully installed ${repo_name} to /usr/local/bin/"
                rm -rf "${tmpdir}" "/tmp/${repo_name}.tar.gz"
                return 0
            fi
        }
        rm -rf "${tmpdir}" "/tmp/${repo_name}.tar.gz"
    fi

    # Try .tar.xz
    local tarxz_url
    tarxz_url=$(find_asset_url "${release_json}" "(aarch64|arm64).*linux.*\\.tar\\.xz$")
    if [ -z "${tarxz_url}" ]; then
        tarxz_url=$(find_asset_url "${release_json}" "linux.*(aarch64|arm64).*\\.tar\\.xz$")
    fi
    if [ -n "${tarxz_url}" ]; then
        echo "[STAGE-02] Found .tar.xz asset: ${tarxz_url}"
        local tmpdir="/tmp/${repo_name}-extract"
        mkdir -p "${tmpdir}"
        wget -q -O "/tmp/${repo_name}.tar.xz" "${tarxz_url}" && \
        tar -xJf "/tmp/${repo_name}.tar.xz" -C "${tmpdir}" && {
            local binary
            binary=$(find "${tmpdir}" -type f -name "${repo_name}" -o -type f -executable | head -1)
            if [ -n "${binary}" ] && file "${binary}" | grep -qi "executable\|ELF"; then
                cp "${binary}" "/usr/local/bin/${repo_name}"
                chmod +x "/usr/local/bin/${repo_name}"
                INSTALL_RESULTS["${repo}"]="${tag_name} (tar.xz)"
                echo "[STAGE-02] Successfully installed ${repo_name} to /usr/local/bin/"
                rm -rf "${tmpdir}" "/tmp/${repo_name}.tar.xz"
                return 0
            fi
        }
        rm -rf "${tmpdir}" "/tmp/${repo_name}.tar.xz"
    fi

    # Try .zip
    local zip_url
    zip_url=$(find_asset_url "${release_json}" "(aarch64|arm64).*linux.*\\.zip$")
    if [ -z "${zip_url}" ]; then
        zip_url=$(find_asset_url "${release_json}" "linux.*(aarch64|arm64).*\\.zip$")
    fi
    if [ -n "${zip_url}" ]; then
        echo "[STAGE-02] Found .zip asset: ${zip_url}"
        local tmpdir="/tmp/${repo_name}-extract"
        mkdir -p "${tmpdir}"
        wget -q -O "/tmp/${repo_name}.zip" "${zip_url}" && \
        unzip -o "/tmp/${repo_name}.zip" -d "${tmpdir}" && {
            local binary
            binary=$(find "${tmpdir}" -type f -name "${repo_name}" -o -type f -executable | head -1)
            if [ -n "${binary}" ] && file "${binary}" | grep -qi "executable\|ELF"; then
                cp "${binary}" "/usr/local/bin/${repo_name}"
                chmod +x "/usr/local/bin/${repo_name}"
                INSTALL_RESULTS["${repo}"]="${tag_name} (zip)"
                echo "[STAGE-02] Successfully installed ${repo_name} to /usr/local/bin/"
                rm -rf "${tmpdir}" "/tmp/${repo_name}.zip"
                return 0
            fi
        }
        rm -rf "${tmpdir}" "/tmp/${repo_name}.zip"
    fi

    echo "[STAGE-02] ERROR: Could not find suitable asset for ${repo}"
    FAILED_APPS+=("${repo}")
    INSTALL_RESULTS["${repo}"]="FAILED (no suitable asset)"
    return 1
}

# ============================================================================
# SPECIAL HANDLERS for repos with non-standard release formats
# ============================================================================

# --------------------------------------------------------------------------
# fastfetch: Releases as .deb for aarch64 linux
# --------------------------------------------------------------------------
install_fastfetch() {
    local repo="$1"
    local release_json="$2"
    local tag_name="$3"

    echo "[STAGE-02] [fastfetch] Looking for aarch64 .deb package ..."

    local deb_url
    deb_url=$(echo "${release_json}" | jq -r \
        '[.assets[] | select(.name | test("linux-aarch64.*\\.deb$"; "i"))] | .[0].browser_download_url // empty')

    if [ -z "${deb_url}" ]; then
        deb_url=$(echo "${release_json}" | jq -r \
            '[.assets[] | select(.name | test("aarch64.*\\.deb$"; "i"))] | .[0].browser_download_url // empty')
    fi

    if [ -z "${deb_url}" ]; then
        echo "[STAGE-02] [fastfetch] ERROR: No aarch64 .deb found"
        FAILED_APPS+=("${repo}")
        INSTALL_RESULTS["${repo}"]="FAILED (no .deb asset)"
        return 1
    fi

    echo "[STAGE-02] [fastfetch] Downloading: ${deb_url}"
    wget -q -O /tmp/fastfetch.deb "${deb_url}"
    dpkg -i /tmp/fastfetch.deb || apt-get install -f -y
    rm -f /tmp/fastfetch.deb

    if command -v fastfetch &>/dev/null; then
        local version
        version=$(fastfetch --version 2>/dev/null | head -1 || echo "${tag_name}")
        INSTALL_RESULTS["${repo}"]="${tag_name} (deb)"
        echo "[STAGE-02] [fastfetch] Successfully installed: ${version}"
        return 0
    else
        FAILED_APPS+=("${repo}")
        INSTALL_RESULTS["${repo}"]="FAILED (dpkg install error)"
        return 1
    fi
}

# --------------------------------------------------------------------------
# btop: Releases as .tbz archive with specific directory structure
# --------------------------------------------------------------------------
install_btop() {
    local repo="$1"
    local release_json="$2"
    local tag_name="$3"

    echo "[STAGE-02] [btop] Looking for aarch64 .tbz archive ..."

    local tbz_url
    tbz_url=$(echo "${release_json}" | jq -r \
        '[.assets[] | select(.name | test("aarch64.*linux.*\\.tbz$"; "i"))] | .[0].browser_download_url // empty')

    if [ -z "${tbz_url}" ]; then
        tbz_url=$(echo "${release_json}" | jq -r \
            '[.assets[] | select(.name | test("linux.*aarch64.*\\.tbz$"; "i"))] | .[0].browser_download_url // empty')
    fi

    if [ -z "${tbz_url}" ]; then
        echo "[STAGE-02] [btop] No .tbz found, trying .tar.bz2 ..."
        tbz_url=$(echo "${release_json}" | jq -r \
            '[.assets[] | select(.name | test("(aarch64|arm64).*linux"; "i"))] | .[0].browser_download_url // empty')
    fi

    if [ -z "${tbz_url}" ]; then
        echo "[STAGE-02] [btop] ERROR: No suitable archive found"
        FAILED_APPS+=("${repo}")
        INSTALL_RESULTS["${repo}"]="FAILED (no archive)"
        return 1
    fi

    echo "[STAGE-02] [btop] Downloading: ${tbz_url}"
    local tmpdir="/tmp/btop-extract"
    mkdir -p "${tmpdir}"
    wget -q -O /tmp/btop.tbz "${tbz_url}"
    tar -xjf /tmp/btop.tbz -C "${tmpdir}"

    # btop archives typically have a btop/bin/btop structure
    local btop_bin
    btop_bin=$(find "${tmpdir}" -type f -name "btop" | head -1)

    if [ -n "${btop_bin}" ]; then
        cp "${btop_bin}" /usr/local/bin/btop
        chmod +x /usr/local/bin/btop

        # Also install themes if present
        local themes_dir
        themes_dir=$(find "${tmpdir}" -type d -name "themes" | head -1)
        if [ -n "${themes_dir}" ]; then
            mkdir -p /usr/local/share/btop/themes
            cp -r "${themes_dir}"/* /usr/local/share/btop/themes/ 2>/dev/null || true
            echo "[STAGE-02] [btop] Installed themes"
        fi

        INSTALL_RESULTS["${repo}"]="${tag_name} (tbz)"
        echo "[STAGE-02] [btop] Successfully installed"
    else
        echo "[STAGE-02] [btop] ERROR: btop binary not found in archive"
        FAILED_APPS+=("${repo}")
        INSTALL_RESULTS["${repo}"]="FAILED (binary not in archive)"
    fi

    rm -rf "${tmpdir}" /tmp/btop.tbz
    return 0
}

# --------------------------------------------------------------------------
# micro: Releases as .tar.gz with specific naming
# --------------------------------------------------------------------------
install_micro() {
    local repo="$1"
    local release_json="$2"
    local tag_name="$3"

    echo "[STAGE-02] [micro] Looking for linux-arm64 .tar.gz ..."

    local targz_url
    targz_url=$(echo "${release_json}" | jq -r \
        '[.assets[] | select(.name | test("linux-arm64.*\\.tar\\.gz$"; "i"))] | .[0].browser_download_url // empty')

    if [ -z "${targz_url}" ]; then
        targz_url=$(echo "${release_json}" | jq -r \
            '[.assets[] | select(.name | test("linux.*arm64.*\\.tar\\.gz$"; "i"))] | .[0].browser_download_url // empty')
    fi

    if [ -z "${targz_url}" ]; then
        echo "[STAGE-02] [micro] ERROR: No arm64 .tar.gz found"
        FAILED_APPS+=("${repo}")
        INSTALL_RESULTS["${repo}"]="FAILED (no .tar.gz)"
        return 1
    fi

    echo "[STAGE-02] [micro] Downloading: ${targz_url}"
    local tmpdir="/tmp/micro-extract"
    mkdir -p "${tmpdir}"
    wget -q -O /tmp/micro.tar.gz "${targz_url}"
    tar -xzf /tmp/micro.tar.gz -C "${tmpdir}"

    local micro_bin
    micro_bin=$(find "${tmpdir}" -type f -name "micro" | head -1)

    if [ -n "${micro_bin}" ]; then
        cp "${micro_bin}" /usr/local/bin/micro
        chmod +x /usr/local/bin/micro
        INSTALL_RESULTS["${repo}"]="${tag_name} (tar.gz)"
        echo "[STAGE-02] [micro] Successfully installed"
    else
        echo "[STAGE-02] [micro] ERROR: micro binary not found in archive"
        FAILED_APPS+=("${repo}")
        INSTALL_RESULTS["${repo}"]="FAILED (binary not in archive)"
    fi

    rm -rf "${tmpdir}" /tmp/micro.tar.gz
    return 0
}

# --------------------------------------------------------------------------
# lazygit: Releases as .tar.gz with naming lazygit_*_Linux_arm64.tar.gz
# --------------------------------------------------------------------------
install_lazygit() {
    local repo="$1"
    local release_json="$2"
    local tag_name="$3"

    echo "[STAGE-02] [lazygit] Looking for Linux_arm64 .tar.gz ..."

    local targz_url
    targz_url=$(echo "${release_json}" | jq -r \
        '[.assets[] | select(.name | test("Linux_arm64\\.tar\\.gz$"))] | .[0].browser_download_url // empty')

    if [ -z "${targz_url}" ]; then
        targz_url=$(echo "${release_json}" | jq -r \
            '[.assets[] | select(.name | test("linux.*arm64.*\\.tar\\.gz$"; "i"))] | .[0].browser_download_url // empty')
    fi

    if [ -z "${targz_url}" ]; then
        echo "[STAGE-02] [lazygit] ERROR: No Linux_arm64 .tar.gz found"
        FAILED_APPS+=("${repo}")
        INSTALL_RESULTS["${repo}"]="FAILED (no .tar.gz)"
        return 1
    fi

    echo "[STAGE-02] [lazygit] Downloading: ${targz_url}"
    local tmpdir="/tmp/lazygit-extract"
    mkdir -p "${tmpdir}"
    wget -q -O /tmp/lazygit.tar.gz "${targz_url}"
    tar -xzf /tmp/lazygit.tar.gz -C "${tmpdir}"

    local lazygit_bin
    lazygit_bin=$(find "${tmpdir}" -type f -name "lazygit" | head -1)

    if [ -n "${lazygit_bin}" ]; then
        cp "${lazygit_bin}" /usr/local/bin/lazygit
        chmod +x /usr/local/bin/lazygit
        INSTALL_RESULTS["${repo}"]="${tag_name} (tar.gz)"
        echo "[STAGE-02] [lazygit] Successfully installed"
    else
        echo "[STAGE-02] [lazygit] ERROR: lazygit binary not found in archive"
        FAILED_APPS+=("${repo}")
        INSTALL_RESULTS["${repo}"]="FAILED (binary not in archive)"
    fi

    rm -rf "${tmpdir}" /tmp/lazygit.tar.gz
    return 0
}

# --------------------------------------------------------------------------
# fd: Releases as .deb or .tar.gz for aarch64
# --------------------------------------------------------------------------
install_fd() {
    local repo="$1"
    local release_json="$2"
    local tag_name="$3"

    echo "[STAGE-02] [fd] Looking for aarch64 package ..."

    # Try .deb first
    local deb_url
    deb_url=$(echo "${release_json}" | jq -r \
        '[.assets[] | select(.name | test("aarch64.*\\.deb$"; "i"))] | .[0].browser_download_url // empty')

    if [ -z "${deb_url}" ]; then
        deb_url=$(echo "${release_json}" | jq -r \
            '[.assets[] | select(.name | test("arm64.*\\.deb$"; "i"))] | .[0].browser_download_url // empty')
    fi

    if [ -n "${deb_url}" ]; then
        echo "[STAGE-02] [fd] Found .deb: ${deb_url}"
        wget -q -O /tmp/fd.deb "${deb_url}"
        dpkg -i /tmp/fd.deb || apt-get install -f -y
        rm -f /tmp/fd.deb

        if command -v fd &>/dev/null || command -v fdfind &>/dev/null; then
            # Create symlink if installed as fdfind
            if ! command -v fd &>/dev/null && command -v fdfind &>/dev/null; then
                ln -sf "$(which fdfind)" /usr/local/bin/fd
            fi
            INSTALL_RESULTS["${repo}"]="${tag_name} (deb)"
            echo "[STAGE-02] [fd] Successfully installed via .deb"
            return 0
        fi
    fi

    # Fallback to .tar.gz
    local targz_url
    targz_url=$(echo "${release_json}" | jq -r \
        '[.assets[] | select(.name | test("aarch64.*linux.*\\.tar\\.gz$"; "i"))] | .[0].browser_download_url // empty')

    if [ -z "${targz_url}" ]; then
        targz_url=$(echo "${release_json}" | jq -r \
            '[.assets[] | select(.name | test("arm64.*linux.*\\.tar\\.gz$"; "i"))] | .[0].browser_download_url // empty')
    fi

    if [ -n "${targz_url}" ]; then
        echo "[STAGE-02] [fd] Found .tar.gz: ${targz_url}"
        local tmpdir="/tmp/fd-extract"
        mkdir -p "${tmpdir}"
        wget -q -O /tmp/fd.tar.gz "${targz_url}"
        tar -xzf /tmp/fd.tar.gz -C "${tmpdir}"

        local fd_bin
        fd_bin=$(find "${tmpdir}" -type f -name "fd" | head -1)
        if [ -n "${fd_bin}" ]; then
            cp "${fd_bin}" /usr/local/bin/fd
            chmod +x /usr/local/bin/fd
            INSTALL_RESULTS["${repo}"]="${tag_name} (tar.gz)"
            echo "[STAGE-02] [fd] Successfully installed"

            # Install man page and completions if available
            local man_page
            man_page=$(find "${tmpdir}" -type f -name "fd.1" | head -1)
            if [ -n "${man_page}" ]; then
                mkdir -p /usr/local/share/man/man1
                cp "${man_page}" /usr/local/share/man/man1/
            fi
            local bash_comp
            bash_comp=$(find "${tmpdir}" -type f -name "fd.bash" -o -name "fd.bash-completion" | head -1)
            if [ -n "${bash_comp}" ]; then
                mkdir -p /usr/share/bash-completion/completions
                cp "${bash_comp}" /usr/share/bash-completion/completions/fd
            fi
        else
            FAILED_APPS+=("${repo}")
            INSTALL_RESULTS["${repo}"]="FAILED (binary not in archive)"
        fi
        rm -rf "${tmpdir}" /tmp/fd.tar.gz
        return 0
    fi

    echo "[STAGE-02] [fd] ERROR: No suitable asset found"
    FAILED_APPS+=("${repo}")
    INSTALL_RESULTS["${repo}"]="FAILED (no asset)"
    return 1
}

# --------------------------------------------------------------------------
# ripgrep: Releases as .tar.gz for aarch64
# --------------------------------------------------------------------------
install_ripgrep() {
    local repo="$1"
    local release_json="$2"
    local tag_name="$3"

    echo "[STAGE-02] [ripgrep] Looking for aarch64 .tar.gz ..."

    local targz_url
    targz_url=$(echo "${release_json}" | jq -r \
        '[.assets[] | select(.name | test("aarch64.*linux.*\\.tar\\.gz$"; "i"))] | .[0].browser_download_url // empty')

    if [ -z "${targz_url}" ]; then
        targz_url=$(echo "${release_json}" | jq -r \
            '[.assets[] | select(.name | test("arm64.*linux.*\\.tar\\.gz$"; "i"))] | .[0].browser_download_url // empty')
    fi

    if [ -z "${targz_url}" ]; then
        targz_url=$(echo "${release_json}" | jq -r \
            '[.assets[] | select(.name | test("linux.*aarch64.*\\.tar\\.gz$"; "i"))] | .[0].browser_download_url // empty')
    fi

    if [ -z "${targz_url}" ]; then
        echo "[STAGE-02] [ripgrep] ERROR: No aarch64 .tar.gz found"
        FAILED_APPS+=("${repo}")
        INSTALL_RESULTS["${repo}"]="FAILED (no .tar.gz)"
        return 1
    fi

    echo "[STAGE-02] [ripgrep] Downloading: ${targz_url}"
    local tmpdir="/tmp/ripgrep-extract"
    mkdir -p "${tmpdir}"
    wget -q -O /tmp/ripgrep.tar.gz "${targz_url}"
    tar -xzf /tmp/ripgrep.tar.gz -C "${tmpdir}"

    local rg_bin
    rg_bin=$(find "${tmpdir}" -type f -name "rg" | head -1)

    if [ -n "${rg_bin}" ]; then
        cp "${rg_bin}" /usr/local/bin/rg
        chmod +x /usr/local/bin/rg
        INSTALL_RESULTS["${repo}"]="${tag_name} (tar.gz)"
        echo "[STAGE-02] [ripgrep] Successfully installed"

        # Install man page and completions if available
        local man_page
        man_page=$(find "${tmpdir}" -type f -name "rg.1" | head -1)
        if [ -n "${man_page}" ]; then
            mkdir -p /usr/local/share/man/man1
            cp "${man_page}" /usr/local/share/man/man1/
        fi
        local bash_comp
        bash_comp=$(find "${tmpdir}" -type f -name "rg.bash" | head -1)
        if [ -n "${bash_comp}" ]; then
            mkdir -p /usr/share/bash-completion/completions
            cp "${bash_comp}" /usr/share/bash-completion/completions/rg
        fi
    else
        echo "[STAGE-02] [ripgrep] ERROR: rg binary not found in archive"
        FAILED_APPS+=("${repo}")
        INSTALL_RESULTS["${repo}"]="FAILED (binary not in archive)"
    fi

    rm -rf "${tmpdir}" /tmp/ripgrep.tar.gz
    return 0
}

# --------------------------------------------------------------------------
# yazi: Releases as .zip for aarch64
# --------------------------------------------------------------------------
install_yazi() {
    local repo="$1"
    local release_json="$2"
    local tag_name="$3"

    echo "[STAGE-02] [yazi] Looking for aarch64 .zip ..."

    local zip_url
    zip_url=$(echo "${release_json}" | jq -r \
        '[.assets[] | select(.name | test("aarch64.*linux.*\\.zip$"; "i"))] | .[0].browser_download_url // empty')

    if [ -z "${zip_url}" ]; then
        zip_url=$(echo "${release_json}" | jq -r \
            '[.assets[] | select(.name | test("linux.*aarch64.*\\.zip$"; "i"))] | .[0].browser_download_url // empty')
    fi

    # Also try arm64 naming
    if [ -z "${zip_url}" ]; then
        zip_url=$(echo "${release_json}" | jq -r \
            '[.assets[] | select(.name | test("(aarch64|arm64).*linux.*\\.zip$"; "i"))] | .[0].browser_download_url // empty')
    fi

    if [ -z "${zip_url}" ]; then
        echo "[STAGE-02] [yazi] ERROR: No aarch64 .zip found"
        FAILED_APPS+=("${repo}")
        INSTALL_RESULTS["${repo}"]="FAILED (no .zip)"
        return 1
    fi

    echo "[STAGE-02] [yazi] Downloading: ${zip_url}"
    local tmpdir="/tmp/yazi-extract"
    mkdir -p "${tmpdir}"
    wget -q -O /tmp/yazi.zip "${zip_url}"
    unzip -o /tmp/yazi.zip -d "${tmpdir}"

    # Install yazi binary
    local yazi_bin
    yazi_bin=$(find "${tmpdir}" -type f -name "yazi" | head -1)

    if [ -n "${yazi_bin}" ]; then
        cp "${yazi_bin}" /usr/local/bin/yazi
        chmod +x /usr/local/bin/yazi
        echo "[STAGE-02] [yazi] Installed yazi binary"

        # Also install ya (yazi helper) if present
        local ya_bin
        ya_bin=$(find "${tmpdir}" -type f -name "ya" | head -1)
        if [ -n "${ya_bin}" ]; then
            cp "${ya_bin}" /usr/local/bin/ya
            chmod +x /usr/local/bin/ya
            echo "[STAGE-02] [yazi] Installed ya helper binary"
        fi

        INSTALL_RESULTS["${repo}"]="${tag_name} (zip)"
        echo "[STAGE-02] [yazi] Successfully installed"
    else
        echo "[STAGE-02] [yazi] ERROR: yazi binary not found in archive"
        FAILED_APPS+=("${repo}")
        INSTALL_RESULTS["${repo}"]="FAILED (binary not in archive)"
    fi

    rm -rf "${tmpdir}" /tmp/yazi.zip
    return 0
}

# --------------------------------------------------------------------------
# Create .desktop files for TUI/GUI applications
# --------------------------------------------------------------------------
create_desktop_files() {
    echo "[STAGE-02] Creating .desktop files ..."

    mkdir -p /usr/share/applications

    # btop
    if command -v btop &>/dev/null || [ -x /usr/local/bin/btop ]; then
        cat > /usr/share/applications/btop.desktop << 'EOF'
[Desktop Entry]
Name=btop
Comment=Resource monitor
Exec=foot -e btop
Icon=utilities-system-monitor
Terminal=false
Type=Application
Categories=System;Monitor;ConsoleOnly;
Keywords=system;process;task;monitor;
EOF
        echo "[STAGE-02]   Created btop.desktop"
    fi

    # yazi
    if command -v yazi &>/dev/null || [ -x /usr/local/bin/yazi ]; then
        cat > /usr/share/applications/yazi.desktop << 'EOF'
[Desktop Entry]
Name=Yazi
Comment=Terminal file manager
Exec=foot -e yazi
Icon=system-file-manager
Terminal=false
Type=Application
Categories=System;FileTools;FileManager;ConsoleOnly;
Keywords=file;manager;terminal;
EOF
        echo "[STAGE-02]   Created yazi.desktop"
    fi

    # lazygit
    if command -v lazygit &>/dev/null || [ -x /usr/local/bin/lazygit ]; then
        cat > /usr/share/applications/lazygit.desktop << 'EOF'
[Desktop Entry]
Name=LazyGit
Comment=Terminal UI for git commands
Exec=foot -e lazygit
Icon=git
Terminal=false
Type=Application
Categories=Development;RevisionControl;ConsoleOnly;
Keywords=git;version;control;
EOF
        echo "[STAGE-02]   Created lazygit.desktop"
    fi

    # micro
    if command -v micro &>/dev/null || [ -x /usr/local/bin/micro ]; then
        cat > /usr/share/applications/micro.desktop << 'EOF'
[Desktop Entry]
Name=Micro
Comment=Modern terminal text editor
Exec=foot -e micro %F
Icon=text-editor
Terminal=false
Type=Application
Categories=Utility;TextEditor;ConsoleOnly;
Keywords=text;editor;terminal;
MimeType=text/plain;text/x-chdr;text/x-csrc;text/x-c++hdr;text/x-c++src;text/x-java;text/x-python;application/x-shellscript;
EOF
        echo "[STAGE-02]   Created micro.desktop"
    fi

    echo "[STAGE-02] .desktop files created"
}

# ============================================================================
# MAIN: Install all applications
# ============================================================================

echo "[STAGE-02] Processing ${#ALL_REPOS[@]} repositories ..."
echo "[STAGE-02] ========================================"

for repo in "${ALL_REPOS[@]}"; do
    # Use subshell error handling so one failure doesn't stop all
    install_github_app "${repo}" || {
        echo "[STAGE-02] WARNING: Installation failed for ${repo}, continuing ..."
    }
    echo ""
done

# Create desktop files
create_desktop_files

# --------------------------------------------------------------------------
# Clean up build dependencies
# --------------------------------------------------------------------------
echo "[STAGE-02] Removing build dependencies to save space ..."
apt-get remove -y --purge build-essential cmake 2>/dev/null || true
apt-get autoremove -y 2>/dev/null || true
apt-get clean
rm -rf /var/lib/apt/lists/*

# Clean up any remaining temp files
rm -rf /tmp/*-extract /tmp/*.tar.gz /tmp/*.tar.xz /tmp/*.tar.bz2 /tmp/*.zip /tmp/*.deb /tmp/*.tbz

# --------------------------------------------------------------------------
# Print summary
# --------------------------------------------------------------------------
echo ""
echo "[STAGE-02] ============================================"
echo "[STAGE-02] INSTALLATION SUMMARY"
echo "[STAGE-02] ============================================"
printf "[STAGE-02] %-30s %s\n" "REPOSITORY" "STATUS"
printf "[STAGE-02] %-30s %s\n" "------------------------------" "--------------------"

for repo in "${ALL_REPOS[@]}"; do
    status="${INSTALL_RESULTS[${repo}]:-UNKNOWN}"
    printf "[STAGE-02] %-30s %s\n" "${repo}" "${status}"
done

if [ ${#FAILED_APPS[@]} -gt 0 ]; then
    echo ""
    echo "[STAGE-02] WARNING: ${#FAILED_APPS[@]} application(s) failed to install:"
    for app in "${FAILED_APPS[@]}"; do
        echo "[STAGE-02]   - ${app}"
    done
fi

echo "[STAGE-02] ============================================"
echo "[STAGE-02] GitHub applications stage completed"
echo "[STAGE-02] ============================================"
