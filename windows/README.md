# Windows

## Requirements

- [Rust](https://rustup.rs/) (to build)
- [PowerShell 7+](https://github.com/PowerShell/PowerShell) (`pwsh`)

## Install

```powershell
cd windows
pwsh -NoProfile -File install.ps1                # install all hooks
pwsh -NoProfile -File install.ps1 notifications  # install a specific hook
```

A UAC prompt will appear for the notification icon/title registry entry. Declining still works — just no icon on toasts.

## Uninstall

```powershell
pwsh -NoProfile -File uninstall.ps1                # uninstall all hooks
pwsh -NoProfile -File uninstall.ps1 notifications  # uninstall a specific hook
```

## Hooks

| Hook | Description |
|------|-------------|
| [notifications/](notifications/) | Desktop notifications with elapsed time, terminal focus, and editor integration |
