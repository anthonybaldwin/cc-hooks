# Windows

CC hooks for Windows Terminal.

## Requirements

- [Rust](https://rustup.rs/) (to build)
- [PowerShell 7+](https://github.com/PowerShell/PowerShell) (`pwsh`)

## Install

```powershell
cd windows
pwsh -NoProfile -File install.ps1
```

A UAC prompt will appear for the notification icon/title registry entry. Declining still works — just no icon on toasts.

## Uninstall

```powershell
pwsh -NoProfile -File uninstall.ps1
```

## Hooks

| Hook | Description |
|------|-------------|
| [notifications/](notifications/) | Toast notifications with elapsed time, terminal focus, and editor integration |
