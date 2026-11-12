```
 ███╗   ██╗███████╗██╗   ██╗██╗  ██╗ ██████╗ ███╗   ██╗     ██████╗ ███████╗
 ████╗  ██║██╔════╝██║   ██║╚██╗██╔╝██╔═══██╗████╗  ██║    ██╔═══██╗██╔════╝
 ██╔██╗ ██║█████╗  ██║   ██║ ╚███╔╝ ██║   ██║██╔██╗ ██║    ██║   ██║███████╗
 ██║╚██╗██║██╔══╝  ██║   ██║ ██╔██╗ ██║   ██║██║╚██╗██║    ██║   ██║╚════██║
 ██║ ╚████║███████╗╚██████╔╝██╔╝ ██╗╚██████╔╝██║ ╚████║    ╚██████╔╝███████║
 ╚═╝  ╚═══╝╚══════╝ ╚═════╝ ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═══╝     ╚═════╝ ╚══════╝
```

# Neuxon OS — Ultra-Optimized Raspberry Pi 3B+ Operating System

**Neuxon OS** is a minimal, performance-first Linux distribution purpose-built for the
**Raspberry Pi 3B+** (BCM2837B0, Cortex-A53 quad-core, 1 GB RAM). It ships a modern
Wayland desktop based on **Labwc**, **Waybar**, and **Fuzzel** — all wrapped in a
monochromatic design language that is as lean on resources as it is clean on screen.

The entire OS image is assembled reproducibly from Debian Bookworm `arm64` packages using
`debootstrap`, cross-compiled on any x86_64 host via QEMU user-mode emulation, and
delivered as a compressed `.img.xz` ready to flash with `dd`, Raspberry Pi Imager, or
balenaEtcher.

---

## Hardware Target

| Spec | Value |
|---|---|
| **Board** | Raspberry Pi 3 Model B+ |
| **SoC** | Broadcom BCM2837B0 |
| **CPU** | Quad-core Cortex-A53 @ 1.4 GHz (ARMv8-A / aarch64) |
| **RAM** | 1 GB LPDDR2 |
| **GPU** | Broadcom VideoCore IV @ 400 MHz |
| **Network** | Gigabit Ethernet (USB 2.0 bound), 802.11ac Wi-Fi, Bluetooth 4.2 |
| **Storage** | microSD (SDHC / SDXC) |

---

## Features

### Performance & System
- **Debian Bookworm arm64** base — stable, well-tested package ecosystem
- **Raspberry Pi kernel** from the official `archive.raspberrypi.com` repository
- **ZRAM swap** with `zstd` compression, sized to 100 % of RAM, `swappiness=100`
- **systemd-networkd + systemd-resolved** for fast, lightweight networking
- **systemd-timesyncd** for NTP time synchronization
- **Headless-ready** — SSH enabled out of the box
- **Minimal footprint** — no snap, no flatpak, no bloatware

### Desktop Environment
- **Labwc** — lightweight Wayland compositor (wlroots-based, Openbox-like)
- **Waybar** — highly customizable status bar
- **Fuzzel** — fast, Wayland-native application launcher
- **Foot** — minimal, GPU-accelerated terminal emulator
- **Thunar** — lightweight file manager
- **seatd** — minimal seat management (no elogind overhead)

### Applications (built from GitHub sources)
- Additional applications cloned and compiled from upstream GitHub repositories
- Easily extensible — drop a new repo URL into the apps stage

### Theme & Branding
| Token | Hex |
|---|---|
| Background | `#080808` |
| Surface | `#121212` |
| Border | `#262626` |
| Text | `#F2F2F2` |
| Muted | `#888888` |
| Accent | `#FFFFFF` |

---

## Quick Start

### Option 1 — GitHub Actions (recommended)

1. **Fork** this repository on GitHub.
2. Push to the `main` branch (or open a pull request).
3. The **Build Neuxon OS** workflow runs automatically.
4. Download the artifacts from the **Actions** tab:
   - `Neuxon-OS-rpi3bplus-arm64.img.xz`
   - `Neuxon-OS-rpi3bplus-arm64.iso`
   - `checksums.txt`

### Option 2 — Local Docker build

```bash
git clone https://github.com/your-org/neuxon-os.git
cd neuxon-os
chmod +x build-local-docker.sh
./build-local-docker.sh
```

Artifacts are written to the `output/` directory.

### Option 3 — Manual build on a Debian/Ubuntu x86_64 host

```bash
git clone https://github.com/your-org/neuxon-os.git
cd neuxon-os
chmod +x build.sh
sudo ./build.sh
```

### Flashing the image

```bash
xz -dk output/Neuxon-OS-rpi3bplus-arm64.img.xz
sudo dd if=output/Neuxon-OS-rpi3bplus-arm64.img of=/dev/sdX bs=4M status=progress conv=fsync
```

Replace `/dev/sdX` with your microSD card device. **Double-check** the target device!

---

## Repository Structure

```
neuxon-os/
├── .github/
│   └── workflows/
│       └── build-neuxon-os.yml          # GitHub Actions CI workflow
├── config/
│   ├── boot/
│   │   ├── cmdline.txt                  # Optimized kernel cmdline
│   │   └── config.txt                   # RPi3B+ BCM2837B0 boot config
│   ├── branding/
│   │   ├── fastfetch/config.jsonc       # Fastfetch monochrome layout
│   │   ├── plymouth/neuxon/             # Custom Plymouth boot splash
│   │   ├── issue                        # Pre-login monochrome banner
│   │   ├── motd                         # Post-login welcome box
│   │   └── os-release                   # Distribution identification
│   ├── desktop/
│   │   ├── btop/                        # btop monochrome configuration & theme
│   │   ├── foot/foot.ini                # Foot terminal configuration
│   │   ├── fuzzel/fuzzel.ini            # Fuzzel launcher configuration
│   │   ├── gtk-3.0/                     # GTK3 dark monochrome CSS & settings
│   │   ├── gtk-4.0/                     # GTK4 dark monochrome CSS & settings
│   │   ├── labwc/                       # Labwc Openbox config & themerc-override
│   │   ├── mako/config                  # Mako notification daemon config
│   │   ├── micro/settings.json          # Micro editor dark settings
│   │   ├── waybar/                      # Waybar JSON layout & CSS style
│   │   ├── yazi/theme.toml              # Yazi monochrome theme
│   │   └── neuxon-session.sh            # Wayland session startup script
│   ├── system/
│   │   ├── disable-services.sh          # Daemon stripping script
│   │   ├── fstab                        # Optimized root/tmp/log mounts
│   │   ├── neuxon-zram.service          # ZRAM swap systemd unit
│   │   ├── sysctl-neuxon.conf           # Aggressive ZRAM vm tuning
│   │   └── zram-setup.sh                # 100% RAM zstd ZRAM setup
│   └── user/
│       └── setup-user.sh                # Default user provisioning
├── scripts/
│   ├── common.sh                        # Shared helper functions
│   ├── create-image.sh                  # Disk image creation & compression
│   ├── create-iso.sh                    # ISO wrapper creation
│   └── setup-host-deps.sh               # Host build dependency installer
├── stage-neuxon/
│   ├── 00-bootstrap/
│   │   └── 01-run.sh                    # Debootstrap arm64 rootfs
│   ├── 01-base-system/
│   │   └── 01-run-chroot.sh             # Kernel, firmware, base config
│   ├── 02-github-apps/
│   │   └── 01-run-chroot.sh             # Automated GitHub applications pipeline
│   ├── 03-desktop/
│   │   └── 01-run-chroot.sh             # Labwc, Waybar, Fuzzel, Foot
│   ├── 04-branding/
│   │   └── 01-run-chroot.sh             # Theme, GTK, Plymouth, MOTD
│   └── 05-finalize/
│       └── 01-run.sh                    # Image assembly & compression
├── build.sh                             # Main build orchestrator
├── build-local-docker.sh                # Docker-based local build runner
├── Dockerfile                           # Build environment container
├── .gitattributes                       # Line-ending normalization
├── LICENSE                              # MIT License
└── README.md                            # Comprehensive documentation
```

---

## Customization Guide

### Adding packages

Edit `stage-neuxon/01-base-system/01-run-chroot.sh` and append package names to the
`apt-get install` invocation, or add a new `apt-get install` line at the end of the
script.

### Adding GitHub-sourced applications

Edit `stage-neuxon/02-github-apps/01-run-chroot.sh`. Add a new block following the
existing pattern:

```bash
log_info "Building my-app..."
cd /tmp
git clone --depth 1 https://github.com/user/my-app.git
cd my-app
# build commands (make, cmake, meson, etc.)
make install
cd /tmp && rm -rf my-app
```

### Changing theme colors

All color tokens are applied in `stage-neuxon/04-branding/01-run-chroot.sh`. Search for
the hex values listed in the **Theme & Branding** table above and replace them with your
preferred palette.

### Changing the default user or password

In `build.sh`, modify the `USERNAME` and `PASSWORD` variables near the top of the file:

```bash
USERNAME="myuser"
PASSWORD="mypassword"
```

### Changing the image size

In `build.sh`, adjust `IMG_SIZE`:

```bash
IMG_SIZE="8G"   # default is 4G
```

### Changing the boot partition size

In `build.sh`, adjust `BOOT_SIZE`:

```bash
BOOT_SIZE="512M"   # default is 256M
```

---

## Default Credentials

| Field | Value |
|---|---|
| **Username** | `neuxon` |
| **Password** | `neuxon` |

> **⚠️  Change the password on first login!**
>
> ```bash
> passwd
> ```

---

## License

Neuxon OS is released under the **MIT License**. See [LICENSE](LICENSE) for the full text.
