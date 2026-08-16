import type { A2UiMessage } from './types'

export type InteractionDeliveryRef = {
  interactionId: string
  actionToken: string
}

/**
 * Delivery metadata may wrap the A2UI document or be copied into a component action.
 * Keep rendering independent from that transport shape and locate it at submit time.
 */
export function findInteractionDelivery(messages: A2UiMessage[]): InteractionDeliveryRef | null {
  for (let index = messages.length - 1; index >= 0; index -= 1) {
    const found = visit(messages[index], 0)
    if (found) return found
  }
  return null
}

function visit(value: unknown, depth: number): InteractionDeliveryRef | null {
  if (!value || typeof value !== 'object' || depth > 6) return null
  const record = value as Record<string, unknown>
  const interactionId = text(record.interactionId ?? record.interaction_id)
  const actionToken = text(record.actionToken ?? record.action_token)
  if (interactionId && actionToken) return { interactionId, actionToken }

  for (const child of Object.values(record)) {
    if (!child || typeof child !== 'object') continue
    const found = visit(child, depth + 1)
    if (found) return found
  }
  return null
}

function text(value: unknown) {
  return typeof value === 'string' ? value.trim() : ''
}
