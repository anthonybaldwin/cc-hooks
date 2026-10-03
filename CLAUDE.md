# claude-statusline

An opinionated multi-row statusline dashboard for Claude Code. Single-file Bun scripts, no
dependencies, no build step.

## Files

The repo root is a one-plugin **marketplace** (`.claude-plugin/marketplace.json`, name
`anthonybaldwin`); the plugin itself is `plugins/statusline-dashboard/` (name
`statusline-dashboard` — plugin names can't start with `claude-`, that prefix is reserved).
Everything a user installs lives under the plugin dir; tooling and docs stay at the root.

- `plugins/statusline-dashboard/statusline.js` — the main dashboard. Reads Claude Code's
  statusline JSON from stdin, writes ANSI-styled rows to stdout. Everything lives in this one
  file, ordered roughly: ANSI/color constants → glyphs → formatting helpers → config-counting
  subsystem (scopes, plugins, MCP) → stdin parse → per-row segment building → `packSection`
  layout → output.
- `plugins/statusline-dashboard/subagent-statusline.js` — the per-subagent row for Claude Code's
  agent panel (`subagentStatusLine` in settings). Same conventions, much smaller.
- `plugins/statusline-dashboard/install.js` — points `~/.claude/settings.json` at the scripts in
  ITS OWN directory (merges, backs up first). Run from the checkout it wires the checkout; run
  from the plugin data dir (via the `setup` skill) it wires the staged copies. `--print` for a dry
  run; `--uninstall` clears only blocks that point at that directory.
- `plugins/statusline-dashboard/hooks/hooks.json` + `scripts/stage.js` — `SessionStart` hook
  that copies the three scripts into `${CLAUDE_PLUGIN_DATA}`. **Why:** a plugin can't set
  `statusLine`, and `${CLAUDE_PLUGIN_ROOT}` is a per-version cache path that moves on every
  update — so settings point at the stable data dir and the hook keeps it current. Must stay
  silent (SessionStart stdout is injected into Claude's context) and always exit 0.
- `plugins/statusline-dashboard/skills/setup/SKILL.md` — `/statusline-dashboard:setup`: stages,
  then runs `install.js` from the data dir (`--print` / `--uninstall` pass through).
- `plugins/statusline-dashboard/.claude-plugin/plugin.json` — manifest. **Bump `version` to ship
  to plugin users**: the manifest version IS the plugin version, so a push without a bump never
  reaches installed copies.
- `check.js` — the invariant checker (see below). `.github/workflows/check.yml` runs it on
  Linux/macOS/Windows and runs `claude plugin validate --strict` on the marketplace + plugin.

## Running / verifying changes

Requires **Bun** (`Bun.stdin` / `Bun.main`). Run `bun check.js` after any change to the packer,
height budget, or output shape: it renders fixture payloads for both scripts across a grid of
`COLUMNS`×`LINES` inside a sandboxed `HOME`/`TEMP` (no real config, no live caches, no network)
and asserts the invariants below plus a "no data-less rows" rule. `--show 60x24` prints one
stripped render. For a specific payload, pipe it in by hand:

```sh
echo '{"session_id":"x","model":{"display_name":"Opus"},"cwd":"C:/some/repo","cost":{},
  "context_window":{"context_window_size":200000,"current_usage":{"input_tokens":50000}},
  "rate_limits":{"five_hour":{"used_percentage":42,"resets_at":"2026-06-12T20:00:00Z"}}}' \
  | COLUMNS=140 bun statusline.js
```

The user's live statusline runs `statusline.js` **directly from this working tree** (settings
point at the repo file, not a copy) — edits take effect on the next render, including broken
ones. Don't leave the file in a non-running state between edits. (Plugin installs run the staged
copy in `~/.claude/plugins/data/` instead and only pick up a `version` bump.)

## Critical invariants

These exist to dodge real Claude Code rendering bugs; violating them corrupts the user's
terminal, not just the aesthetics.

1. **Height never shrinks between renders, and never exceeds what the terminal can spare.**
   Shrink: CC reserves vertical space from the previous render's line count; if the count drops,
   stale rows stack (under-clear, fixed upstream in CC v2.1.170 but kept defensive). Guarded by
   the slot floor (empty sections backfill blank) AND a per-session high-water mark
   (`sl-hwm-*.json`, keyed to `COLUMNS×LINES`) that pads later renders up to the tallest height
   already shown; the mark resets on resize (which forces a full CC repaint anyway). Short
   terminal: CC gives the statusline what remains after the turn's transcript tail + prompt +
   its own footer, and hard-trims our tail AND the footer when we exceed it (observed
   v2.1.223) — the transcript share is unknowable, so content clamps to a THIRD of `LINES`
   (CC's exported height belief); over budget, the squeeze loop re-packs the tallest section
   (ties by `SQUEEZE_ORDER`) one row shorter via `packSection`'s `maxRows` (cut with a trailing
   `…`), then whole sections vanish in `DROP_ORDER`. Tall terminal: wraps beyond the section
   count are allowed (no `…` data loss) up to `WRAP_HEADROOM` extra rows. **Adding a row =
   adding one entry to `sectionSpecs`** (and to `SQUEEZE_ORDER` + `DROP_ORDER`); never
   conditionally omit a slot.
2. **Lines must never exceed the terminal width.** CC counts logical lines; a terminal
   hard-wrap desyncs its repaint. `packSection` measures with `vlen` (visible width, ANSI- and
   wide-glyph-aware) and degrades per item: widest alt → narrowest alt → wrap to a fresh row →
   truncate the narrow alt with `…` when even that overflows a row on its own (any alt count —
   an unclipped over-wide item is exactly the hard-wrap this guards against). Width comes from
   `COLUMNS || stdout.columns || 80` — never a huge fallback (a `1e9` fallback once corrupted
   the terminal).
3. **U+2800 (Braille blank), not spaces, for indentation and blank rows.** CC strips leading
   whitespace and trailing blank rows; U+2800 renders blank but isn't whitespace.
4. **Never block the render on the network.** Slow data (OAuth usage API) is served from a
   TTL'd temp-file cache; a stale cache triggers a detached self-respawn
   (`CLAUDE_STATUSLINE_USAGE_REFRESH=1`) that refreshes out-of-band and exits before the stdin
   read. Cross-render state lives in `$TEMP/sl-*.json` files (usage cache,
   per-session accumulators).

## Layout conventions

- A row's content is a list of **segments**: plain strings, or `{ alts: [wide, narrow] }` where
  the packer uses `alts[0]` when the row fits and `alts[alts.length - 1]` when space is tight
  (bars and parenthesized detail go in the wide form only).
- `packSection(label, segments, lead, leadWidth, preferDetail, maxRows)` does the layout:
  all-widest on one line → all-narrowest on one line (skipped when `preferDetail`) → greedy
  per-item wrap, cut with `…` when `maxRows` is hit (only the height-cap squeeze loop passes
  `maxRows`). A finite `maxRows` flips the section into **squeeze mode**: items go narrow-first
  and the all-narrow probe runs even for `preferDetail` sections, because under a row budget a
  cut item is lost outright while a dropped bar or scope paren is only detail. The first item on
  an empty row always tries its narrow form, then truncates in place, before any wrap/cut — a
  row must never emit just its label and `…`. An empty segment list emits nothing (the slot
  backfills blank — rows like Turn/Activity disappear after `/clear`).
- Row **lead** glyphs render once before the first segment; pass the lead's true cell width —
  `vlen` guesses wrong for some glyphs in the user's terminal font.
- Section labels pad to `SECTION_WIDTH` (8) and render bold-italic-SOFT.

## Style conventions

- Colors are 256-color ANSI constants at the top of the file. `SOFT` (245) for labels/punctuation,
  `DIM` (244) for annotations and predictions, `VAL`/`WHITE` (97) for primary values; semantic
  colors (GREEN/YELLOW/RED, usageColor, contextColor) carry meaning — don't reuse them
  decoratively. Each row lead has its own hue; before introducing a color, grep `c256(` to
  confirm it's unused.
- Glyphs are Nerd Font codepoints declared as `g*` constants with the NF name in a comment.
  On the user's Windows font some Font Awesome glyphs render as tofu — Material Design (`nf-md-*`,
  `0xf0xxx`) codepoints are the safer choice; comments by existing glyphs note known exceptions.
- Comments throughout the file explain *why* (CC bugs, font quirks, API gotchas), and several
  encode hard-won diagnoses (e.g. the API-duration laptop-sleep artifact). Preserve and imitate
  that register; don't strip them when refactoring.

## Pace balance

Each Limits gauge appends a signed pace balance vs the even-consumption budget line
(`(elapsed/window)·100`, window start = `resets_at` − window length): `+N%` = quota in hand
(green), `-N%` = burning ahead (yellow), SOFT within ±2%, shown as soon as any time has elapsed
in the window (suppressed only for a degenerate just-reset window — matches usage-buttons'
PaceMetric). Kept to a few chars on purpose — the user wants it terse; don't expand it into words
("reserve"/"over pace") or give it a dedicated row.

## Workflow notes

- Update the README row list when rows change — it enumerates every row in render order.
- Run `bun check.js` before committing; a new row also means bumping `SECTIONS` in `check.js`.
  After touching anything under `plugins/` or `.claude-plugin/`, also run
  `claude plugin validate --strict .` and `claude plugin validate --strict plugins/statusline-dashboard`.
- Adding a file the status line needs at runtime = adding it to `FILES` in `scripts/stage.js`
  (and the `staged` list in `check.js`) — otherwise plugin installs won't have it.
- Commit when a change is done and verified; **do not push without being asked.**
- Test renders share the real `$TEMP/sl-*.json` caches — clean up anything you seed with fake
  data.
- **Subprocess hygiene:** pass secrets (the OAuth token) to `curl` via its stdin config
  (`-K -`), never a `-H`/CLI arg — args are visible in process listings. Add `windowsHide: true`
  to every `spawn`/`spawnSync` so console/detached children don't flash a terminal on Windows.
