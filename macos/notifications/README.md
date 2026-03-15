# Notifications

Native macOS notifications for Claude Code via [terminal-notifier](https://github.com/julienXX/terminal-notifier).

## What it does

When Claude finishes or needs input, you get a notification showing:
- **Project directory** and **elapsed time** (e.g., "Task completed (12s)")
- Clicking the notification body focuses the correct terminal **window/tab/pane**
  - [Ghostty](https://ghostty.org/docs/features/applescript): matched by working directory
  - [iTerm2](https://iterm2.com/documentation-scripting.html): matched by tty device
  - Terminal.app: matched by tty device
- **Open in Editor** button — opens the project in your configured editor
- Notifications replace by session (no stacking)
- Falls back to `osascript` (no click actions) if terminal-notifier is not installed

## Configuration

Copy `config.json.example` to `config.json` and edit:

```json
{
    "terminal": "ghostty",
    "editor": "zed",
    "messages": {
        "notification": "Claude needs your input",
        "stop": "Task completed"
    },
    "icons": {
        "notification": "icons/notification.png",
        "stop": "icons/stop.png"
    }
}
```

| Field | Description |
|-------|-------------|
| `terminal` | Terminal to focus on click (`ghostty`, `iterm2`, `terminal`) |
| `editor` | Editor to open projects in (`zed`, `code`, `cursor`) |

### Icons

Place in `icons/` (gitignored):
- `notification.png` — shown when Claude needs input
- `stop.png` — shown when Claude finishes

## Files

| File | Purpose |
|------|---------|
| `Sources/main.swift` | Swift source — all hook commands, notification handling, install/uninstall |
| `Package.swift` | Swift Package Manager build config |
| `config.json.example` | Example config (copy to `config.json`) |
