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

The tint is a single [OSC 11](https://invisible-island.net/xterm/ctlseqs/ctlseqs.html#h3-Operating-System-Commands) escape (`ESC ] 11 ; #rrggbb BEL`) written to the terminal. The catch on Windows is *getting the escape to the right pane*:

- Hooks run with their **stdout captured by Claude Code**, so a plain `print!` never reaches the terminal. There's no `/dev/tty` on Windows either.
- Instead the hook walks up the process tree to the `claude` process, `AttachConsole()`s to **its** console — which is the pane's pseudoconsole ([ConPTY](https://devblogs.microsoft.com/commandline/windows-command-line-introducing-the-windows-pseudo-console-conpty/)) — and writes the escape to `CONOUT$`. ConPTY then relays it to the terminal. Because the ConPTY is per-pane, concurrent sessions never clobber each other's color.

> **Heads up:** this relies on ConPTY forwarding OSC 11 background changes through to the terminal. Recent **Windows 11 + Windows Terminal** honor it; older Windows builds may swallow the sequence (in which case the tint silently won't appear). Test on your machine and tweak the hex values to taste.

## Setup

```powershell
cd windows
pwsh -NoProfile -File install.ps1 session-color
```

This builds `session-color.exe` (`cargo build --release`) and registers the hooks in `~/.claude/settings.json` (additive — existing hooks like [notifications](../notifications/) are preserved). Restart Claude Code to activate.

### Requirements

- [Rust](https://rustup.rs/) (to build) and [PowerShell 7+](https://github.com/PowerShell/PowerShell) (`pwsh`)
- [Windows Terminal](https://github.com/microsoft/terminal) on a recent Windows 11 build (for ConPTY OSC 11 passthrough)

### Uninstall

```powershell
cd windows
pwsh -NoProfile -File uninstall.ps1 session-color
```

## Customizing

Edit the hex values near the top of `src/main.rs` (in `paint()`), then re-run `install.ps1 session-color` to rebuild. Keep them dim — they fill the whole pane, so bright values hurt text contrast.

```rust
let seq: &[u8] = match state {
    "working" => b"\x1b]11;#574515\x07", // amber — working
    "needs"   => b"\x1b]11;#501d22\x07", // red   — needs you (blocking)
    "done"    => b"\x1b]11;#233f20\x07", // green — done / idle, your move
    _         => b"\x1b]111\x07",        // reset bg to terminal default
};
```

To change which status a given event maps to, edit `MAPPING` in `src/main.rs` and re-run the installer.
