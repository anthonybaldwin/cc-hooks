// The values this mod keeps in $.state (claude plugin validate checks every key the module names
// against this contract) and the shapes they hold.

/** One category of the context window, as /context lists it, minus what the bar doesn't need. */
export type Segment = {
  name: string
  tokens: number
  /** A theme colour key (`promptBorder`, `inactive`, `permission`, …) — what /context draws the row in. */
  color: string
  kind: 'used' | 'free' | 'buffer' | 'deferred'
}

/** The last breakdown the mod took, drawn until the next one replaces it. */
export type Snapshot = {
  categories: Segment[]
  totalTokens: number
  /** The window the breakdown measures against (the compaction window, which may be under the model's). */
  maxTokens: number
  /** `totalTokens` over `maxTokens`, whole percent; past 100 when over. */
  percentage: number
  model: string
  /** `$.clock.now()` when taken. */
  at: number
}

declare module 'claude-code' {
  interface PluginState {
    'context-bar': {
      snapshot: Snapshot | null
      isVisible: boolean
    }
  }
}
