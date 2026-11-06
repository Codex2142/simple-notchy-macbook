#!/usr/bin/env bash
# Removes Project Island, its launch-at-login agent, and (optionally) its local data.
# Usage: ./scripts/uninstall-app.sh [--purge-data]
set -euo pipefail

PLIST_LABEL="com.projectisland.macos.login"
PLIST_PATH="$HOME/Library/LaunchAgents/$PLIST_LABEL.plist"

pkill -f "Project Island.app/Contents/MacOS/ProjectIslandApp" 2>/dev/null || true
launchctl bootout "gui/$(id -u)" "$PLIST_PATH" 2>/dev/null || true
rm -f "$PLIST_PATH"
rm -rf "$HOME/Applications/Project Island.app"

if [ "${1:-}" = "--purge-data" ]; then
    rm -rf "$HOME/Library/Application Support/ProjectIsland"
    echo "==> Local database removed."
fi
echo "==> Project Island uninstalled."
