###############################################################################
# Dockerfile — Neuxon OS Build Environment
###############################################################################
# Provides a reproducible Debian Bookworm x86_64 environment with all host
# dependencies needed to cross-build the Neuxon OS arm64 image.
#
# Usage:
#   docker build -t neuxon-os-builder .
#   docker run --privileged -v $(pwd)/output:/build/output neuxon-os-builder
###############################################################################

FROM debian:bookworm

LABEL maintainer="Neuxon OS Contributors"
LABEL description="Build environment for Neuxon OS (Raspberry Pi 3B+ arm64)"

# ---------------------------------------------------------------------------
# Install build dependencies
# ---------------------------------------------------------------------------
RUN apt-get update -qq && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        debootstrap \
        qemu-user-static \
        binfmt-support \
        xz-utils \
        dosfstools \
        e2fsprogs \
        parted \
        kpartx \
        xorriso \
        mtools \
        git \
        curl \
        wget \
        ca-certificates \
        rsync \
        fdisk \
        mount \
        systemd-container \
        jq \
        unzip \
        file \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# Copy the build system into the container
# ---------------------------------------------------------------------------
COPY . /build

# ---------------------------------------------------------------------------
# Make all scripts executable
# ---------------------------------------------------------------------------
RUN find /build -name '*.sh' -exec chmod +x {} +

# ---------------------------------------------------------------------------
# Set working directory and entrypoint
# ---------------------------------------------------------------------------
WORKDIR /build

ENTRYPOINT ["/build/build.sh"]
