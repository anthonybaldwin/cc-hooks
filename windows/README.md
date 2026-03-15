# Windows

Toast notifications for Claude Code on Windows. Shows elapsed time, focuses the correct terminal tab, and opens your editor.

## Requirements

- Windows 10/11
- [PowerShell 7+](https://github.com/PowerShell/PowerShell)
- [BurntToast](https://github.com/Windos/BurntToast) — `Install-Module BurntToast`
- [Windows Terminal](https://github.com/microsoft/terminal)

## Install

```powershell
cd windows
pwsh -File install.ps1
```

This registers protocol handlers and adds hooks to `~/.claude/settings.json` (merges with existing settings).

### Notification Icon

Place a PNG at `hooks/icon.png` for the notification icon. Not included — add your own. Notifications work fine without one.

## Configuration

Edit `config.json`:

```json
{
    "editor": "zed",
    "messages": {
        "notification": "Claude needs your input",
        "stop": "Task completed"
    },
    "icons": {
        "notification": "icon.png",
        "stop": "icon.png"
    }
}
```

- `editor` — command on your PATH (`zed`, `code`, `cursor`, etc.). Button label updates automatically.
- `messages` — notification text per hook event.
- `icons` — PNG filename per hook event (relative to `hooks/`). Use different icons for different events.

## What it does

When Claude finishes or needs input, you get a toast notification showing:
- **Project name** and **elapsed time** (e.g., "Task completed (12s)")
- **Focus Terminal** button — brings Windows Terminal to front and switches to the correct tab
- **Open in Editor** button — opens the project directory in your configured editor
- Clicking the notification body also focuses the terminal

Temp files and background processes are cleaned up when the session ends.

## Files

| File | Purpose |
|------|---------|
| `config.json` | Editor configuration |
| `install.ps1` | One-time setup: protocols + settings.json |
| `hooks/on-submit.ps1` | Timer + tab identification + watcher spawn |
| `hooks/notify.ps1` | Toast notification with elapsed time + buttons |
| `hooks/on-end.ps1` | Cleanup temp files and watcher on session end |
| `hooks/focus-terminal.ps1` | Focuses WT window + selects tab by RuntimeId |
| `hooks/protocol-handler.ps1` | Creates trigger file for focus watcher |
| `hooks/editor-handler.ps1` | Opens project in configured editor |
| `hooks/launch-hidden.vbs` | Hidden process launcher |
| `hooks/register-protocol.ps1` | Registers protocol handlers |
