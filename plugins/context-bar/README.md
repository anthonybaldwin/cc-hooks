# Context Bar

A [mod](https://code.claude.com/docs/en/plugins/mods/overview) that draws your context window as a stacked bar in the band above the prompt — one color per category, as `/context` breaks it down — with a legend underneath:

```
████████▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▒▒▒▒▒▒░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
40%  System prompt 3%  System tools 7%  Messages 30%  Autocompact buffer 10%  Free space 50%
```

(Each run is drawn in its category's theme color — the same colors `/context` uses — solid `█` for what's in use, `▒` for the compaction buffer, `░` for free space.)

It's live: Claude Code pushes a measurement after every turn, and the bar redraws from it. No polling, no timer, no token-count requests (the breakdown is the local `summary` estimate, the one `/context` starts from).

## Install

```
/plugin marketplace add anthonybaldwin/cc-plugins
/plugin install context-bar@cc-plugins
```

Requires Claude Code **v2.1.287+** (mods). It draws in the terminal and in the Desktop app's Code tab; in the VS Code chat panel and `claude -p` the hooks run but nothing is drawn.

## Use

| | |
|---|---|
| `/context-bar` | Toggle the bar. The choice is remembered across sessions. Works mid-turn. |
| `ctrl+x ctrl+a` | Claude Code's own collapse for the band above the prompt. |

The band is shared with other mods and with Claude Code's surveys; a survey takes precedence while it's up.

## Why a mod, and why not a row in statusline-dashboard

The status line receives only the window's total. The per-category breakdown is a mods-API call (`$.session.usage({ breakdown })`), and the band above the prompt is the one place a plugin can draw a multi-row, theme-colored widget that updates on push. So the status line keeps its context gauge, and this is the detail view beside it. The two are independent — install either or both.

## How it works

`hooks/register.ts`:

- `session.start` registers `/context-bar`, restores the saved toggle from `$.store`, and takes a first measurement.
- `session.measure` (fired after each main-thread turn) re-reads `$.session.usage({ breakdown: 'summary' })` whenever the context unit moved, and writes the snapshot into `$.state`. Writing the state redraws the band — the render hook subscribes to it.
- `classic.SessionStart` for `clear` / `resume` / `fork` / `compact` measures again and restores the toggle (those reset `$.state`).
- `ui.render` on `AbovePrompt` lays the categories out across `bodyColumns` cells with largest-remainder rounding (so the bar is always exactly the band's width and every non-empty category stays visible), skips deferred tool rows like `/context`'s grid does, and fits as many legend entries as the width allows.

Tests (`claude plugin test plugins/context-bar`) cover the layout arithmetic, drawing on both surfaces, the toggle round-trip through `$.store`, the `/clear` path, and the survey precedence.
