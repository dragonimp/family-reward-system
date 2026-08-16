import { EventSchemas, EventType, type BaseEvent } from '@ag-ui/client'

export type AgUiEnvelope = {
  type?: string
  payload?: Record<string, unknown>
}

export function parseAgUiEnvelope(data: unknown): BaseEvent | null {
  if (!data || typeof data !== 'object') return null
  const envelope = data as AgUiEnvelope
  if (envelope.type !== 'stream.agui' || !envelope.payload) return null

  const payload = normalizeAgUiPayload(envelope.payload)
  const schema = EventSchemas as unknown as { safeParse?: (value: unknown) => { success: boolean; data?: BaseEvent } }
  if (!schema.safeParse) return payload as BaseEvent

  const parsed = schema.safeParse(payload)
  return parsed.success ? parsed.data! : payload as BaseEvent
}

export function parseA2UiEnvelope(data: unknown): Record<string, unknown> | null {
  if (!data || typeof data !== 'object') return null
  const envelope = data as AgUiEnvelope
  if (envelope.type !== 'stream.a2ui' || !envelope.payload) return null
  return envelope.payload
}

function normalizeAgUiPayload(payload: Record<string, unknown>): Record<string, unknown> {
  const normalized: Record<string, unknown> = { ...payload }
  const type = String(normalized.type || '')

  if (type === EventType.RUN_STARTED || type === EventType.RUN_FINISHED || type === EventType.RUN_ERROR) {
    delete normalized.threadId
  }

  if (type === EventType.TEXT_MESSAGE_START && !normalized.role) {
    normalized.role = 'assistant'
  }

  if ((type === EventType.REASONING_MESSAGE_START || type === EventType.TEXT_MESSAGE_START) && !normalized.messageId) {
    normalized.messageId = `${type.toLowerCase()}-${Date.now()}`
  }

  return normalized
}
