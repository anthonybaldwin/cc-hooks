# Notifications

macOS desktop notifications for [Claude Code](https://claude.com/product/claude-code) using native macOS APIs.

## Why not just use...

**[Built-in terminal notifications](https://code.claude.com/docs/en/terminal-config#notification-setup)?** [Ghostty](https://ghostty.org/), [Kitty](https://sw.kovidgoyal.net/kitty/), and [WezTerm](https://wezfurlong.org/wezterm/) support them natively, but the click-to-focus behavior is limited. On macOS, clicking a Ghostty notification from a split pane [opens a new window](https://github.com/ghostty-org/ghostty/discussions/10445) instead of focusing the originating pane. The Linux fix ([#9145](https://github.com/ghostty-org/ghostty/issues/9145)) hasn't been ported to macOS yet. WezTerm shows notifications but clicking them only brings the window to the foreground — not the originating tab or pane ([PR #7643](https://github.com/wez/wezterm/pull/7643) is open to fix this). [iTerm2](https://iterm2.com/)'s built-in notifications (Settings → Profiles → Terminal → Notification Center Alerts) do focus the correct session/pane on click, but don't offer elapsed time or editor integration.

**[terminal-notifier](https://github.com/julienXX/terminal-notifier)?** It can show notifications, but doesn't know about Claude Code sessions — no elapsed time, no terminal focus, no editor integration. This project uses native macOS APIs directly and falls back to terminal-notifier if needed.

**`osascript display notification`?** No click actions at all — it's a fire-and-forget alert.

<!-- TODO: Verify if Ghostty has fixed macOS notification focus
     https://github.com/ghostty-org/ghostty/issues/9145
     https://github.com/ghostty-org/ghostty/discussions/10445
     TODO: Verify if WezTerm has merged click-to-focus
     https://github.com/wez/wezterm/pull/7643 -->

## What it does

When Claude finishes or needs input, you get a notification showing:
- **Project directory** and **elapsed time** (e.g., "Task completed (12s)")
- Clicking the notification body focuses the correct terminal **window/tab/pane**
  - Ghostty (1.3.0+): matched by terminal ID, fallback to working directory
  - iTerm2: matched by session ID, fallback to tty device
  - [WezTerm](https://wezfurlong.org/wezterm/): matched by pane ID via CLI
  - [Terminal.app](https://support.apple.com/guide/terminal/welcome/mac): matched by tty device
- **Open in Editor** button — opens the project directory in your configured editor
- Notifications replace by session (no stacking)
- Falls back to terminal-notifier, then `osascript` if native notifications are unavailable
- Optional **webhook** — sends a push notification when you're AFK (screen locked or idle)
- Skips IDE terminals (VS Code, Zed, Cursor) — only fires in standalone terminals
- Per-type notification messages:

| Type | Default message | Webhook behavior |
|------|----------------|-----------------|
| `idle_prompt` | "Claude needs your input" | Only when AFK |
| `permission_prompt` | "Claude needs permission" | Always (blocks Claude) |
| `elicitation_dialog` | "Action required" | Always (blocks Claude) |
| `stop` | "Task completed" | Only when AFK |
| `auth_success` | Skipped | Skipped |

## Setup

Or just run `bash macos/install.sh notifications` from the repo root.

### Prerequisites

- macOS 12+
- Swift 5.9+ (`xcode-select --install` if needed)
- Optional: [terminal-notifier](https://github.com/julienXX/terminal-notifier) (`brew install terminal-notifier`) as a fallback

### Build

```bash
cd macos/notifications
swift build -c release
```

The install script assembles the binary into a `.app` bundle (required for native macOS notifications) and ad-hoc signs it.

### Install

```bash
cd macos
bash install.sh
```

Or just run `bash macos/install.sh notifications` from the repo root.

### Uninstall

```bash
cd macos
bash uninstall.sh
```

Or just run `bash macos/uninstall.sh notifications` from the repo root.

This removes notification hooks from `~/.claude/settings.json` and cleans up temp files.

## Configuration

Copy `config.json.example` to `config.json` and edit:

```json
{
    "title": "CC Notification",
    "terminal": "ghostty",
    "editor": "zed",
    "messages": {
        "notification": "Claude needs your input",
        "permission": "Claude needs permission",
        "elicitation": "Action required",
        "stop": "Task completed"
    },
    "icons": {
        "notification": "icons/notification.png",
        "stop": "icons/stop.png"
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
| `title` | Name shown in the .app bundle and notification attribution |
| `terminal` | Terminal to focus on click (`ghostty`, `iterm2`, `wezterm`, `terminal`) |
| `editor` | Editor to open projects in (`zed`, `code`, `cursor`) |

### Webhook

When configured, sends a JSON POST to the webhook URL if you're AFK (screen locked or idle for `idle_minutes`). The payload is defined by a JSON template file with variable substitution.

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

## Files

| File | Purpose |
|------|---------|
| `Sources/main.swift` | Swift source — all hook commands, notification handling, install/uninstall |
| `Package.swift` | Swift Package Manager build config |
| `Info.plist` | App bundle metadata (agent app, bundle ID, macOS version) |
| `config.json.example` | Example config (copy to `config.json`) |
