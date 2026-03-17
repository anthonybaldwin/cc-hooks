# Notifications

Toast notifications for [Claude Code](https://claude.com/product/claude-code) via Windows' WinRT API.

## Why not just use...

**Built-in terminal notifications?** [Windows Terminal](https://aka.ms/terminal) doesn't support Claude Code's [built-in desktop notifications](https://code.claude.com/docs/en/terminal-config#notification-setup). [Ghostty](https://ghostty.org/) and [Kitty](https://sw.kovidgoyal.net/kitty/) are not available on Windows. [WezTerm](https://wezfurlong.org/wezterm/) does run on Windows and supports built-in notifications, but clicking them only brings the window to the foreground — not the originating tab or pane ([PR #7643](https://github.com/wez/wezterm/pull/7643) is open to fix this).

**[BurntToast](https://github.com/Windos/BurntToast)?** It's a PowerShell module — every hook invocation pays PowerShell's startup cost. Click actions still require protocol handlers, and you'd need to build all the session tracking, elapsed time, and editor integration on top. This project uses the WinRT API directly from a compiled Rust binary.

## What it does

When Claude finishes or needs input, you get a toast notification showing:
- **Project directory** and **elapsed time** (e.g., "Task completed (12s)")
- **Focus Terminal** button — brings Windows Terminal to front and switches to the correct tab
- **Open in Editor** button — opens the project directory in your configured editor
- Clicking the notification body focuses the terminal
- Notifications replace by session (no stacking)
- Optional **webhook** — sends a push notification when you're AFK (idle)
- Skips IDE terminals (VS Code, Zed, Cursor) — only fires in Windows Terminal
- Per-type notification messages:

| Type | Default message | Webhook behavior |
|------|----------------|-----------------|
| `idle_prompt` | "Claude needs your input" | Only when AFK |
| `permission_prompt` | "Claude needs permission" | Always (blocks Claude) |
| `elicitation_dialog` | "Action required" | Always (blocks Claude) |
| `stop` | "Task completed" | Only when AFK |
| `auth_success` | Skipped | Skipped |

## Setup

Or just run `pwsh -NoProfile -File windows/install.ps1 notifications` from the repo root.

### Prerequisites

- [Rust](https://rustup.rs/)
- [PowerShell 7+](https://github.com/PowerShell/PowerShell) (`pwsh`)

### Build

```powershell
cd windows\notifications
cargo build --release
```

The binary is at `target\release\notifications.exe`.

### Install

```powershell
# Build, configure, register protocol handlers + AUMID, and register hooks
cd windows
pwsh -NoProfile -File install.ps1
```

A UAC prompt will appear for the notification icon/title registry entry. Declining still works — just no icon on toasts.

### Uninstall

```powershell
cd windows\notifications
.\bin\notifications.exe uninstall
```

Or just run `pwsh -NoProfile -File windows/uninstall.ps1 notifications` from the repo root.

This removes notification hooks from `~/.claude/settings.json`, protocol handlers (HKCU), AUMID registry keys, and cleans up watcher processes. A UAC prompt will appear for HKLM registry removal.

## Configuration

Copy `config.json.example` to `config.json` and edit:

```json
{
    "title": "CC Notification",
    "editor": "zed",
    "messages": {
        "notification": "Claude needs your input",
        "permission": "Claude needs permission",
        "elicitation": "Action required",
        "stop": "Task completed"
    },
    "icons": {
        "notification": "icons/notification.png",
        "stop": "icons/stop.png",
        "title": "icons/title.ico"
    },
    "webhook": {
        "url": "",
        "idle_minutes": 15,
        "payload": "webhook.json"
    }
}
```

| Field | Description |
|-------|-------------|
| `title` | Name shown in toast attribution bar (registered in HKLM during install) |
| `editor` | Editor to open projects in (`zed`, `code`, `cursor`) |

### Webhook

When configured, sends a JSON POST to the webhook URL if you're AFK (idle for `idle_minutes`). The payload is defined by a JSON template file with variable substitution.

| Field | Description |
|-------|-------------|
| `webhook.url` | Webhook endpoint (leave empty to disable) |
| `webhook.idle_minutes` | Minutes of inactivity before sending (default: 15, `0` = always send) |
| `webhook.payload` | Path to JSON template file (relative to notifications/) |

Copy one of the service-specific examples and customize (e.g., `cp webhook.discord.json.example webhook.discord.json`):
- `webhook.gotify.json.example` — [Gotify](https://gotify.net/) (URL must include `?token=<apptoken>`)
- `webhook.discord.json.example` — [Discord](https://discord.com/)
- `webhook.ntfy.json.example` — [ntfy](https://ntfy.sh/) (URL must be the root, e.g., `https://ntfy.sh/`, not the topic URL)
- `webhook.slack.json.example` — [Slack](https://slack.com/)

Available template variables:

| Variable | Description |
|----------|-------------|
| `{{title}}` | Config title or project directory name |
| `{{message}}` | Notification message (e.g., "Task completed") |
| `{{elapsed}}` | Elapsed time (e.g., "(2m 30s)") |
| `{{project}}` | Project directory name |
| `{{event}}` | Hook event type (`notification` or `stop`) |
| `{{notification_type}}` | Notification sub-type (`idle_prompt`, `permission_prompt`, `elicitation_dialog`) |

Additional data is available in the [hook payload](https://code.claude.com/docs/en/hooks) but not currently exposed as template variables: `prompt` (user's last message), `last_assistant_message` (Claude's final response), `transcript_path` (full conversation history), and `cwd` (working directory).

### Icons

Place in `icons/` (gitignored):
- `notification.png` — shown when Claude needs input
- `stop.png` — shown when Claude finishes
- `title.ico` — small icon in the notification attribution bar

## Files

| File | Purpose |
|------|---------|
| `src/main.rs` | Rust source — all hook commands, focus watcher, install/uninstall |
| `Cargo.toml` | Build configuration + dependencies |
| `config.json.example` | Example config (copy to `config.json`) |
