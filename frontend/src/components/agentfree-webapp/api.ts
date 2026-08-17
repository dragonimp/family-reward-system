import http from '../../services/api'
import { readCurrentUser } from '../../auth'
import type { Agent, ChatAttachment, ChatMessage, GatewayConversationEvent, Session, StudioAgent } from './types'

// Host-only transport adapter. Chat behavior lives in @agentfree/webapp-chat.

type AxiosLike<T> = Promise<{ data: T }>
type AgentFreeWebAppUser = {
  username?: string
  displayName?: string
  realName?: string
  role?: string
} | null

export const WEB_APP_BOT_ID = ''
let explicitCurrentUser: AgentFreeWebAppUser = null
let explicitWebAppBotId = ''

const wrap = async <T,>(value: Promise<T>): AxiosLike<T> => ({ data: await value })

export function setAgentFreeWebAppCurrentUser(user: AgentFreeWebAppUser) {
  explicitCurrentUser = user
}

export function setAgentFreeWebAppBotId(botId: string) {
  explicitWebAppBotId = botId.trim()
}

function getCurrentUser() {
  return explicitCurrentUser || readCurrentUser()
}

function getWebAppBotId() {
  return explicitWebAppBotId || WEB_APP_BOT_ID
}

function authHeaders() {
  const user = getCurrentUser()
  return {
    ...(user?.username ? { 'X-User-Name': user.username } : {}),
    ...(user?.role ? { 'X-User-Role': user.role } : {}),
  }
}

export const getAgents = (
  authorizedOnly = false,
  gatewayType?: string,
  user?: string,
  ownedOnly = false,
  webAppBotId?: string,
) => wrap(http.get<unknown, Agent[]>('/api/agentfree/agents', {
  headers: authHeaders(),
  params: {
    authorizedOnly: authorizedOnly || undefined,
    gatewayType: gatewayType && gatewayType !== 'All' ? gatewayType : undefined,
    user: user || undefined,
    ownedOnly: ownedOnly || undefined,
    webAppBotId: webAppBotId || getWebAppBotId(),
  },
}))

export const getSessions = (gatewayType?: string, user?: string, webAppBotId = getWebAppBotId()) => wrap(http.get<unknown, Session[]>('/api/agentfree/sessions', {
  headers: authHeaders(),
  params: {
    gatewayType: gatewayType && gatewayType !== 'All' ? gatewayType : undefined,
    user: user || undefined,
    webAppBotId: webAppBotId || getWebAppBotId(),
  },
}))

export const getSession = (id: string) => wrap(http.get<unknown, Session>(`/api/agentfree/sessions/${encodeURIComponent(id)}`, {
  headers: authHeaders(),
}))

export const getMessages = (sessionId: string, params?: { take?: number; beforeId?: number; ids?: string }) =>
  wrap(http.get<unknown, ChatMessage[]>(`/api/agentfree/sessions/${encodeURIComponent(sessionId)}/messages`, {
    headers: authHeaders(),
    params,
  }))

export const getSessionTimeline = (
  sessionId: string,
  params?: { turnId?: string; eventType?: string; includePayload?: boolean; take?: number },
) => wrap(http.get<unknown, GatewayConversationEvent[]>(`/api/agentfree/sessions/${encodeURIComponent(sessionId)}/timeline`, {
  headers: authHeaders(),
  params,
}))

export const getSessionQueue = (sessionId: string) =>
  wrap(http.get<unknown, unknown>(`/api/agentfree/sessions/${encodeURIComponent(sessionId)}/queue`, { headers: authHeaders() }))

export const getStudioAgents = (_params?: { mine?: boolean }): AxiosLike<StudioAgent[]> => Promise.resolve({ data: [] })

export const createSession = (data: { agentId: number; name?: string; webAppBotId?: string }) =>
  wrap(http.post<unknown, Session>('/api/agentfree/sessions', {
    ...data,
    webAppBotId: data.webAppBotId || getWebAppBotId(),
  }, { headers: authHeaders() }))

export const updateSession = (id: string, data: { name?: string; isArchived?: boolean }) =>
  wrap(http.put<unknown, unknown>(`/api/agentfree/sessions/${encodeURIComponent(id)}`, data, { headers: authHeaders() }))

export const archiveSession = (id: string) => updateSession(id, { isArchived: true })

export const resetSessionContext = (id: string) =>
  wrap(http.post<unknown, unknown>(`/api/agentfree/chat/sessions/${encodeURIComponent(id)}/reset`, undefined, { headers: authHeaders() }))

export const respondInteraction = (data: Record<string, unknown> & { interactionId: string }) =>
  wrap(http.post<unknown, { message: string }>(`/api/agentfree/interactions/${encodeURIComponent(data.interactionId)}/respond`, data, { headers: authHeaders() }))

export function streamChat(streamRequest: {
  sessionId: string
  content: string
  agentId?: number
  attachments?: ChatAttachment[]
  enableThinking?: boolean
  messageMode?: 'queue' | 'steer'
}): Promise<{ reader: ReadableStreamDefaultReader<Uint8Array>; abort: () => void }> {
  const abortController = new AbortController()
  const user = getCurrentUser()
  const responsePromise = fetch('/api/agentfree/chat/stream', {
    method: 'POST',
    credentials: 'include',
    headers: {
      'Content-Type': 'application/json',
      ...(user?.username ? { 'X-User-Name': user.username } : {}),
      ...(user?.role ? { 'X-User-Role': user.role } : {}),
    },
    body: JSON.stringify({
      sessionId: streamRequest.sessionId,
      agentId: streamRequest.agentId,
      message: streamRequest.content,
      attachments: streamRequest.attachments || [],
      currentUser: user,
      webAppBotId: getWebAppBotId(),
      enableThinking: streamRequest.enableThinking,
      messageMode: streamRequest.messageMode,
    }),
    signal: abortController.signal,
  })

  return responsePromise.then(async response => {
    if (!response.ok || !response.body) {
      const detail = await response.text().catch(() => '')
      throw new Error(`Stream request failed: ${response.status} ${response.statusText}${detail ? `: ${detail}` : ''}`)
    }
    return {
      reader: response.body.getReader(),
      abort: () => abortController.abort(),
    }
  })
}
