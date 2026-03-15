#!/usr/bin/env bash
# CC Hooks — macOS Uninstall
#
# Run: bash uninstall.sh
#
# Removes hooks from ~/.claude/settings.json and cleans up temp files.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EXE="$SCRIPT_DIR/notifications/bin/notifications"

if [[ -x "$EXE" ]]; then
    "$EXE" uninstall
else
    echo "Binary not found — nothing to uninstall"
fi
