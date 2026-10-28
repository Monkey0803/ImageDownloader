#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SDK="${OHOS_NATIVE_HOME:-/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/native}"
TOOL="$SDK/llvm/bin"
PREFIX="$ROOT/third_party/zip-deps/arm64-v8a"
CACHE="$ROOT/third_party/zip-deps/cache"
BUILD="$ROOT/third_party/zip-deps/build"
ARCHIVE="$CACHE/openssl-3.5.2.tar.gz"
SHA256=c53a47e5e441c930c3928cf7bf6fb00e5d129b630e0aa873b08258656e7345ec

if [[ -f "$PREFIX/lib/libcrypto.a" && -f "$PREFIX/lib/libssl.a" && -f "$PREFIX/include/openssl/evp.h" ]]; then
  exit 0
fi
mkdir -p "$CACHE" "$BUILD" "$PREFIX"
if [[ ! -f "$ARCHIVE" ]]; then
  curl -fL --retry 3 -o "$ARCHIVE" \
    https://github.com/openssl/openssl/releases/download/openssl-3.5.2/openssl-3.5.2.tar.gz
fi
printf '%s  %s\n' "$SHA256" "$ARCHIVE" | shasum -a 256 -c -
tar -xzf "$ARCHIVE" -C "$BUILD"
export PATH="$TOOL:$PATH"
export CC="$TOOL/clang --target=aarch64-linux-ohos --sysroot=$SDK/sysroot"
export AR="$TOOL/llvm-ar"
export RANLIB="$TOOL/llvm-ranlib"
cd "$BUILD/openssl-3.5.2"
perl Configure linux-generic64 no-shared no-tests no-apps no-module \
  --prefix="$PREFIX" --libdir=lib -fPIC
make -j"${JOBS:-8}"
make install_sw
