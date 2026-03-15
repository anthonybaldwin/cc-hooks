# Notifications

Native macOS notifications for Claude Code via UserNotifications framework.

## What it does

When Claude finishes or needs input, you get a notification showing:
- **Project directory** and **elapsed time** (e.g., "Task completed (12s)")
- Clicking the notification body focuses your terminal (Ghostty, iTerm2, Terminal)
- **Open in Editor** button — opens the project in your configured editor
- Notifications replace by session (no stacking)

## Configuration

Copy `config.json.example` to `config.json` and edit:

```json
{
    "terminal": "ghostty",
    "editor": "zed",
    "messages": {
        "notification": "Claude needs your input",
        "stop": "Task completed"
    }
}
```

| Field | Description |
|-------|-------------|
| `terminal` | Terminal to focus on click (`ghostty`, `iterm2`, `terminal`) |
| `editor` | Editor to open projects in (`zed`, `code`, `cursor`) |

## Files

| File | Purpose |
|------|---------|
| `Sources/main.swift` | Swift source — all hook commands + notification handling |
| `Package.swift` | Swift Package Manager build config |
| `config.json.example` | Example config (copy to `config.json`) |
