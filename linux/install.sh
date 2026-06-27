#!/usr/bin/env bash
# CC Hooks — Linux Install
#
# Run: bash install.sh                # install all hooks
#      bash install.sh session-color  # install a specific hook
#
# Note: Linux currently ships the session-color hook only. Desktop
# notifications are not implemented here yet (see the repo README).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

install_session_color() {
    bash "$SCRIPT_DIR/session-color/install.sh"
}

target="${1:-all}"
case "$target" in
    all)           install_session_color ;;
    session-color) install_session_color ;;
    *) echo "Unknown hook: $target (expected: session-color)"; exit 1 ;;
esac

echo "Done! Restart Claude Code to activate hooks."
