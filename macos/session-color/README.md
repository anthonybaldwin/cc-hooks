# Session Color

Tint the terminal background by [Claude Code](https://claude.com/product/claude-code) session status, so you can tell at a glance — across a wall of panes — which session is working, which needs you, and which is done.

<img width="30%" alt="CleanShot 2026-06-25 at 11 47 51" src="https://github.com/user-attachments/assets/ed8736db-05dd-4cb4-8418-e60c32ea8f3b" /> 
<img width="30%" alt="CleanShot 2026-06-25 at 11 49 41" src="https://github.com/user-attachments/assets/cde1bc8e-248f-456c-b5f4-57f06c34f78d" />
<img width="30%" alt="CleanShot 2026-06-25 at 11 47 55" src="https://github.com/user-attachments/assets/48705014-a675-432c-9d19-d19f253e2a1c" />

| State | Color | Fires on |
|-------|-------|----------|
| 🟡 **working** | amber | `UserPromptSubmit`, `PostToolUse`, `PostToolUseFailure`, `ElicitationResult` |
| 🔴 **needs you** | red | `PermissionRequest`, `Elicitation` |
| 🔵 **done / idle** | subtle blue | `Stop`, `Notification` |
| ⬛ **reset** | default | `SessionStart`, `SessionEnd` |

It flips **back** to amber after a red prompt (via `PostToolUse`), so a session that asked for permission mid-task doesn't get stuck looking like it still needs you.

Red is reserved for *actual* blocking decisions (`PermissionRequest`, `Elicitation`). `Notification` maps to the calm blue instead of red, because it also fires when a session simply goes idle after finishing — coloring that red would cry wolf and drown out the sessions that genuinely need you.

## How it works

The tint is a single [OSC 11](https://invisible-island.net/xterm/ctlseqs/ctlseqs.html#h3-Operating-System-Commands) escape (`ESC ] 11 ; #rrggbb BEL`) written to the terminal. Two things make it work where a naive approach fails:

- **Fullscreen-safe.** In `/tui fullscreen` Claude draws on the alternate screen but inherits the terminal's background rather than painting opaque cells, so an OSC 11 background change shows through. (Confirmed in [Ghostty](https://ghostty.org/); other terminals that honor OSC 11 under the alt-screen should work too.)
- **It finds the right tty.** Hooks run **without a controlling terminal**, so `printf ... > /dev/tty` fails with `Device not configured` and the color silently never lands. Instead the script walks up the process tree to the Claude process and writes to its real tty device (the pane's pty). Because that device is per-pane, concurrent sessions never clobber each other's color.

## Setup

```bash
cd macos
bash install.sh session-color
```

This copies `session-color.sh` to `~/.claude/hooks/` and registers the hooks in `~/.claude/settings.json` (additive — existing hooks like [notifications](../notifications/) are preserved). Restart Claude Code to activate.

### Requirements

- A terminal that honors OSC 11 background changes under the alternate screen (e.g. Ghostty).
- `python3` (used by the installer to edit `settings.json`).

### Uninstall

```bash
cd macos
bash uninstall.sh session-color
```

## Customizing

Edit the hex values at the top of `session-color.sh` (then re-run `install.sh session-color` to copy the change into `~/.claude/hooks/`). Keep them dim — they fill the whole pane, so bright values hurt text contrast.

```sh
case "$1" in
  working) seq='\033]11;#574515\007' ;;   # amber — working
  needs)   seq='\033]11;#501d22\007' ;;   # red   — needs you (blocking)
  done)    seq='\033]11;#1e3050\007' ;;   # subtle blue — done / idle
  reset|*) seq='\033]111\007'        ;;   # reset bg to terminal default
esac
```

To change which status a given event maps to, edit `MAPPING` in `install.sh` and re-run it.
