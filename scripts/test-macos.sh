#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

export TMPDIR="/tmp"
export CLANG_MODULE_CACHE_PATH="/tmp/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="/tmp/swiftpm-module-cache"

echo "==> Building ProjectIslandApp & libraries..."
swift build --disable-sandbox \
    --package-path "$ROOT_DIR/apps/macos" \
    --cache-path /tmp/swiftpm-cache \
    --scratch-path /tmp/swiftpm-build \
    -Xcc -fmodules-cache-path=/tmp/clang-module-cache \
    -Xswiftc -module-cache-path -Xswiftc /tmp/clang-module-cache \
    --product ProjectIslandApp

echo "==> Running IslandSelfTest..."
swift run --disable-sandbox \
    --package-path "$ROOT_DIR/apps/macos" \
    --cache-path /tmp/swiftpm-cache \
    --scratch-path /tmp/swiftpm-build \
    -Xcc -fmodules-cache-path=/tmp/clang-module-cache \
    -Xswiftc -module-cache-path -Xswiftc /tmp/clang-module-cache \
    IslandSelfTest
