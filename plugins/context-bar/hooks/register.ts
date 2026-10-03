// context-bar — a mod that draws the context window as a stacked bar above the prompt.
//
// One colour per category, as /context breaks the window down (system prompt, tools, memory
// files, messages, …, then the compaction buffer and free space), scaled to the band's width, with
// a legend underneath. It's live: Claude Code pushes `session.measure` after every turn and the
// mod re-reads the breakdown then — no polling, no timer. `/context-bar` toggles it, and the
// choice is remembered across sessions in $.store.
//
// WHY A MOD (and not a row in statusline-dashboard): the status line only gets the window's
// total; the per-category breakdown is a mods-API call (`$.session.usage({ breakdown })`), and
// the band is the one place a plugin can draw a multi-row, themed, live widget. The status line
// keeps the gauge; this is the detail.
import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { Segment, Snapshot } from '../types'

const snapshot = atom({ plugin: 'context-bar', key: 'snapshot' } as const, null as Snapshot | null)
const isVisible = atom({ plugin: 'context-bar', key: 'isVisible' } as const, true)

/** $.store key for the remembered visibility (one boolean; absent = shown). */
export const STORE_KEY = 'isVisible'

/** The glyph each kind of segment is drawn with — used rows solid, the buffer hatched, free space light. */
export const glyphFor = (kind: Segment['kind']): string => (kind === 'free' ? '░' : kind === 'buffer' ? '▒' : '█')

/**
 * Splits `width` cells across the segments in proportion to their tokens (largest-remainder
 * rounding, so the cells always sum to exactly `width` and no non-empty segment rounds to zero
 * while a cell can be found for it). Deferred rows are left out, as /context's grid leaves them.
 * Pure, so the test can check the arithmetic without a drawing.
 */
export function layout(categories: Segment[], width: number): Array<Segment & { cells: number }> {
  const rows = categories.filter((c) => c.kind !== 'deferred' && c.tokens > 0)
  const total = rows.reduce((n, c) => n + c.tokens, 0)
  if (width <= 0 || total <= 0 || rows.length === 0) return []
  const exact = rows.map((c) => (c.tokens / total) * width)
  const cells = exact.map((x) => Math.floor(x))
  let left = width - cells.reduce((n, c) => n + c, 0)
  // Hand the leftover cells to the largest fractional parts first.
  const order = exact.map((x, i) => [x - cells[i], i] as const).sort((a, b) => b[0] - a[0])
  for (const [, i] of order) {
    if (left <= 0) break
    cells[i] += 1
    left -= 1
  }
  // A non-empty row that still rounded to nothing borrows one cell from the widest row, so every
  // category present is at least visible.
  for (let i = 0; i < cells.length; i++) {
    if (cells[i] > 0) continue
    const widest = cells.indexOf(Math.max(...cells))
    if (cells[widest] > 1) {
      cells[widest] -= 1
      cells[i] = 1
    }
  }
  return rows.map((c, i) => ({ ...c, cells: cells[i] }))
}

/** `name NN%` legend entries, only for rows worth a label, as many as fit in `width` two columns apart. */
export function legend(categories: Segment[], maxTokens: number, width: number): Array<{ text: string; color: string }> {
  const items = categories
    .filter((c) => c.kind !== 'deferred' && c.tokens > 0)
    .map((c) => ({ text: `${c.name} ${Math.max(1, Math.round((c.tokens / Math.max(1, maxTokens)) * 100))}%`, color: c.color }))
  const out: typeof items = []
  let used = 0
  for (const it of items) {
    const need = (out.length ? 2 : 0) + it.text.length
    if (used + need > width) break
    out.push(it)
    used += need
  }
  return out
}

// Re-read the breakdown and publish it; the ui.render hook subscribes to `snapshot`, so the write
// redraws the band. 'summary' estimates locally and sends no token-count requests. (Top-level
// function declarations: the validator follows `$` only into functions declared at the top of
// the module, so helpers that take it live here, not inside `register`.)
async function measure($: EngineInterface): Promise<void> {
  try {
    const usage = await $.session.usage({ breakdown: 'summary' })
    const b = usage.context.breakdown
    if (!b) return
    const snap: Snapshot = {
      categories: b.categories.map((c) => ({ name: c.name, tokens: c.tokens, color: c.color, kind: c.kind })),
      totalTokens: b.totalTokens,
      maxTokens: b.rawMaxTokens,
      percentage: b.percentage,
      model: b.model,
      at: await $.clock.now(),
    }
    await update($, snapshot, () => snap)
  } catch {
    // No session bound yet (a `-p` run, the very first moments of a session): keep the last snapshot.
  }
}

// The remembered toggle lives in $.store (across sessions); $.state resets on /clear, so copy it
// back in on every start-like event, not just session.start.
async function loadVisible($: EngineInterface): Promise<void> {
  const saved = await $.store.get(STORE_KEY)
  if (typeof saved === 'boolean') await update($, isVisible, () => saved)
}

export const register: Register = (on) => {
  on('session.start', async ($, e, next) => {
    await $.command.register({
      name: 'context-bar',
      description: 'Show or hide the context-window bar above the prompt',
      immediate: true,
    })
    await loadVisible($)
    await measure($)
    return next(e)
  })

  // /clear, /resume, /branch and compaction reset or reshape the window: measure again, and bring
  // the saved toggle back (those three reset $.state, and session.start doesn't fire for them).
  on('classic.SessionStart', { source: ['clear', 'resume', 'fork', 'compact'] }, async ($, e, next) => {
    await loadVisible($)
    await measure($)
    return next(e)
  })

  // Pushed after each main-thread turn (and when a rate-limit window moves a point): the moment
  // the fill may have changed.
  on('session.measure', async ($, e, next) => {
    if (e.changed.includes('context')) await measure($)
    return next(e)
  })

  on('command.run', { command: 'context-bar' }, async ($) => {
    const show = !(await read($, isVisible))
    await update($, isVisible, () => show)
    await $.store.set(STORE_KEY, show)
    if (show) await measure($)
    return { text: show ? 'Context bar shown.' : 'Context bar hidden — /context-bar shows it again.' }
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const snap = await read($, snapshot)
    const shown = await read($, isVisible)
    if (e.props.hasSurvey || !shown || !snap) return next(e)

    const { Box, Text } = $.ui.resolve(e)
    const width = Math.max(10, e.props.bodyColumns)
    const bar = layout(snap.categories, width)
    if (bar.length === 0) return next(e)

    const head = `${snap.percentage}%`
    const items = legend(snap.categories, snap.maxTokens, width - head.length - 2)

    return Box({
      flexDirection: 'column',
      children: [
        Box({
          flexDirection: 'row',
          children: bar.map((seg) => Text({ color: seg.color, children: [glyphFor(seg.kind).repeat(seg.cells)] })),
        }),
        Box({
          flexDirection: 'row',
          columnGap: 2,
          children: [
            Text({ bold: true, children: [head] }),
            ...items.map((it) => Text({ color: it.color, children: [it.text] })),
          ],
        }),
      ],
    })
  })
}
