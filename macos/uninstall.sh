#!/usr/bin/env bash
# CC Hooks — macOS Uninstall
#
# Run: bash uninstall.sh
#
# Removes hooks from ~/.claude/settings.json and cleans up temp files.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NOTIF_DIR="$SCRIPT_DIR/notifications"

# Read title from config (default: "CC Notification")
TITLE=$(python3 -c "import json; print(json.load(open('$NOTIF_DIR/config.json')).get('title', 'CC Notification'))" 2>/dev/null || echo "CC Notification")

EXE="$NOTIF_DIR/bin/$TITLE.app/Contents/MacOS/notifications"

if [[ -x "$EXE" ]]; then
    "$EXE" uninstall
else
    echo "Binary not found — nothing to uninstall"
fi
