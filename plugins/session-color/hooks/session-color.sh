#!/bin/sh
# session-color — hook dispatcher. hooks.json runs this for every wired event with one argument,
# the state to paint (working | needs | done | reset); it hands off to the platform implementation.
#
# WHY A DISPATCHER: a plugin's hooks.json is one file for every OS, with no per-platform branching,
# while the tint is delivered three different ways (OSC 11 to the pane's pty on macOS, tmux-native
# pane style or OSC 11 on Linux, a ConPTY console attach from a native exe on Windows). `sh` is the
# one runtime every Claude Code install has — Git Bash provides it on Windows — so this stays a
# POSIX script, and it `exec`s the implementation so the process tree the implementations walk
# (up to the `claude` process, to find its tty / console) is unchanged.
#
# Always exits 0: a hook failure here must never surface in the session.
state="${1:-reset}"
here="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)" # the plugin root

case "$(uname -s 2>/dev/null)" in
  MINGW*|MSYS*|CYGWIN*)
    # Windows: the Rust exe lives in the plugin's persistent data dir, where /session-color:setup
    # builds it (the plugin root is a per-version cache path, and it holds only source). Until
    # setup has run there's nothing to paint with — stay silent. The env var may carry backslashes;
    # MSYS sh is happier with forward slashes.
    data="$(printf '%s' "${CLAUDE_PLUGIN_DATA:-}" | tr '\\' '/')"
    exe="$data/session-color.exe"
    [ -n "$data" ] && [ -f "$exe" ] || exit 0
    exec "$exe" "$state"
    ;;
  Darwin) exec sh "$here/macos/session-color.sh" "$state" ;;
  Linux)  exec sh "$here/linux/session-color.sh" "$state" ;;
esac
exit 0
