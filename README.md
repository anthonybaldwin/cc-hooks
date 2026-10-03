# cc-plugins

[Claude Code](https://claude.com/claude-code) plugins, served from this repo as a
[plugin marketplace](https://code.claude.com/docs/en/plugins/marketplace-reference):

```
/plugin marketplace add anthonybaldwin/cc-plugins
```

| Plugin | What it does | Install |
| --- | --- | --- |
| [**statusline-dashboard**](plugins/statusline-dashboard/) | Opinionated multi-row status line: context, cost, rate-limit windows with pace balance, git/PR, sub-agents, and config-scope breakdowns. Zero-dependency Bun scripts with Nerd Font glyphs. | `/plugin install statusline-dashboard@cc-plugins` then `/statusline-dashboard:setup` |
| [**context-bar**](plugins/context-bar/) | A mod: your context window as a stacked bar above the prompt, one color per category as `/context` breaks it down, live after every turn. `/context-bar` toggles it. Claude Code 2.1.287+. | `/plugin install context-bar@cc-plugins` |
| [**session-color**](plugins/session-color/) | Tints the terminal background by session status — amber while Claude works, red when it needs you, green when done — per pane via OSC 11 (tmux-native on Linux, ConPTY on Windows). | `/plugin install session-color@cc-plugins` (+ `/session-color:setup` on Windows) |
| [**notifications**](plugins/notifications/) | Native desktop notifications when Claude finishes or needs input: elapsed time, focus-the-originating-pane, open-in-editor, AFK webhook. Windows (WinRT) and macOS (UserNotifications). | `/plugin install notifications@cc-plugins` then `/notifications:setup` |

Each plugin's README covers requirements, configuration and how it works. A few things are the
same for all of them:

- **`setup` skills exist because plugins can't do everything.** A plugin can register hooks,
  skills and MCP servers, but it can't set `statusLine` in your settings, and it can't run a
  build. Where one of those is needed, the plugin ships a `/<plugin>:setup` skill that does it,
  and stages whatever it produces in the plugin's **persistent data directory**
  (`~/.claude/plugins/data/…`) rather than the plugin's install path — the install path is a
  per-version cache directory that moves on every update, the data directory is stable.
- **Updates**: `/plugin update <name>@cc-plugins` (or enable auto-update for the marketplace in
  `/plugin` → Marketplaces). Plugins are versioned by their manifest; a push without a version
  bump isn't an update.
- **Uninstall**: `/plugin uninstall <name>@cc-plugins`. It removes the plugin's hooks and its data
  directory. Where a plugin wrote outside those (the statusline's `statusLine` setting, the
  Windows notification registry entries), run `/<plugin>:setup --uninstall` first.

## Layout

```
cc-plugins/
├─ .claude-plugin/marketplace.json   # the marketplace: one entry per plugin below
├─ plugins/
│  ├─ statusline-dashboard/          # statusline.js, subagent-statusline.js, install.js,
│  │                                 #   SessionStart staging hook, setup skill
│  ├─ context-bar/                   # a mod: hooks/register.ts, types/, tests/
│  ├─ session-color/                 # hooks.json + sh dispatcher; macos/ linux/ (shell), windows/ (Rust)
│  └─ notifications/                 # hooks.json + sh dispatcher; windows/ (Rust), macos/ (Swift)
├─ check.js                          # statusline invariant checker (see its README → Development)
└─ .github/workflows/check.yml       # check.js on 3 OSes, `claude plugin validate` + `test`, cargo + swift builds
```

To work on a plugin from a checkout, add the checkout as a local marketplace — it then loads in
place, and edits apply on the next session or `/reload-plugins`:

```
/plugin marketplace add /path/to/cc-plugins
/plugin install session-color@cc-plugins
```

## License

[MIT](LICENSE) © Anthony Baldwin.
