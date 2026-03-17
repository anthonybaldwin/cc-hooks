# macOS

## Requirements

- [Xcode](https://developer.apple.com/xcode/) Command Line Tools (`xcode-select --install`)
- Optional: [terminal-notifier](https://github.com/julienXX/terminal-notifier) (`brew install terminal-notifier`) — fallback if native notifications are unavailable

## Install

```bash
cd macos
bash install.sh                # install all hooks
bash install.sh notifications  # install a specific hook
```

## Uninstall

```bash
bash uninstall.sh                # uninstall all hooks
bash uninstall.sh notifications  # uninstall a specific hook
```

## Hooks

| Hook | Description |
|------|-------------|
| [notifications/](notifications/) | Desktop notifications with elapsed time, terminal focus, and editor integration |
