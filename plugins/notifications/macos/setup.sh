#!/usr/bin/env bash
# notifications — macOS setup (run by the /notifications:setup skill)
#
#   bash setup.sh --data <CLAUDE_PLUGIN_DATA>              build + stage the .app bundle
#   bash setup.sh --data <CLAUDE_PLUGIN_DATA> --uninstall  remove it
#
# Builds the Swift binary, assembles it into a <Title>.app bundle (required for native
# UserNotifications), ad-hoc signs it, and stages the bundle in the plugin's persistent data dir.
# The hook dispatcher (hooks/notifications.sh) runs the binary from THERE: the plugin root is a
# per-version cache path that moves on every update, the data dir is stable. config.json, icons/
# and the webhook templates live in the data dir too — the binary finds config.json by walking up
# from its own location, and the bundle sits directly under the data dir.
#
# Never touches ~/.claude/settings.json: the hooks come from the plugin's hooks.json (and go away
# with `/plugin uninstall`). This replaces the old `notifications install` step.

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"   # <plugin root>/macos
DATA=""
UNINSTALL=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --data) DATA="$2"; shift 2 ;;
        --uninstall|-u) UNINSTALL=1; shift ;;
        *) echo "Unknown argument: $1"; exit 1 ;;
    esac
done
[[ -n "$DATA" ]] || { echo "Usage: setup.sh --data <CLAUDE_PLUGIN_DATA> [--uninstall]"; exit 1; }

read_config() { # read_config <key> <default>  — top-level string from config.json
    python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get(sys.argv[2], sys.argv[3]))" \
        "$DATA/config.json" "$1" "$2" 2>/dev/null || echo "$2"
}

if [[ $UNINSTALL -eq 1 ]]; then
    # A notify handler may still be blocking on a visible notification.
    pkill -f "$DATA/.*\.app/Contents/MacOS/notifications" 2>/dev/null || true
    rm -f /tmp/claude-timer-* /tmp/claude-notifier-* 2>/dev/null || true
    shopt -s nullglob
    for app in "$DATA"/*.app; do rm -rf "$app"; echo "Removed $app"; done
    echo "Done. Config and icons in $DATA are kept; run /plugin uninstall notifications@cc-plugins to remove the hooks (and the data dir)."
    exit 0
fi

command -v swift >/dev/null 2>&1 || { echo "swift not found — install the Xcode Command Line Tools (xcode-select --install) and re-run."; exit 1; }

mkdir -p "$DATA/icons"

# Seed config + webhook templates (never overwrite the user's).
if [[ ! -f "$DATA/config.json" ]]; then
    cp "$SRC_DIR/config.json.example" "$DATA/config.json"
    echo "Created $DATA/config.json from the example — edit it to set terminal/editor/webhook"
fi
for tpl in "$SRC_DIR"/webhook.*.json.example; do
    [[ -f "$DATA/$(basename "$tpl")" ]] || cp "$tpl" "$DATA/"
done

TITLE="$(read_config title "CC Notification")"
APP_DIR="$DATA/$TITLE.app"
EXE="$APP_DIR/Contents/MacOS/notifications"

# Build — scratch path in the data dir so nothing lands in the per-version plugin root.
echo "Building..."
swift build -c release --package-path "$SRC_DIR" --scratch-path "$DATA/build/notifications" 2>&1 | tail -3

# Assemble the .app bundle (drop any stale bundle first, e.g. after a title change).
pkill -f "$DATA/.*\.app/Contents/MacOS/notifications" 2>/dev/null || true
shopt -s nullglob
for old in "$DATA"/*.app; do rm -rf "$old"; done
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$DATA/build/notifications/release/notifications" "$EXE"

# App icon, if present (configurable via icons.app in config.json; paths are relative to the data dir).
APP_ICON="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('icons', {}).get('app', 'icons/AppIcon.png'))" "$DATA/config.json" 2>/dev/null || echo "icons/AppIcon.png")"
[[ -f "$DATA/$APP_ICON" ]] && cp "$DATA/$APP_ICON" "$APP_DIR/Contents/Resources/AppIcon.png"

# Info.plist with the configured title.
python3 -c "
import sys
with open(sys.argv[1]) as f: plist = f.read()
print(plist.replace('CC Notifications', sys.argv[2]), end='')
" "$SRC_DIR/Info.plist" "$TITLE" > "$APP_DIR/Contents/Info.plist"

codesign --force --sign - "$APP_DIR" || echo "Warning: ad-hoc code signing failed — notifications may not work correctly"

echo "Staged $APP_DIR"
echo "Done! Restart Claude Code to activate (the hooks are already registered by the plugin)."
echo "On first notification macOS asks for permission; optional: brew install terminal-notifier as a fallback."
