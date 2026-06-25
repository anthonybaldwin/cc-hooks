#!/usr/bin/env bash
# CC Hooks — macOS Install
#
# Run: bash install.sh                # install all hooks
#      bash install.sh notifications  # install a specific hook
#      bash install.sh session-color

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

install_notifications() {
    local NOTIF_DIR="$SCRIPT_DIR/notifications"

    # Copy config if it doesn't exist
    if [[ ! -f "$NOTIF_DIR/config.json" ]]; then
        cp "$NOTIF_DIR/config.json.example" "$NOTIF_DIR/config.json"
        echo "Created config.json from example — edit to configure terminal/editor"
    fi

    # Read title from config (default: "CC Notification")
    local TITLE
    TITLE=$(python3 -c "import json; print(json.load(open('$NOTIF_DIR/config.json')).get('title', 'CC Notification'))" 2>/dev/null || echo "CC Notification")

    local APP_DIR="$NOTIF_DIR/bin/$TITLE.app"
    local EXE="$APP_DIR/Contents/MacOS/notifications"

    # Build
    echo "Building..."
    cd "$NOTIF_DIR"
    swift build -c release 2>&1 | tail -3

    # Assemble .app bundle
    rm -rf "$APP_DIR"
    mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
    cp .build/release/notifications "$EXE"

    # Copy app icon if available (configurable via icons.app in config.json)
    local APP_ICON
    APP_ICON=$(python3 -c "import json; print(json.load(open('$NOTIF_DIR/config.json')).get('icons', {}).get('app', 'icons/AppIcon.png'))" 2>/dev/null || echo "icons/AppIcon.png")
    if [[ -f "$NOTIF_DIR/$APP_ICON" ]]; then
        cp "$NOTIF_DIR/$APP_ICON" "$APP_DIR/Contents/Resources/AppIcon.png"
    fi

    # Generate Info.plist with title from config
    python3 -c "
import sys
with open(sys.argv[1]) as f: plist = f.read()
print(plist.replace('CC Notifications', sys.argv[2]), end='')
" "$NOTIF_DIR/Info.plist" "$TITLE" > "$APP_DIR/Contents/Info.plist"

    # Ad-hoc sign the bundle
    if ! codesign --force --sign - "$APP_DIR"; then
        echo "Warning: ad-hoc code signing failed — notifications may not work correctly"
    fi

    # Register hooks
    "$EXE" install
}

install_session_color() {
    bash "$SCRIPT_DIR/session-color/install.sh"
}

target="${1:-all}"
case "$target" in
    all)           install_notifications; install_session_color ;;
    notifications) install_notifications ;;
    session-color) install_session_color ;;
    *) echo "Unknown hook: $target (expected: notifications, session-color)"; exit 1 ;;
esac

echo "Done! Restart Claude Code to activate hooks."
