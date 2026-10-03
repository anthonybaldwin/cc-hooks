# Notifications

macOS desktop notifications for [Claude Code](https://claude.com/product/claude-code) using native macOS APIs.

<img width="360" height="164" alt="CleanShot 2026-06-25 at 11 41 22" src="https://github.com/user-attachments/assets/2440aaf1-2743-44ac-ac4e-996badfce202" /> <br>
<img width="352" height="90" alt="CleanShot 2026-06-25 at 11 41 35" src="https://github.com/user-attachments/assets/54159d33-c3ca-4719-9058-f265e70014fe" />

## Why not just use...

**[Built-in terminal notifications](https://code.claude.com/docs/en/terminal-config#notification-setup)?** [Ghostty](https://ghostty.org/) notifications from a split pane [open a new window](https://github.com/ghostty-org/ghostty/discussions/10445) instead of focusing the originating pane. [WezTerm](https://wezfurlong.org/wezterm/) clicking only brings the window to the foreground — not the tab or pane. [iTerm2](https://iterm2.com/)'s built-in notifications focus the correct pane but don't offer elapsed time or editor integration.

**[terminal-notifier](https://github.com/julienXX/terminal-notifier)?** No session awareness — no elapsed time, terminal focus, or editor integration. This project uses native macOS APIs and falls back to terminal-notifier if needed.

**`osascript display notification`?** No click actions.

## What it does

When Claude finishes or needs input, you get a notification showing:
- **Project directory** and **elapsed time** (e.g., "Task completed (12s)")
- Clicking the notification body focuses the correct **window/tab/pane**:
  - Ghostty: 3-pass matching (terminal+tab+window ID → CWD+name → prefix CWD)
  - iTerm2: session ID → CWD+name → prefix CWD
  - WezTerm: pane ID via CLI
  - Terminal.app: tty → process name
- **Open in Editor** button — opens the project in your configured editor
- Notifications replace by session (no stacking)
- Falls back to terminal-notifier, then `osascript` if native notifications are unavailable
- Optional **webhook** — sends to Discord, Slack, ntfy, etc. when you're AFK (screen locked or idle)
- Configurable notification sound
- Skips IDE terminals (VS Code, Zed, Cursor) — only fires in standalone terminals
- Per-type notification messages and icons (see `config.json.example`)

## Setup

```bash
cd macos
bash install.sh
```

This builds the Swift binary, assembles a `.app` bundle (required for native notifications), ad-hoc signs it, and registers hooks in `~/.claude/settings.json`.

### Prerequisites

- macOS 12+
- Swift 5.9+ (`xcode-select --install` if needed)
- Optional: [terminal-notifier](https://github.com/julienXX/terminal-notifier) (`brew install terminal-notifier`) as a fallback

### Uninstall

```bash
cd macos/notifications
.build/release/notifications uninstall
```

Removes hooks from `~/.claude/settings.json` and cleans up temp files.

## Configuration

Copy `config.json.example` to `config.json` and edit:

```json
{
    "title": "Claude Code",
    "terminal": "ghostty",
    "editor": "zed",
    "desktop": true,
    "sound": "default",
    "messages": {
        "notification": "Claude needs your input",
        "permission": "Claude needs permission",
        "elicitation": "Action required",
        "idle": "Claude is waiting",
        "stop": "Task completed"
    },
    "icons": {
        "app": "icons/AppIcon.png",
        "notification": "icons/notification.png",
        "permission": "icons/notification.png",
        "elicitation": "icons/notification.png",
        "idle": "icons/notification.png",
        "stop": "icons/stop.png"
    },
    "webhook": {
        "enabled": true,
        "url": "",
        "idle_minutes": 15,
        "payload": "webhook.discord.json"
    }
}
```

| Field | Description |
|-------|-------------|
| `title` | Name shown in the .app bundle and notification attribution |
| `terminal` | Terminal to focus on click (`ghostty`, `iterm2`, `wezterm`, `terminal`) |
| `editor` | Editor to open projects in (`zed`, `code`, `cursor`) |
| `desktop` | Set to `false` to skip desktop notifications (webhook-only mode) |
| `sound` | `"default"`, a sound name (see below), or `""` to disable |

#### Sound names

macOS uses sounds from `/System/Library/Sounds/` and `~/Library/Sounds/`. Built-in options:

`Basso`, `Blow`, `Bottle`, `Frog`, `Funk`, `Glass`, `Hero`, `Morse`, `Ping`, `Pop`, `Purr`, `Sosumi`, `Submarine`, `Tink`

Drop a `.aiff`, `.wav`, or `.caf` file in `~/Library/Sounds/` to use a custom sound.

### Icons

Place in `icons/` (gitignored). Each notification type can have its own icon — see `config.json.example` for all slots. Types without a specific icon fall back to `notification`.

### Webhook

Sends a JSON POST when you're AFK (screen locked or idle for `idle_minutes`). Useful for Discord, Slack, ntfy, Gotify, etc.

| Field | Description |
|-------|-------------|
| `webhook.enabled` | Set to `false` to disable without removing config |
| `webhook.url` | Webhook endpoint (leave empty to disable) |
| `webhook.idle_minutes` | Minutes of inactivity before sending (default: 15, `0` = always send) |
| `webhook.payload` | Path to JSON template file (relative to notifications/) |

Copy a service-specific example and customize:
- `webhook.discord.json.example` — [Discord](https://discord.com/)
- `webhook.slack.json.example` — [Slack](https://slack.com/)
- `webhook.ntfy.json.example` — [ntfy](https://ntfy.sh/)
- `webhook.gotify.json.example` — [Gotify](https://gotify.net/)

Template variables: `{{title}}`, `{{message}}`, `{{elapsed}}`, `{{project}}`, `{{event}}`, `{{notification_type}}`

## Files

| File | Purpose |
|------|---------|
| `Sources/main.swift` | Swift source — all hook commands, notification handling, install/uninstall |
| `Package.swift` | Swift Package Manager build config |
| `Info.plist` | App bundle metadata (agent app, bundle ID, macOS version) |
| `config.json.example` | Example config (copy to `config.json`) |
