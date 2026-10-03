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

- **It finds the right tty.** Hooks run **without a controlling terminal**, so `printf ... > /dev/tty` fails and the color silently never lands. Instead the script walks up the process tree to the Claude process to find its real tty device (the pane's pty, e.g. `/dev/pts/3`). Everything is keyed off that pty, so the tint is per-pane and concurrent sessions never clobber each other's color.
- **tmux-aware.** Inside tmux, raw OSC 11 escapes get intercepted by tmux and don't reliably reach the pane, so the script maps the resolved pty to its tmux pane id and colors it natively with `tmux select-pane -P bg=…`. Outside tmux it falls back to an OSC 11 escape written to the pty.
- **Fullscreen-safe.** In `/tui fullscreen` Claude draws on the alternate screen but inherits the background rather than painting opaque cells, so the tint (tmux pane style or OSC 11) shows through.

## Setup

```bash
cd linux
bash install.sh session-color
```

This copies `session-color.sh` to `~/.claude/hooks/` and registers the hooks in `~/.claude/settings.json` (additive — existing hooks are preserved). Restart Claude Code to activate.

### Requirements

- Under **tmux**, nothing special — coloring uses `select-pane` (tmux 2.1+; hex colors need 2.2+).
- Otherwise, a terminal that honors OSC 11 background changes (and, for `/tui`, under the alternate screen). Most modern emulators do (e.g. GNOME Terminal/VTE, Kitty, Alacritty, WezTerm, Ghostty); `xterm` honors OSC 11 but not under the alt-screen.
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
