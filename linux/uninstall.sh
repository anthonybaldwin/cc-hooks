#!/usr/bin/env bash
# CC Hooks — Linux Uninstall
#
# Run: bash uninstall.sh                # uninstall all hooks
#      bash uninstall.sh session-color  # uninstall a specific hook
#
# Removes hooks from ~/.claude/settings.json.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

uninstall_session_color() {
    bash "$SCRIPT_DIR/session-color/uninstall.sh"
}

target="${1:-all}"
case "$target" in
    all)           uninstall_session_color ;;
    session-color) uninstall_session_color ;;
    *) echo "Unknown hook: $target (expected: session-color)"; exit 1 ;;
esac
