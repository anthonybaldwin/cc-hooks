# Session Color

Tint the terminal background by [Claude Code](https://claude.com/product/claude-code) session status, so you can tell at a glance — across a wall of panes — which session is working, which needs you, and which is done.

| State | Color | Fires on |
|-------|-------|----------|
| 🟡 **working** | amber | `UserPromptSubmit`, `PostToolUse`, `PostToolUseFailure`, `ElicitationResult` |
| 🔴 **needs you** | red | `PermissionRequest`, `Elicitation` |
| 🟢 **done / idle** | green | `Stop` |
| ⬛ **reset** | default | `SessionStart`, `SessionEnd` |

It flips **back** to amber after a red prompt (via `PostToolUse`), so a session that asked for permission mid-task doesn't get stuck looking like it still needs you.

Red is reserved for *actual* blocking decisions (`PermissionRequest`, `Elicitation`). The `Notification` event is deliberately left unwired: it fires for `permission_prompt`, `idle_prompt`, `elicitation_*`, and `auth_success` — every one already covered by a more specific event above. In particular `idle_prompt` (idle ~60s after finishing) would just repaint an already-green session, so coloring on `Notification` adds nothing but conflicts.

## How it works

The tint is a single [OSC 11](https://invisible-island.net/xterm/ctlseqs/ctlseqs.html#h3-Operating-System-Commands) escape (`ESC ] 11 ; #rrggbb BEL`) written to the terminal. Two things make it work where a naive approach fails:

- **Fullscreen-safe.** In `/tui fullscreen` Claude draws on the alternate screen but inherits the terminal's background rather than painting opaque cells, so an OSC 11 background change shows through, on terminals that honor OSC 11 under the alt-screen.
- **It finds the right tty.** Hooks run **without a controlling terminal**, so `printf ... > /dev/tty` fails and the color silently never lands. Instead the script walks up the process tree to the Claude process and writes to its real tty device (the pane's pty, e.g. `/dev/pts/3`). Because that device is per-pane, concurrent sessions never clobber each other's color.

## Setup

```bash
cd linux
bash install.sh session-color
```

This copies `session-color.sh` to `~/.claude/hooks/` and registers the hooks in `~/.claude/settings.json` (additive — existing hooks are preserved). Restart Claude Code to activate.

### Requirements

- A terminal that honors OSC 11 background changes (and, for `/tui`, under the alternate screen). Most modern emulators do (e.g. GNOME Terminal/VTE, Kitty, Alacritty, WezTerm, Ghostty); `xterm` honors OSC 11 but not under the alt-screen.
- `python3` (used by the installer to edit `settings.json`).

### Uninstall

```bash
cd linux
bash uninstall.sh session-color
```

## Customizing

Edit the hex values at the top of `session-color.sh` (then re-run `install.sh session-color` to copy the change into `~/.claude/hooks/`). Keep them dim — they fill the whole pane, so bright values hurt text contrast.

```sh
case "$1" in
  working) seq='\033]11;#574515\007' ;;   # amber — working
  needs)   seq='\033]11;#501d22\007' ;;   # red   — needs you (blocking)
  done)    seq='\033]11;#233f20\007' ;;   # green — done / idle
  reset|*) seq='\033]111\007'        ;;   # reset bg to terminal default
esac
```

To change which status a given event maps to, edit `MAPPING` in `install.sh` and re-run it.
