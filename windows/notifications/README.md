# Notifications

Toast notifications for Claude Code via Windows' WinRT API.

## What it does

When Claude finishes or needs input, you get a toast notification showing:
- **Project directory** and **elapsed time** (e.g., "Task completed (12s)")
- **Focus Terminal** button — brings Windows Terminal to front and switches to the correct tab
- **Open in Editor** button — opens the project directory in your configured editor
- Clicking the notification body also focuses the terminal
- Notifications replace by session (no stacking)

Skips notifications when running inside an IDE (Zed, VS Code, etc.).

## Configuration

Copy `config.json.example` to `config.json` and edit:

```json
{
    "title": "CC Notification",
    "editor": "zed",
    "messages": {
        "notification": "Claude needs your input",
        "stop": "Task completed"
    },
    "icons": {
        "notification": "icons/notification.png",
        "stop": "icons/stop.png",
        "title": "icons/title.ico"
    }
}
```

| Field | Description |
|-------|-------------|
| `title` | Name shown in toast attribution bar (registered in HKLM during install) |
| `editor` | Editor to open projects in (`zed`, `code`, `cursor`) |

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
