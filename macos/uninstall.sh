#!/usr/bin/env bash
# CC Hooks — macOS Uninstall
#
# Run: bash uninstall.sh                # uninstall all hooks
#      bash uninstall.sh notifications  # uninstall a specific hook
#      bash uninstall.sh session-color
#
# Removes hooks from ~/.claude/settings.json and cleans up temp files.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

uninstall_notifications() {
    local NOTIF_DIR="$SCRIPT_DIR/notifications"

    # Read title from config (default: "CC Notification")
    local TITLE
    TITLE=$(python3 -c "import json; print(json.load(open('$NOTIF_DIR/config.json')).get('title', 'CC Notification'))" 2>/dev/null || echo "CC Notification")

    local EXE="$NOTIF_DIR/bin/$TITLE.app/Contents/MacOS/notifications"

    if [[ -x "$EXE" ]]; then
        "$EXE" uninstall
    else
        echo "Notifications binary not found — nothing to uninstall"
    fi
}

uninstall_session_color() {
    bash "$SCRIPT_DIR/session-color/uninstall.sh"
}

target="${1:-all}"
case "$target" in
    all)           uninstall_notifications; uninstall_session_color ;;
    notifications) uninstall_notifications ;;
    session-color) uninstall_session_color ;;
    *) echo "Unknown hook: $target (expected: notifications, session-color)"; exit 1 ;;
esac
