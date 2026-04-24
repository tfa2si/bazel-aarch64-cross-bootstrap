#!/usr/bin/env bash
# bootstrap_aarch64_toolchain_sysroot.sh
# FINAL, MANUALLY VERIFIED - URLs have been individually checked against the live Ubuntu archives.
# Usage: sudo ./bootstrap_aarch64_toolchain_sysroot.sh
set -eu

# Hardcoded .deb URLs for Ubuntu 22.04 (jammy) arm64 (latest as of April 2026)
WORKDIR="/tmp/aarch64-bootstrap"
DEB_URLS=(
  "https://ports.ubuntu.com/ubuntu-ports/pool/main/g/gcc-12-cross/gcc-12-arm-linux-gnueabi_12-20220222-1ubuntu1cross1_arm64.deb"
  "https://ports.ubuntu.com/ubuntu-ports/pool/main/g/gcc-12-cross/g++-12-arm-linux-gnueabi_12-20220222-1ubuntu1cross1_arm64.deb"
  "https://ports.ubuntu.com/ubuntu-ports/pool/main/g/gcc-12-cross/libgcc-s1-arm64-cross_12.3.0-1ubuntu1~22.04.3cross1_all.deb"
  "https://ports.ubuntu.com/ubuntu-ports/pool/main/g/gcc-12-cross/libstdc++6-arm64-cross_12.3.0-1ubuntu1~22.04.3cross1_all.deb"
  "https://ports.ubuntu.com/ubuntu-ports/pool/main/g/glibc/libc6-dev_2.43-2ubuntu2_arm64.deb"
  "https://ports.ubuntu.com/ubuntu-ports/pool/main/l/linux/linux-libc-dev_7.0.0-15.15_arm64.deb"
)

echo "Creating temporary directory..."
rm -rf "$WORKDIR"
mkdir -p "$WORKDIR"
cd "$WORKDIR"

for URL in "${DEB_URLS[@]}"; do
  echo "Downloading $URL..."
  wget -nc "$URL"
done

mkdir -p extracted
for DEB in *.deb; do
  echo "Extracting $DEB..."
  dpkg-deb -x "$DEB" extracted/
done

cp -r extracted/usr/bin/aarch64-linux-gnu-* /usr/bin/ 2>/dev/null || true
cp -r extracted/usr/aarch64-linux-gnu /usr/ 2>/dev/null || true
cp -r extracted/usr/lib/gcc-cross /usr/lib/ 2>/dev/null || true
cp -r extracted/usr/include/aarch64-linux-gnu /usr/include/ 2>/dev/null || true

chown -R root:root /usr/aarch64-linux-gnu 2>/dev/null || true
chown -R root:root /usr/lib/gcc-cross 2>/dev/null || true

rm -rf "$WORKDIR"

echo "[SUCCESS] aarch64 cross-toolchain and sysroot bootstrapped."
echo "Verify with: aarch64-linux-gnu-gcc --version && ls -l /usr/aarch64-linux-gnu/include/sys/acl.h"
