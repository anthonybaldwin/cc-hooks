# Linux

## Requirements

- `python3` (used by the installers to edit `settings.json`)
- A terminal that honors [OSC 11](https://invisible-island.net/xterm/ctlseqs/ctlseqs.html#h3-Operating-System-Commands) background changes (most modern emulators)
- Under **tmux**, truecolor enabled so the hex tints land faithfully:
  ```tmux
  # ~/.tmux.conf
  set -g default-terminal "tmux-256color"
  set -ag terminal-overrides ",xterm-256color:RGB"
  ```
  Over SSH this needs nothing extra — `TERM` rides the pty automatically, so as long as the server has the `tmux-256color` terminfo, color just works.

## Install

```bash
cd linux
bash install.sh                # install all hooks
bash install.sh session-color  # install a specific hook
```

## Uninstall

```bash
cd linux
bash uninstall.sh                # uninstall all hooks
bash uninstall.sh session-color  # uninstall a specific hook
```

## Hooks

| Hook | Description |
|------|-------------|
| [session-color/](session-color/) | Status-driven terminal background tint (working / needs you / done) |

> **Note:** Desktop notifications are not implemented on Linux yet. The plan is to pipe Linux (SSH/WSL) notifications through to the macOS/Windows notifier rather than reimplement them natively.
