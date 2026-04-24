# ARM64 Cross-Compilation for eclipse-score/communication

This directory contains scripts to set up a fully automated, repository-independent ARM64 cross-compilation pipeline for the [eclipse-score/communication](https://github.com/eclipse-score/communication) project using Bazel on an Ubuntu 22.04/24.04 host.

---

## Why Bazel Cross-Compilation Is Difficult

Setting up Bazel for C++ cross-compilation is notoriously challenging, especially for ARM targets. The main difficulties are:

- **Toolchain API Instability:** Bazel's C++ toolchain API has changed significantly across versions. Many online guides are outdated, and the modern `action_config`/`tool_path` APIs are not always compatible with the version of `rules_cc` in use.
- **rules_cc Compatibility:** The `rules_cc` repository often lags behind Bazel releases. This leads to breakage if you use the latest Bazel with older toolchain configs, or vice versa.
- **Sysroot and Linker Issues:** Getting the sysroot and linker (`g++` vs `gcc`) set up correctly is critical. If Bazel uses `gcc` for linking C++ binaries, you get missing symbols like `std::cout`.
- **Opaque Error Messages:** Bazel's error messages for toolchain misconfiguration are often cryptic, making debugging slow and frustrating.
- **Platform/Constraint Complexity:** You must define and register platforms and toolchains explicitly, and Bazel's platform resolution can be non-obvious.

### The Approach Used in This Project

This project uses a **legacy workaround** that is robust across Bazel 8.x and recent `rules_cc`:

- **Linker Tool Path Set to g++:** In the toolchain config, the tool named `linker` is set to the path of `g++` (not `ld` or `gcc`). This forces Bazel to use the C++ linker, avoiding missing C++ symbols.
- **No action_config Blocks:** Only the most stable Starlark APIs are used: `feature`, `flag_set`, `flag_group`, and `tool_path`. No `action_config` or `with_feature_set` blocks are present, as these are the source of most incompatibilities.
- **Explicit Sysroot Feature:** The sysroot is injected as a feature for all compile and link actions, ensuring the correct headers and libraries are found for ARM.
- **Minimal, Explicit Toolchain Registration:** Only the required toolchain and platforms are registered, and all tool paths are specified.

## Prerequisites

- Ubuntu 22.04 or 24.04 host (x86-64)
- Bazel installed
- Internet access (to download `.deb` packages from `ports.ubuntu.com`)

No `apt` repository access is required — all toolchain and sysroot files are fetched via direct `.deb` URLs.

---

## Quick Start

Run the three scripts in order from this directory:

```bash
# 1. Bootstrap the aarch64 cross-toolchain and sysroot
sudo bash bootstrap_aarch64_toolchain_sysroot.sh

# 2. Build ACL for ARM64 and prepare the cross-compilation environment
bash prepare_score_cross_env.sh

# 3. Apply all required source and build patches
bash apply_score_cross_patches.sh
```

Then build with Bazel:

```bash
cd ~/test/communication

# ARM64 (Raspberry Pi 5 / aarch64)
bazel build //score/mw/com/example/ipc_bridge:ipc_bridge_cpp \
    --platforms=//platforms:rpi5_aarch64

# x86-64 (host)
bazel build //score/mw/com/example/ipc_bridge:ipc_bridge_cpp
```

---

## Scripts

### `bootstrap_aarch64_toolchain_sysroot.sh`

Downloads and installs everything needed for ARM64 cross-compilation directly from `.deb` packages — no `apt` repository required. Installs to `/usr/bin` and `/usr/aarch64-linux-gnu`.

What it does:
- Downloads `gcc-aarch64-linux-gnu`, `g++-aarch64-linux-gnu`, `libc6-dev:arm64`, and other required packages
- Extracts and installs toolchain binaries and sysroot files
- Cleans up temporary files

Verify after running:
```bash
aarch64-linux-gnu-gcc --version
ls /usr/aarch64-linux-gnu
```

### `prepare_score_cross_env.sh`

Builds ACL for ARM64 and ensures the required sysroot headers are in place.

What it does:
- Builds `libacl` for ARM64 (if not already built)
- Copies `acl.h` into the sysroot if missing

### `apply_score_cross_patches.sh`

Applies all patches needed for a green-field cross-compilation build.

What it does:
- Copies the rebuilt `libacl.a` and headers to the forked `score_baselibs`
- Patches sysroot and `local_acl` headers to remove `EXPORT` macros
- Patches the `score_baselibs` `BUILD` file to use `local_acl` for ARM64
- Configures Bazel to disable `-Werror=deprecated-declarations`
- Registers the ARM64 toolchain and platform in the Bazel workspace

---

## Notes

- All scripts are idempotent — safe to re-run.
- `.deb` URLs in `bootstrap_aarch64_toolchain_sysroot.sh` are hardcoded to specific versions. If a URL returns 404, update it to the latest available version from [ports.ubuntu.com](http://ports.ubuntu.com/pool/main/).
- For manual inspection of any step, read the individual scripts directly.
