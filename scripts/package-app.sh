#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

export TMPDIR="/tmp"
export CLANG_MODULE_CACHE_PATH="/tmp/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="/tmp/swiftpm-module-cache"

echo "==> [1/3] Building Rust core & generating Swift UniFFI bindings..."
./scripts/build-rust-macos.sh

echo "==> [2/3] Compiling ProjectIslandApp executable..."
swift build --disable-sandbox \
    --package-path "$ROOT_DIR/apps/macos" \
    --cache-path /tmp/swiftpm-cache \
    --scratch-path /tmp/swiftpm-build \
    -Xcc -fmodules-cache-path=/tmp/clang-module-cache \
    -Xswiftc -module-cache-path -Xswiftc /tmp/clang-module-cache \
    --product ProjectIslandApp

APP_DIR="$ROOT_DIR/build/Project Island.app"
echo "==> [3/3] Packaging macOS bundle at: $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp /tmp/swiftpm-build/debug/ProjectIslandApp "$APP_DIR/Contents/MacOS/ProjectIslandApp"
chmod +x "$APP_DIR/Contents/MacOS/ProjectIslandApp"

# Bundle the Rust bridge dylib inside the .app so it no longer depends on the repo location.
mkdir -p "$APP_DIR/Contents/Frameworks"
cp "$ROOT_DIR/target/debug/libisland_bridge.dylib" "$APP_DIR/Contents/Frameworks/libisland_bridge.dylib"
OLD_DYLIB_PATH="$(otool -L "$APP_DIR/Contents/MacOS/ProjectIslandApp" | awk '/libisland_bridge.dylib/ {print $1}' | head -n 1)"
install_name_tool -id "@rpath/libisland_bridge.dylib" "$APP_DIR/Contents/Frameworks/libisland_bridge.dylib"
if [ -n "$OLD_DYLIB_PATH" ]; then
    install_name_tool -change "$OLD_DYLIB_PATH" "@executable_path/../Frameworks/libisland_bridge.dylib" \
        "$APP_DIR/Contents/MacOS/ProjectIslandApp"
fi

cat > "$APP_DIR/Contents/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>ProjectIslandApp</string>
    <key>CFBundleIdentifier</key>
    <string>com.projectisland.macos</string>
    <key>CFBundleName</key>
    <string>Project Island</string>
    <key>CFBundleDisplayName</key>
    <string>Project Island</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.2.0</string>
    <key>CFBundleVersion</key>
    <string>2</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>Project Island membutuhkan izin untuk membaca lagu dan mengontrol pemutaran musik di Spotify serta Apple Music.</string>
</dict>
</plist>
EOF

ENTITLEMENTS_FILE="/tmp/project-island-entitlements.plist"
cat > "$ENTITLEMENTS_FILE" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.automation.apple-events</key>
    <true/>
</dict>
</plist>
EOF

codesign --force --deep --entitlements "$ENTITLEMENTS_FILE" --sign - "$APP_DIR" >/dev/null 2>&1 || true

echo "==> Done! App bundle created at: $APP_DIR"
echo "    Run with: open \"$APP_DIR\""
