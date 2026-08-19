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
  // A normal WebApp message must be sent without a queue mode.  Mapping every
  // message to "queue" makes the Gateway legitimately emit a queue card for
  // every single turn.  Preserve the explicit steer action only.
  streamChat: ({ messageMode, ...request }) => api.streamChat({
    ...request,
    messageMode: messageMode === 'steer' ? 'steer' : undefined,
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
