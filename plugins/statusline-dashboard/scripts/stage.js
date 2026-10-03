#!/usr/bin/env bun
// SessionStart hook: stage the status line scripts into the plugin's persistent data directory.
//
// WHY: Claude Code's `statusLine` setting is a plain command string in ~/.claude/settings.json —
// a plugin can't set it, and `${CLAUDE_PLUGIN_ROOT}` isn't substituted there. Pointing settings at
// the plugin root directly would also break on every update: the root is a per-VERSION cache dir
// (~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/) that moves with each release.
// `${CLAUDE_PLUGIN_DATA}` (~/.claude/plugins/data/<id>/) is stable across updates, so the setup
// skill points settings at copies there, and this hook refreshes those copies at session start —
// the hook always runs from the CURRENT version's root, so the staged files track updates with a
// one-session lag at most.
//
// MUST stay silent: SessionStart stdout is added to Claude's context. Always exits 0 — a failed
// stage must never degrade the session (the previous copies keep rendering).
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const FILES = ["statusline.js", "subagent-statusline.js", "install.js"];

const root = process.env.CLAUDE_PLUGIN_ROOT;
const data = process.env.CLAUDE_PLUGIN_DATA;
if (!root || !data) process.exit(0); // not run by Claude Code as a plugin hook — nothing to do

try {
  mkdirSync(data, { recursive: true });
  for (const name of FILES) {
    const src = join(root, name);
    if (!existsSync(src)) continue;
    const want = readFileSync(src);
    const dst = join(data, name);
    // Byte-compare before writing: an identical copy is left untouched so its mtime stays put and
    // nothing watching the file (editors, the user's own tooling) sees a spurious change.
    if (existsSync(dst) && want.equals(readFileSync(dst))) continue;
    writeFileSync(dst, want);
  }
} catch {
  // swallow — see header
}
process.exit(0);
