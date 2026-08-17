import React, { useEffect } from 'react'
import { AgentFreeWebAppChat as SharedAgentFreeWebAppChat, type AgentFreeWebAppChatApiAdapter, type AgentFreeWebAppChatProps as SharedProps } from '@agentfree/webapp-chat'
import { readCurrentUser } from '../../auth'
import * as api from './api'

export type AgentFreeWebAppChatProps = Omit<SharedProps, 'apiAdapter'>

const apiAdapter: AgentFreeWebAppChatApiAdapter = {
  getAgents: api.getAgents,
  getSessions: api.getSessions,
  getSession: api.getSession,
  getMessages: api.getMessages,
  getSessionTimeline: api.getSessionTimeline,
  getSessionQueue: api.getSessionQueue,
  getStudioAgents: api.getStudioAgents,
  createSession: api.createSession,
  updateSession: api.updateSession,
  archiveSession: api.archiveSession,
  resetSessionContext: api.resetSessionContext,
  respondInteraction: api.respondInteraction,
  // The family gateway currently supports its established queue/steer wire values.
  streamChat: request => api.streamChat({
    ...request,
    messageMode: request.messageMode === 'steer' ? 'steer' : 'queue',
  }),
}

/** Thin HappyLife transport and identity adapter for the shared AgentFree chat. */
export function AgentFreeWebAppChat({ currentUser, webAppBotId, ...props }: AgentFreeWebAppChatProps) {
  const resolvedUser = currentUser || readCurrentUser()

  useEffect(() => {
    api.setAgentFreeWebAppCurrentUser(resolvedUser)
    api.setAgentFreeWebAppBotId(webAppBotId || '')
  }, [resolvedUser, webAppBotId])

  return <SharedAgentFreeWebAppChat {...props} webAppBotId={webAppBotId} currentUser={resolvedUser} apiAdapter={apiAdapter} />
}
