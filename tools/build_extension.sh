#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${ANDROID_NDK_HOME:?Point ANDROID_NDK_HOME at the installed Android NDK}"
mkdir -p native/bin
args=(-std=c++17 -O3 -fPIC -shared -fvisibility=hidden -Wl,--no-undefined)
g++ "${args[@]}" native/terrain_kernel.cpp -o native/bin/libskyterrain.linux.x86_64.so
toolchain="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64"
"$toolchain/bin/aarch64-linux-android26-clang++" "${args[@]}" \
  native/terrain_kernel.cpp -o native/bin/libskyterrain.android.arm64.so
