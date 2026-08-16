export interface Agent {
  id: number
  name: string
  description?: string
  agentType?: string
  agentCode?: string
  configJson?: string
  agentId?: number
  groupName?: string
  sortOrder?: number
  status: string
}

export interface StudioAgent {
  id: number
  name: string
}

export interface Session {
  id: string
  agentId: number
  agentName?: string
  agentType?: string
  agentCode?: string
  agentConfigJson?: string
  agentStatus?: string
  studioAgentName?: string
  userId?: number
  userName?: string
  name: string
  gatewayType?: string
  gatewayTypeLabel?: string
  isResponding?: boolean
  pendingUserMessage?: string
  respondingStartedAt?: string
  createdAt: string
  updatedAt: string
}

export interface ChatAttachment {
  type: string
  name?: string
  mediaType?: string
  size?: number
  url?: string
  dataUrl?: string
  fileId?: string
  mediaId?: string
  metadata?: Record<string, string>
}

export interface ChatMessage {
  id: number
  sessionId: string
  requestId?: string
  role: 'system' | 'user' | 'assistant'
  senderName?: string
  content: string
  toolCallId?: string
  toolTraceJson?: string
  processPartsJson?: string
  attachmentsJson?: string
  a2UiJson?: string
  createdAt: string
}

export interface GatewayConversationEvent {
  id: number
  sessionId: string
  turnId: string
  requestId?: string
  sequence: number
  eventType: string
  role: string
  channel?: string
  content?: string
  payloadJson?: string
  payloadPreview?: string
  payloadTruncated?: boolean
  toolCallId?: string
  toolName?: string
  a2UiType?: string
  messageId?: number
  createdAt: string
}
