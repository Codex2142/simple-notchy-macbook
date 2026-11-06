#!/usr/bin/env bash
# Installs Project Island into /Applications (or ~/Applications) and registers it to launch at login.
# Usage: ./scripts/install-app.sh [--release] [--system] [--user] [--no-login-item]
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ENABLE_LOGIN=1
PACKAGE_FLAGS=()
DEST_DIR="/Applications"

for arg in "$@"; do
    case "$arg" in
        --release)
            PACKAGE_FLAGS=(--release)
            ;;
        --no-login-item)
            ENABLE_LOGIN=0
            ;;
        --user)
            DEST_DIR="$HOME/Applications"
            ;;
        --system)
            DEST_DIR="/Applications"
            ;;
    esac
done

# If installing to /Applications and directory is not writable without sudo, fallback or prompt
if [ "$DEST_DIR" = "/Applications" ] && [ ! -w "/Applications" ]; then
    echo "Notice: /Applications is not writable by current user without elevated permissions."
    echo "Installing to $HOME/Applications instead (use --system with sudo if preferred)."
    DEST_DIR="$HOME/Applications"
fi

./scripts/package-app.sh "${PACKAGE_FLAGS[@]}"

SRC_APP="$ROOT_DIR/build/Project Island.app"
DEST_DIR="$HOME/Applications"
DEST_APP="$DEST_DIR/Project Island.app"

echo "==> Installing to $DEST_APP"
pkill -f "Project Island.app/Contents/MacOS/ProjectIslandApp" 2>/dev/null || true
mkdir -p "$DEST_DIR"
rm -rf "$DEST_APP"
cp -R "$SRC_APP" "$DEST_APP"
xattr -dr com.apple.quarantine "$DEST_APP" 2>/dev/null || true

PLIST_LABEL="com.projectisland.macos.login"
PLIST_PATH="$HOME/Library/LaunchAgents/$PLIST_LABEL.plist"
UID_NUM="$(id -u)"

if [ "$ENABLE_LOGIN" -eq 1 ]; then
    echo "==> Registering launch-at-login (LaunchAgent: $PLIST_PATH)"
    mkdir -p "$HOME/Library/LaunchAgents"
    cat > "$PLIST_PATH" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$PLIST_LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/open</string>
        <string>-a</string>
        <string>$DEST_APP</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>LimitLoadToSessionType</key>
    <string>Aqua</string>
</dict>
</plist>
EOF
    launchctl bootout "gui/$UID_NUM" "$PLIST_PATH" 2>/dev/null || true
    launchctl bootstrap "gui/$UID_NUM" "$PLIST_PATH"
fi

echo "==> Launching Project Island"
open -a "$DEST_APP"
echo "==> Done."
