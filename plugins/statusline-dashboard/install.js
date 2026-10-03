#!/usr/bin/env bun
// Cross-platform installer for statusline-dashboard (Windows / macOS / Linux). Bun is already required
// to run the status line, so the installer is itself a Bun script — no shell/PowerShell needed.
//
//   bun install.js              configure ~/.claude/settings.json to use these scripts
//   bun install.js --print      show what it WOULD write, without changing anything
//   bun install.js --uninstall  remove the statusLine/subagentStatusLine blocks that point HERE
//                               (--print works with it too)
//
// It points Claude Code's `statusLine` and `subagentStatusLine` at the scripts in THIS directory,
// merging into any existing settings.json (a .bak copy is made first) and preserving unrelated keys.
// Uninstall is symmetric and cautious: a block whose command points at some OTHER status line is
// left alone (and reported), so running it in the wrong checkout can't strip someone else's setup.
//
// "THIS directory" is deliberate: run from a git checkout it wires the checkout (edits go live on
// the next render); run from the plugin's data dir — where the SessionStart hook (scripts/stage.js)
// stages a copy of these files and the `setup` skill invokes it — it wires that stable copy. The
// plugin root itself is never a valid target: it's a per-version cache path that moves on update.
import { existsSync, mkdirSync, readFileSync, writeFileSync, copyFileSync } from "node:fs";
import { homedir } from "node:os";
import { join, dirname } from "node:path";

const dryRun = process.argv.includes("--print") || process.argv.includes("--dry-run");
const uninstall = process.argv.includes("--uninstall");

// Where these scripts live (absolute, forward slashes — Git Bash on Windows mangles backslashes in
// the command string, and forward slashes work for Bun on every platform).
const repoDir = (import.meta.dir || dirname(Bun.main)).replace(/\\/g, "/");
const statusline = `${repoDir}/statusline.js`;
const subagent = `${repoDir}/subagent-statusline.js`;

if (!existsSync(statusline)) {
  console.error(`✗ statusline.js not found next to the installer (looked in ${repoDir}).`);
  process.exit(1);
}

const claudeDir = join(homedir(), ".claude");
const settingsPath = join(claudeDir, "settings.json");

let settings = {};
let hadExisting = false;
if (existsSync(settingsPath)) {
  hadExisting = true;
  try {
    settings = JSON.parse(readFileSync(settingsPath, "utf8")) || {};
  } catch (e) {
    console.error(`✗ ${settingsPath} is not valid JSON (${e.message}). Fix or remove it, then re-run.`);
    process.exit(1);
  }
}

const removed = []; // --uninstall: blocks we cleared
const foreign = []; // --uninstall: blocks that point elsewhere (left untouched)
if (uninstall) {
  // Only clear a block whose command names THIS checkout's script (path compared with forward
  // slashes — the installer writes them that way, but a hand-edited Windows path may not be).
  const pointsHere = (block, script) =>
    block && typeof block === "object" && typeof block.command === "string" && block.command.replace(/\\/g, "/").includes(script);
  for (const [key, script] of [["statusLine", statusline], ["subagentStatusLine", subagent]]) {
    if (pointsHere(settings[key], script)) {
      delete settings[key];
      removed.push(key);
    } else if (settings[key] !== undefined) foreign.push(key);
  }
  if (!removed.length) {
    console.log(`Nothing to remove — ${settingsPath} has no statusLine/subagentStatusLine pointing at ${repoDir}.`);
    for (const key of foreign) console.log(`  (${key} is set, but points elsewhere — left as-is)`);
    process.exit(0);
  }
} else {
  // Merge over any existing blocks so unrelated keys (and the user's padding/refreshInterval/etc.) survive.
  const prevSL = settings.statusLine && typeof settings.statusLine === "object" ? settings.statusLine : {};
  settings.statusLine = {
    ...prevSL,
    type: "command",
    command: `bun "${statusline}"`,
    hideVimModeIndicator: prevSL.hideVimModeIndicator ?? true, // the status line renders vim mode itself
    padding: prevSL.padding ?? 0,
    refreshInterval: prevSL.refreshInterval ?? 60, // keep the clock current while idle
  };

  const prevSA = settings.subagentStatusLine && typeof settings.subagentStatusLine === "object" ? settings.subagentStatusLine : {};
  settings.subagentStatusLine = {
    ...prevSA,
    type: "command",
    command: `bun "${subagent}"`,
  };
}

const json = JSON.stringify(settings, null, 2) + "\n";

if (dryRun) {
  console.log(`# would write ${settingsPath}:\n`);
  console.log(json);
  process.exit(0);
}

mkdirSync(claudeDir, { recursive: true });
if (hadExisting) copyFileSync(settingsPath, settingsPath + ".bak");
writeFileSync(settingsPath, json);

if (uninstall) {
  console.log("✓ statusline-dashboard removed from settings");
  console.log(`  settings:  ${settingsPath}  (backup: settings.json.bak)`);
  console.log(`  cleared:   ${removed.join(", ")}`);
  for (const key of foreign) console.log(`  kept:      ${key} (points elsewhere)`);
  console.log("\nRestart Claude Code to return to its built-in footer.");
} else {
  console.log("✓ statusline-dashboard configured");
  console.log(`  settings:           ${settingsPath}${hadExisting ? "  (backup: settings.json.bak)" : "  (created)"}`);
  console.log(`  statusLine:         bun "${statusline}"`);
  console.log(`  subagentStatusLine: bun "${subagent}"`);
  console.log("\nRestart Claude Code (or start a new interaction) to see it.");
}
