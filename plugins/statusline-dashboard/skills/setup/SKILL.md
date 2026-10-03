---
name: setup
description: Configure (or remove) the statusline-dashboard status line in ~/.claude/settings.json. Use when the user runs /statusline-dashboard:setup, asks to install, enable, set up, turn on, remove, or uninstall this status line, or asks why the dashboard isn't showing after installing the plugin.
argument-hint: "[--print | --uninstall]"
allowed-tools: Bash(bun *)
---

# Set up the statusline-dashboard status line

Claude Code's `statusLine` setting is a command string in the user's `~/.claude/settings.json`. A
plugin can't set it on its own, so this skill runs the plugin's installer, which writes it.

The installer points `statusLine` and `subagentStatusLine` at copies of the scripts in the
plugin's **persistent data directory**, not at the plugin root. The plugin root is a per-version
cache directory that moves with every update; the data directory is stable, and a SessionStart
hook in this plugin refreshes the copies there each session.

## Steps

1. Stage the scripts into the data directory (idempotent; needed when the plugin was installed
   during this session, before the SessionStart hook has had a chance to run):

   ```bash
   bun "${CLAUDE_PLUGIN_ROOT}/scripts/stage.js"
   ```

2. Run the installer from the data directory. Pass through any arguments the user gave
   (`$ARGUMENTS`): `--print` previews the settings.json that would be written without writing it;
   `--uninstall` removes only the `statusLine` / `subagentStatusLine` blocks that point at this
   plugin's data directory, leaving any other status line alone.

   ```bash
   bun "${CLAUDE_PLUGIN_DATA}/install.js" $ARGUMENTS
   ```

   The installer merges into the existing `settings.json` (a `settings.json.bak` copy is made
   first) and preserves unrelated keys, including any `statusLine.padding` / `refreshInterval`
   the user already set.

3. Show the installer's output to the user verbatim. On a successful install, tell them to restart
   Claude Code (or start a new interaction) to see the dashboard, and that a Nerd Font is needed
   for the glyphs. If `bun` isn't found, tell them Bun is required (https://bun.sh) and stop.

Don't edit `settings.json` by hand — the installer is the only writer, so `--uninstall` can later
recognize what it wrote.
