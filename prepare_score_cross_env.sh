#!/bin/bash
set -e

# Download and build ACL for ARM64 if not already built
if [ ! -d "$HOME/acl_build/acl-2.3.2" ]; then
  mkdir -p $HOME/acl_build
  cd $HOME/acl_build
  wget https://download.savannah.nongnu.org/releases/acl/acl-2.3.2.tar.gz
  tar xf acl-2.3.2.tar.gz
  cd acl-2.3.2
  ./configure --host=aarch64-linux-gnu --prefix=/usr/aarch64-linux-gnu --enable-static --disable-shared CFLAGS="-fPIC"
  make
fi

# Ensure sysroot header exists (copy if missing)
if [ ! -f /usr/aarch64-linux-gnu/include/sys/acl.h ]; then
  sudo mkdir -p /usr/aarch64-linux-gnu/include/sys
  sudo cp $HOME/acl_build/acl-2.3.2/include/sys/acl.h /usr/aarch64-linux-gnu/include/sys/
fi

echo "ACL for ARM64 built and sysroot header ensured."
