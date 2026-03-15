#!/usr/bin/env bash
# CC Hooks — macOS Install
#
# Run: bash install.sh
#
# Builds the Swift binary, copies config if needed, and merges
# hook config into ~/.claude/settings.json (via the binary itself,
# no python dependency).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NOTIF_DIR="$SCRIPT_DIR/notifications"
BIN_DIR="$NOTIF_DIR/bin"
EXE="$BIN_DIR/notifications"

# Build
echo "Building..."
cd "$NOTIF_DIR"
swift build -c release 2>&1 | tail -3
mkdir -p "$BIN_DIR"
cp .build/release/notifications "$EXE"

# Copy config if it doesn't exist
if [[ ! -f "$NOTIF_DIR/config.json" ]]; then
    cp "$NOTIF_DIR/config.json.example" "$NOTIF_DIR/config.json"
    echo "Created config.json from example — edit to configure terminal/editor"
fi

# Register hooks
"$EXE" install

echo "Done! Restart Claude Code to activate hooks."
