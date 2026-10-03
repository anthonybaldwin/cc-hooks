import { expect, mock, test } from 'claude-code/testing'

import { layout, legend } from '../hooks/register'

// What Claude Code passes to a ui.render hook for the band, apart from the app.
const BAND = {
  plugin: 'context-bar',
  component: 'AbovePrompt',
  viewport: { columns: 100, rows: 30 },
  props: {
    hasSurvey: false,
    isWorking: false,
    maxRows: 12,
    bodyColumns: 60,
    scroll: { offset: 0, bodyRows: 11 },
    view: {},
  },
} as const

// A breakdown in the shape $.session.usage({ breakdown }) resolves to (the fields the mod reads).
const categories = [
  { name: 'System prompt', tokens: 6000, color: 'promptBorder', isDeferred: false, kind: 'used' },
  { name: 'System tools', tokens: 14000, color: 'permission', isDeferred: false, kind: 'used' },
  { name: 'Messages', tokens: 60000, color: 'success', isDeferred: false, kind: 'used' },
  { name: 'Deferred tools', tokens: 9000, color: 'inactive', isDeferred: true, kind: 'deferred' },
  { name: 'Autocompact buffer', tokens: 20000, color: 'warning', isDeferred: false, kind: 'buffer' },
  { name: 'Free space', tokens: 100000, color: 'inactive', isDeferred: false, kind: 'free' },
]
const usage = {
  startedAt: 0,
  context: {
    tokens: 80000,
    window: 200000,
    percent: 40,
    breakdown: {
      categories,
      totalTokens: 80000,
      maxTokens: 200000,
      rawMaxTokens: 200000,
      autocompactSource: 'model-default',
      percentage: 40,
      gridRows: [],
      model: 'Opus',
      memoryFiles: [],
      mcpTools: [],
      agents: [],
      isAutoCompactEnabled: true,
      apiUsage: null,
    },
  },
  rateLimits: [],
  cost: { usd: 0.5 },
}

const segs = categories.map(({ name, tokens, color, kind }) => ({ name, tokens, color, kind }))

test('layout fills the width exactly, skips deferred rows, and keeps every row visible', () => {
  for (const width of [10, 37, 60, 200]) {
    const bar = layout(segs, width)
    expect(bar.reduce((n, s) => n + s.cells, 0)).toBe(width)
    expect(bar.some((s) => s.name === 'Deferred tools')).toBe(false)
    expect(bar.every((s) => s.cells >= 1)).toBe(true)
  }
  // The biggest row gets the most cells; free space is drawn last.
  const bar = layout(segs, 60)
  expect(bar[bar.length - 1].kind).toBe('free')
  expect(Math.max(...bar.map((s) => s.cells))).toBe(bar.find((s) => s.name === 'Free space')!.cells)
  expect(layout(segs, 0)).toEqual([])
  expect(layout([], 40)).toEqual([])
})

test('legend labels rows by percent of the window and stops at the width', () => {
  const all = legend(segs, 200000, 500)
  expect(all.map((l) => l.text)).toEqual([
    'System prompt 3%',
    'System tools 7%',
    'Messages 30%',
    'Autocompact buffer 10%',
    'Free space 50%',
  ])
  const few = legend(segs, 200000, 36) // "System prompt 3%" + 2 + "System tools 7%" = 33; Messages would need 45
  expect(few.map((l) => l.text)).toEqual(['System prompt 3%', 'System tools 7%'])
})

test('after session.start the band draws the bar and a legend, on both surfaces', async ($, on) => {
  mock.clock(on)
  on('session.start', () => ({ cwd: '/work' }))
  on('command.register', () => ({ value: undefined }))
  on('store.get', () => ({ value: undefined }))
  on('session.usage', () => ({ value: usage }))
  await $.session.start({ surface: 'terminal', isInteractive: true, cwd: '/work' })

  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ ...BAND, surface })
    expect(await ui.find({ type: 'Text', text: '40%' })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: 'Messages 30%' })).toBeDefined()
    // 60 cells of bar across the segments: the Messages run is the widest used segment.
    const messages = await ui.find({ type: 'Text', text: /^█+$/ })
    expect(messages).toBeDefined()
    await ui.unmount()
  }
})

test('/context-bar hides the band, remembers it, and shows it again', async ($, on) => {
  mock.clock(on)
  const saved = new Map<string, unknown>()
  on('session.start', () => ({ cwd: '/work' }))
  on('command.register', () => ({ value: undefined }))
  on('store.get', ($, e) => ({ value: saved.get(e.key) }))
  on('store.set', ($, e) => {
    saved.set(e.key, e.value)
    return { value: undefined }
  })
  on('session.usage', () => ({ value: usage }))
  // What Claude Code draws in the band when the mod passes (nothing of its own, but the kit needs an answer).
  on('ui.render', () => ({ type: 'Text', props: {}, children: ['drawn by Claude Code'] }))
  await $.session.start({ surface: 'terminal', isInteractive: true, cwd: '/work' })

  const hide = await $.command.run({ command: 'context-bar', args: '' })
  expect(hide.text).toMatch(/hidden/)
  expect(saved.get('isVisible')).toBe(false)

  let ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect(await ui.find({ type: 'Text', text: '40%' })).toBeUndefined()
  expect(await ui.find({ type: 'Text', text: 'drawn by Claude Code' })).toBeDefined()
  await ui.unmount()

  const show = await $.command.run({ command: 'context-bar', args: '' })
  expect(show.text).toMatch(/shown/)
  expect(saved.get('isVisible')).toBe(true)
  ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect(await ui.find({ type: 'Text', text: '40%' })).toBeDefined()
  await ui.unmount()
})

test('a saved "hidden" survives /clear', async ($, on) => {
  mock.clock(on)
  on('store.get', () => ({ value: false }))
  on('session.usage', () => ({ value: usage }))
  on('classic.SessionStart', () => ({}))
  on('ui.render', () => ({ type: 'Text', props: {}, children: ['drawn by Claude Code'] }))
  await $.classic.SessionStart({ source: 'clear' })

  const ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect(await ui.find({ type: 'Text', text: '40%' })).toBeUndefined()
  await ui.unmount()
})

test('a survey in the band wins over the bar', async ($, on) => {
  mock.clock(on)
  on('session.start', () => ({ cwd: '/work' }))
  on('command.register', () => ({ value: undefined }))
  on('store.get', () => ({ value: undefined }))
  on('session.usage', () => ({ value: usage }))
  on('ui.render', () => ({ type: 'Text', props: {}, children: ['the survey'] }))
  await $.session.start({ surface: 'terminal', isInteractive: true, cwd: '/work' })

  const ui = await $.ui.mount({ ...BAND, surface: 'terminal', props: { ...BAND.props, hasSurvey: true } })
  expect(await ui.find({ type: 'Text', text: 'the survey' })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: '40%' })).toBeUndefined()
  await ui.unmount()
})
