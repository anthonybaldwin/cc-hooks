# macOS

CC hooks for macOS terminals.

## Requirements

- Xcode Command Line Tools (`xcode-select --install`)
- [terminal-notifier](https://github.com/julienXX/terminal-notifier) (`brew install terminal-notifier`) — for click actions

## Install

```bash
cd macos
bash install.sh
```

## Uninstall

```bash
bash uninstall.sh
```

## Hooks

| Hook | Description |
|------|-------------|
| [notifications/](notifications/) | Native notifications with elapsed time, terminal focus, and editor integration |
