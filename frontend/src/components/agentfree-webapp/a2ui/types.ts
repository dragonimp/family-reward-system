export type A2UiAction =
  | { type: 'event'; name: string; context?: Record<string, unknown>; dataModel?: unknown }
  | { type: 'function'; name: string; args?: Record<string, unknown>; dataModel?: unknown }
  | { type: 'open_url'; url: string; dataModel?: unknown }
  | { type: 'send_message'; text: string; dataModel?: unknown }
  | { type: 'unknown'; payload: unknown; dataModel?: unknown }

export type A2UiMessage = Record<string, unknown>

export type A2UiBlock = {
  id: string
  messages: A2UiMessage[]
}

export type A2UiRendererProps = {
  messages: A2UiMessage[]
  onAction: (action: A2UiAction) => void | Promise<void>
}

export type A2UiComponent = {
  id: string
  component: string
  [key: string]: unknown
}

export type A2UiSurface = {
  surfaceId: string
  catalogId?: string
  components: Map<string, A2UiComponent>
  dataModel: unknown
  rootId: string
}
