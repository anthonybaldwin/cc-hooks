# macOS

## Requirements

- [Xcode](https://developer.apple.com/xcode/) Command Line Tools (`xcode-select --install`)
- Optional: [terminal-notifier](https://github.com/julienXX/terminal-notifier) (`brew install terminal-notifier`) — fallback if native notifications are unavailable

## Install

```bash
cd macos
bash install.sh                # install all hooks
bash install.sh notifications  # or install a specific hook
bash install.sh session-color
```

## Uninstall

```bash
bash uninstall.sh                # uninstall all hooks
bash uninstall.sh notifications  # or uninstall a specific hook
bash uninstall.sh session-color
```

## Hooks

| Hook | Description |
|------|-------------|
| [notifications/](notifications/) | Desktop notifications with elapsed time, terminal focus, and editor integration |
| [session-color/](session-color/) | Tints the terminal background by session status — working (amber), needs you (red), done/idle (blue) |
