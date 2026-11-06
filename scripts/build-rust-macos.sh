#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

export PATH="/opt/homebrew/bin:$HOME/.cargo/bin:$PATH"

echo "==> Building island-bridge (debug staticlib + cdylib)..."
cargo build --offline -p island-bridge

OUT_SWIFT_DIR="$ROOT_DIR/apps/macos/Sources/Bridge/Generated"
OUT_C_DIR="$ROOT_DIR/apps/macos/Sources/CIslandBridge/include"
mkdir -p "$OUT_SWIFT_DIR" "$OUT_C_DIR"

echo "==> Generating Swift UniFFI bindings..."
cargo run --offline -p island-bridge --bin uniffi-bindgen -- generate \
    --library "$ROOT_DIR/target/debug/libisland_bridge.dylib" \
    --metadata-no-deps \
    --no-format \
    --language swift \
    --out-dir "$OUT_SWIFT_DIR"

mv -f "$OUT_SWIFT_DIR/island_bridgeFFI.h" "$OUT_C_DIR/island_bridgeFFI.h"
cat > "$OUT_C_DIR/module.modulemap" << 'EOF'
module island_bridgeFFI {
    header "island_bridgeFFI.h"
    export *
}
EOF
rm -f "$OUT_SWIFT_DIR/island_bridgeFFI.modulemap"

cat > "$ROOT_DIR/apps/macos/Sources/CIslandBridge/shim.c" << 'EOF'
// Empty C translation unit for SwiftPM C target wrapping island_bridgeFFI.h
EOF

echo "==> UniFFI Swift bindings generated in $OUT_SWIFT_DIR and headers in $OUT_C_DIR"
