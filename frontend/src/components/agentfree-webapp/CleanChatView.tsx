import React, { useCallback, useEffect, useRef, useState } from 'react'
import { Alert, Button, Collapse, Dropdown, Input, Modal, Spin, Switch, Tag, Tooltip, Typography, Upload, message } from 'antd'
import { ApiOutlined, AudioOutlined, CheckCircleOutlined, CodeOutlined, CopyOutlined, DownOutlined, EditOutlined, ExclamationCircleOutlined, LoadingOutlined, MessageOutlined, OrderedListOutlined, PaperClipOutlined, SendOutlined, StopOutlined, ThunderboltOutlined, ToolOutlined } from '@ant-design/icons'
import ReactMarkdown from 'react-markdown'
import remarkBreaks from 'remark-breaks'
import remarkGfm from 'remark-gfm'
import { getMessages, getSession, getSessionTimeline, resetSessionContext, respondInteraction, streamChat } from './api'
import { parseA2UiEnvelope, parseAgUiEnvelope } from './agui/protocol'
import { A2UiRenderer } from './a2ui/A2UiRenderer'
import type { A2UiAction, A2UiMessage } from './a2ui/types'
import { findInteractionDelivery } from './a2ui/interactionDelivery'
import type { ChatAttachment, ChatMessage, GatewayConversationEvent, Session as SessionType } from './types'
import { isImeComposing } from './chatKeyboard'

const { Text } = Typography
const { TextArea } = Input

interface CleanChatViewProps {
  sessionId: string
  agentId?: number
  agentName?: string
  agentType?: string
  agentCode?: string
  agentConfigJson?: string
  agentStatus?: string
  studioAgentName?: string
  onSessionUpdated?: () => void
}

type LiveTool = {
  id: string
  name: string
  args: string
  result: string
  status: 'running' | 'done' | 'error'
}

type LiveSkill = {
  id: number | string
  key?: string
  name: string
  description?: string
  tools?: string[]
}

type LiveProcessPart =
  | { id: string; type: 'text'; content: string }
  | { id: string; type: 'thinking'; content: string; status: 'running' | 'done' }
  | { id: string; type: 'tool'; tool: LiveTool }
  | { id: string; type: 'skill'; skills: LiveSkill[] }
  | { id: string; type: 'a2ui'; messages: A2UiMessage[] }
  | { id: string; type: 'error'; message: string }

type LiveState = {
  running: boolean
  text: string
  thinking: string
  tools: LiveTool[]
  a2ui: A2UiMessage[]
  parts: LiveProcessPart[]
  error: string
}

type A2UiModalState = {
  open: boolean
  messages: A2UiMessage[]
  title: string
  source: 'live' | 'history'
}

type CodexMessageMode = 'queue' | 'steer'

type QueuedMessage = {
  id: string
  content: string
  mode: CodexMessageMode
  status: 'queued' | 'running' | 'error'
  createdAt: string
  steerCount?: number
}

const emptyLive = (): LiveState => ({
  running: false,
  text: '',
  thinking: '',
  tools: [],
  a2ui: [],
  parts: [],
  error: '',
})

const liveSnapshotStore = new Map<string, LiveState>()
const liveSnapshotSubscribers = new Map<string, Set<(live: LiveState) => void>>()
const liveAborters = new Map<string, () => void>()
const queueSnapshotStore = new Map<string, QueuedMessage[]>()
const queueSnapshotSubscribers = new Map<string, Set<(items: QueuedMessage[]) => void>>()
const queueCollapsedStore = new Map<string, boolean>()
const activeStreamCounts = new Map<string, number>()

function readQueueSnapshot(sessionId: string) {
  return queueSnapshotStore.get(sessionId) || []
}

function publishQueueSnapshot(sessionId: string, updater: (items: QueuedMessage[]) => QueuedMessage[]) {
  const next = updater(readQueueSnapshot(sessionId))
  if (next.length > 0) queueSnapshotStore.set(sessionId, next)
  else queueSnapshotStore.delete(sessionId)
  queueSnapshotSubscribers.get(sessionId)?.forEach(listener => listener(next))
  return next
}

function subscribeQueueSnapshot(sessionId: string, listener: (items: QueuedMessage[]) => void) {
  const listeners = queueSnapshotSubscribers.get(sessionId) || new Set<(items: QueuedMessage[]) => void>()
  listeners.add(listener)
  queueSnapshotSubscribers.set(sessionId, listeners)
  return () => {
    listeners.delete(listener)
    if (listeners.size === 0) queueSnapshotSubscribers.delete(sessionId)
  }
}

function queueModeOf(value: unknown): CodexMessageMode {
  return String(value || '').toLowerCase() === 'steer' ? 'steer' : 'queue'
}

function readRuntimeQueueItems(payload: any): QueuedMessage[] | null {
  const rawItems = Array.isArray(payload?.waitingItems)
    ? payload.waitingItems
    : Array.isArray(payload?.waiting)
      ? payload.waiting
      : null
  if (!rawItems) return null
  return rawItems.map((item: any, index: number) => ({
    id: String(item?.id || item?.messageId || `runtime-queue-${index + 1}`),
    content: String(item?.summary || item?.content || '附件消息'),
    mode: queueModeOf(item?.mode),
    status: String(item?.status || '').toLowerCase() === 'running' ? 'running' : 'queued',
    createdAt: String(item?.enqueuedAt || item?.createdAt || payload?.timestamp || new Date().toISOString()),
    steerCount: Number(item?.steerCount || 0),
  }))
}

function activeStreamCount(sessionId: string) {
  return activeStreamCounts.get(sessionId) || 0
}

function changeActiveStreamCount(sessionId: string, delta: number) {
  const next = Math.max(0, activeStreamCount(sessionId) + delta)
  if (next > 0) activeStreamCounts.set(sessionId, next)
  else activeStreamCounts.delete(sessionId)
  return next
}

function hasLiveSnapshotContent(live: LiveState) {
  return live.running
    || Boolean(live.text.trim())
    || Boolean(live.thinking.trim())
    || live.tools.length > 0
    || live.a2ui.length > 0
    || live.parts.length > 0
    || Boolean(live.error.trim())
}

function liveSnapshotKey(sessionId: string) {
  return `agentfree.chat.live.${sessionId}`
}

function readLiveSnapshot(sessionId: string): LiveState | null {
  const inMemory = liveSnapshotStore.get(sessionId)
  if (inMemory && hasLiveSnapshotContent(inMemory)) return inMemory
  try {
    const raw = sessionStorage.getItem(liveSnapshotKey(sessionId))
    if (!raw) return null
    const parsed = JSON.parse(raw) as LiveState
    return parsed && hasLiveSnapshotContent(parsed) ? parsed : null
  } catch {
    return null
  }
}

function publishLiveSnapshot(sessionId: string, live: LiveState) {
  if (hasLiveSnapshotContent(live)) {
    liveSnapshotStore.set(sessionId, live)
    try { sessionStorage.setItem(liveSnapshotKey(sessionId), JSON.stringify(live)) } catch {
      // Storage can be unavailable in privacy mode; the in-memory snapshot remains authoritative.
    }
  } else {
    liveSnapshotStore.delete(sessionId)
    liveAborters.delete(sessionId)
    try { sessionStorage.removeItem(liveSnapshotKey(sessionId)) } catch {
      // Storage can be unavailable in privacy mode; in-memory cleanup already completed.
    }
  }
  liveSnapshotSubscribers.get(sessionId)?.forEach(listener => listener(live))
}

function subscribeLiveSnapshot(sessionId: string, listener: (live: LiveState) => void) {
  const listeners = liveSnapshotSubscribers.get(sessionId) || new Set<(live: LiveState) => void>()
  listeners.add(listener)
  liveSnapshotSubscribers.set(sessionId, listeners)
  return () => {
    listeners.delete(listener)
    if (listeners.size === 0) liveSnapshotSubscribers.delete(sessionId)
  }
}

function setLiveAborter(sessionId: string, abort: () => void) {
  liveAborters.set(sessionId, abort)
}

function abortLiveStream(sessionId: string) {
  liveAborters.get(sessionId)?.()
  liveAborters.delete(sessionId)
}

const markdownComponents = {
  p: ({ children }: { children?: React.ReactNode }) => <p style={{ margin: '0 0 8px', whiteSpace: 'pre-wrap', overflowWrap: 'anywhere', wordBreak: 'break-word', minWidth: 0 }}>{children}</p>,
  ul: ({ children }: { children?: React.ReactNode }) => <ul style={{ margin: '4px 0 8px', paddingLeft: 20, minWidth: 0, overflowWrap: 'anywhere' }}>{children}</ul>,
  ol: ({ children }: { children?: React.ReactNode }) => <ol style={{ margin: '4px 0 8px', paddingLeft: 20, minWidth: 0, overflowWrap: 'anywhere' }}>{children}</ol>,
  li: ({ children }: { children?: React.ReactNode }) => <li style={{ margin: '2px 0', whiteSpace: 'normal', overflowWrap: 'anywhere', wordBreak: 'break-word', minWidth: 0 }}>{children}</li>,
  pre: ({ children }: { children?: React.ReactNode }) => <pre style={{ margin: '8px 0', padding: 12, borderRadius: 6, background: '#f6f8fa', maxWidth: '100%', overflowX: 'auto', whiteSpace: 'pre-wrap', overflowWrap: 'anywhere', wordBreak: 'break-word' }}>{children}</pre>,
  code: ({ children }: { children?: React.ReactNode }) => <code style={{ background: '#f6f8fa', borderRadius: 4, padding: '1px 4px', whiteSpace: 'pre-wrap', overflowWrap: 'anywhere', wordBreak: 'break-word' }}>{children}</code>,
  a: ({ href, children }: { href?: string; children?: React.ReactNode }) => <a href={href} target="_blank" rel="noreferrer" style={{ overflowWrap: 'anywhere', wordBreak: 'break-word' }}>{children}</a>,
}

function MarkdownText({ text }: { text: string }) {
  return (
    <ReactMarkdown remarkPlugins={[remarkGfm, remarkBreaks]} components={markdownComponents}>
      {text}
    </ReactMarkdown>
  )
}

function messageSummary(text: string) {
  const normalized = text.replace(/\s+/g, ' ').trim()
  if (!normalized) return '附件消息'
  return normalized.length > 72 ? `${normalized.slice(0, 72)}...` : normalized
}

function QueuePanel({ items, collapsed, onToggle, onGuide }: { items: QueuedMessage[]; collapsed: boolean; onToggle: () => void; onGuide: (item: QueuedMessage) => void }) {
  if (items.length === 0) return null
  const queuedCount = items.filter(item => item.status === 'queued').length
  return (
    <div style={{ display: 'flex', justifyContent: 'center', pointerEvents: 'none' }}>
      <div
        style={{
          width: 'min(760px, calc(100% - 24px))',
          border: '1px solid #bfd7ff',
          background: 'linear-gradient(135deg, #f8fbff 0%, #edf5ff 100%)',
          borderRadius: 14,
          padding: '10px 12px',
          boxShadow: '0 16px 42px rgba(45, 99, 173, 0.20)',
          pointerEvents: 'auto',
        }}
      >
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 10, marginBottom: 8 }}>
          <span style={{ display: 'inline-flex', alignItems: 'center', gap: 8, minWidth: 0 }}>
            <Text strong style={{ color: '#2459a8' }}>消息队列</Text>
            <Tag color="blue" style={{ margin: 0 }}>{queuedCount > 0 ? `${queuedCount} 条等待` : '正在接续'}</Tag>
          </span>
          <Button size="small" type="text" onClick={onToggle}>
            {collapsed ? '展开' : '收起'} <DownOutlined rotate={collapsed ? 0 : 180} />
          </Button>
        </div>
        {!collapsed && <div style={{ display: 'grid', gap: 6, maxHeight: 220, overflowY: 'auto', paddingRight: 2 }}>
          {items.map((item, index) => (
            <div
              key={item.id}
              style={{
                display: 'grid',
                gridTemplateColumns: 'auto 1fr auto auto',
                alignItems: 'center',
                gap: 8,
                minWidth: 0,
                padding: '7px 9px',
                borderRadius: 10,
                background: item.status === 'running' ? '#fff' : 'rgba(255,255,255,0.72)',
                border: '1px solid rgba(91, 142, 213, 0.18)',
              }}
            >
              <Tag color={item.status === 'running' ? 'processing' : item.status === 'error' ? 'error' : 'default'} style={{ margin: 0 }}>
                #{index + 1}
              </Tag>
              <Text ellipsis style={{ minWidth: 0, color: '#26415f' }}>
                {item.mode === 'steer' ? '补充说明：' : '排队消息：'}{messageSummary(item.content)}
              </Text>
              <Text type="secondary" style={{ fontSize: 12, whiteSpace: 'nowrap' }}>
                {item.status === 'running' ? '执行中' : item.status === 'error' ? '异常' : '等待中'}
              </Text>
              <Button size="small" type="link" style={{ paddingInline: 4 }} onClick={() => onGuide(item)}>
                引导
              </Button>
            </div>
          ))}
        </div>}
      </div>
    </div>
  )
}

function parseServerTime(value?: string) {
  if (!value) return ''
  const normalized = value.includes(' ') ? value.replace(' ', 'T') : value
  const withZone = /([zZ]|[+-]\d{2}:\d{2})$/.test(normalized) ? normalized : `${normalized}Z`
  const date = new Date(withZone)
  if (Number.isNaN(date.getTime())) return ''
  return new Intl.DateTimeFormat('zh-CN', {
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
  }).format(date)
}

function decodeDisplayText(text?: string | null) {
  return (text || '')
    .replace(/\\u([0-9a-fA-F]{4})/g, (_, hex) => String.fromCharCode(parseInt(hex, 16)))
    .replace(/\\n/g, '\n')
    .replace(/\\r/g, '')
    .replace(/\\t/g, '  ')
}

function displayMessageText(text?: string | null) {
  const decoded = stripThinkMarkup(decodeDisplayText(text))
    .replace(/\[GatewayFile\][\s\S]*?\[\/GatewayFile\]/gi, '')
    .trim()
  if (decoded.startsWith('[A2UI_ACTION]')) return summarizePersistedA2UiAction(decoded)
  const marker = '【用户问题】'
  const markerIndex = decoded.indexOf(marker)
  if (markerIndex >= 0) return decoded.slice(markerIndex + marker.length).trim()
  return decoded
}

function stripThinkMarkup(text: string) {
  return text
    .replace(/<think\b[^>]*>[\s\S]*?<\/think>/gi, '')
    .replace(/<\/?think\b[^>]*>/gi, '')
}

function summarizePersistedA2UiAction(text: string) {
  const raw = text.replace(/^\[A2UI_ACTION\]\s*/i, '').trim()
  try {
    const payload = JSON.parse(raw)
    return summarizeA2UiAction(payload?.action) || '已提交交互操作'
  } catch {
    return '已提交交互操作'
  }
}

function summarizeA2UiAction(action?: A2UiAction | null) {
  if (!action) return ''
  if (action.type === 'send_message') return action.text?.trim() || '已发送交互消息'
  if (action.type === 'open_url') return `打开链接：${action.url}`

  const context = action.type === 'event' ? action.context : action.type === 'function' ? action.args : undefined
  const contextSummary = summarizePlainObject(context)
  const dataSummary = summarizeDataModel(action.dataModel)

  if (action.type === 'event') {
    if (contextSummary) return `我选择了：${contextSummary}`
    if (dataSummary) return `我输入了：${dataSummary}`
    return `我选择了：${action.name}`
  }

  if (action.type === 'function') {
    if (contextSummary) return `我提交了：${contextSummary}`
    if (dataSummary) return `我输入了：${dataSummary}`
    return `我提交了：${action.name}`
  }

  if (dataSummary) return `我输入了：${dataSummary}`
  return '已提交交互操作'
}

function summarizePlainObject(value: unknown) {
  if (!value || typeof value !== 'object') return primitiveLabel(value)
  const direct = value as Record<string, unknown>
  const label = primitiveLabel(direct.label)
  if (label) return label
  const directValue = primitiveLabel(direct.value)
  if (directValue) return directValue
  const entries = Object.entries(value as Record<string, unknown>)
    .map(([key, item]) => {
      const label = primitiveLabel(item)
      if (!label) return ''
      if (key === 'label') return label
      if (key === 'choice') return label === 'yes' ? '同意' : label === 'no' ? '拒绝' : label
      return `${key}=${label}`
    })
    .filter(Boolean)
  return entries.slice(0, 4).join('，')
}

function summarizeDataModel(value: unknown) {
  const pairs: string[] = []
  collectDataModelPairs(value, pairs)
  return pairs.slice(0, 5).join('，')
}

function collectDataModelPairs(value: unknown, pairs: string[], path: string[] = []) {
  if (pairs.length >= 8 || value == null) return
  if (Array.isArray(value)) {
    const label = value.map(primitiveLabel).filter(Boolean).join('、')
    if (label) pairs.push(`${path[path.length - 1] || 'value'}=${label}`)
    return
  }
  if (typeof value === 'object') {
    for (const [key, item] of Object.entries(value as Record<string, unknown>)) {
      collectDataModelPairs(item, pairs, [...path, key])
    }
    return
  }
  const label = primitiveLabel(value)
  if (label) pairs.push(`${path[path.length - 1] || 'value'}=${label}`)
}

function primitiveLabel(value: unknown) {
  if (value == null) return ''
  if (typeof value === 'string') return value.trim()
  if (typeof value === 'number' || typeof value === 'boolean') return String(value)
  return ''
}

function parseJsonArray<T>(raw?: string | null): T[] {
  if (!raw) return []
  try {
    const parsed = JSON.parse(raw)
    return Array.isArray(parsed) ? parsed : []
  } catch {
    try {
      const parsed = JSON.parse(decodeDisplayText(raw))
      return Array.isArray(parsed) ? parsed : []
    } catch {
      return []
    }
  }
}

function normalizeAttachment(raw: any): ChatAttachment {
  return {
    type: raw.type ?? raw.Type ?? 'file',
    name: raw.name ?? raw.Name,
    mediaType: raw.mediaType ?? raw.MediaType ?? raw.media_type,
    url: raw.url ?? raw.Url,
    dataUrl: raw.dataUrl ?? raw.DataUrl ?? raw.data_url,
    fileId: raw.fileId ?? raw.FileId ?? raw.file_id,
    mediaId: raw.mediaId ?? raw.MediaId ?? raw.media_id,
    size: raw.size ?? raw.Size,
    metadata: raw.metadata ?? raw.Metadata,
  }
}

function parseAttachments(raw?: string | null): ChatAttachment[] {
  return parseJsonArray<any>(raw).map(normalizeAttachment)
}

function parseA2UiMessages(raw?: string | null): A2UiMessage[] {
  return parseJsonArray<any>(raw).flatMap(item => {
    if (item?.content && typeof item.content === 'object') return [item.content as A2UiMessage]
    if (item && typeof item === 'object') return [item as A2UiMessage]
    return []
  })
}

function summarizeA2UiRequest(messages: A2UiMessage[]) {
  const components = collectA2UiComponents(messages)
  if (components.length === 0) return '需要完成交互操作'

  const text = components
    .map(component => primitiveLabel(component.text) || primitiveLabel(component.title) || '')
    .find(Boolean)
  const fields = components.filter(component => {
    const name = normalizeA2UiComponentName(component.component)
    return ['datetimeinput', 'dateinput', 'date', 'textfield', 'textinput', 'choicepicker', 'select'].includes(name)
  })
  const buttons = components.filter(component => normalizeA2UiComponentName(component.component) === 'button')
  const fieldLabel = fields.map(component => primitiveLabel(component.label) || primitiveLabel(component.placeholder) || primitiveLabel(component.title) || '').find(Boolean)

  if (fields.some(component => ['datetimeinput', 'dateinput', 'date'].includes(normalizeA2UiComponentName(component.component)))) {
    return `请选择日期${fieldLabel ? `：${fieldLabel}` : text ? `：${text}` : ''}`
  }
  if (fields.some(component => ['textfield', 'textinput'].includes(normalizeA2UiComponentName(component.component)))) {
    return `请填写${fieldLabel ? `：${fieldLabel}` : text ? `：${text}` : ''}`
  }
  if (fields.some(component => ['choicepicker', 'select'].includes(normalizeA2UiComponentName(component.component)))) {
    return `请选择${fieldLabel ? `：${fieldLabel}` : text ? `：${text}` : ''}`
  }
  if (buttons.length > 0) {
    return `请确认${text ? `：${text}` : ''}`
  }
  return text || '需要完成交互操作'
}

function collectA2UiComponents(messages: A2UiMessage[]) {
  const components: Array<Record<string, unknown>> = []
  for (const message of messages) {
    const payload = unwrapA2UiPayload(message)
    const directComponents = (payload as any)?.updateComponents?.components || (payload as any)?.createSurface?.components
    if (Array.isArray(directComponents)) components.push(...directComponents.filter(looksLikeA2UiComponent))
    if (looksLikeA2UiComponent(payload)) components.push(payload)
  }
  return components
}

function unwrapA2UiPayload(message: A2UiMessage): Record<string, unknown> | null {
  const content = (message as any)?.content
  if (Array.isArray(content)) return { updateComponents: { components: content } }
  if (content && typeof content === 'object') return content
  if (Array.isArray((message as any)?.data)) return { updateComponents: { components: (message as any).data } }
  return message && typeof message === 'object' ? message : null
}

function looksLikeA2UiComponent(value: unknown): value is Record<string, unknown> {
  return !!value && typeof value === 'object' && typeof (value as any).component === 'string'
}

function normalizeA2UiComponentName(value: unknown) {
  return typeof value === 'string' ? value.replace(/[\s_-]/g, '').toLowerCase() : ''
}

function readDelta(event: any) {
  return decodeDisplayText(String(event?.delta ?? event?.content ?? event?.message ?? ''))
}

function appendTool(tools: LiveTool[], patch: Partial<LiveTool> & { id: string }) {
  const index = tools.findIndex(tool => tool.id === patch.id)
  if (index < 0) {
    return [...tools, { id: patch.id, name: patch.name || patch.id, args: patch.args || '', result: patch.result || '', status: patch.status || 'running' }]
  }
  return tools.map((tool, i) => i === index ? { ...tool, ...patch, args: patch.args != null ? tool.args + patch.args : tool.args, result: patch.result != null ? tool.result + patch.result : tool.result } : tool)
}

function appendTextPart(parts: LiveProcessPart[], delta: string): LiveProcessPart[] {
  const last = parts[parts.length - 1]
  if (last?.type === 'text') {
    return [...parts.slice(0, -1), { ...last, content: last.content + delta }]
  }
  return [...parts, { id: `text-${Date.now()}-${parts.length}`, type: 'text' as const, content: delta }]
}

function appendThinkingPart(parts: LiveProcessPart[], delta: string): LiveProcessPart[] {
  const last = parts[parts.length - 1]
  if (last?.type === 'thinking') {
    return [...parts.slice(0, -1), { ...last, content: last.content + delta, status: 'running' as const }]
  }
  return [...parts, { id: `thinking-${Date.now()}-${parts.length}`, type: 'thinking' as const, content: delta, status: 'running' as const }]
}

function finishThinkingParts(parts: LiveProcessPart[]): LiveProcessPart[] {
  return parts.map(part => part.type === 'thinking' ? { ...part, status: 'done' as const } : part)
}

function upsertToolPart(parts: LiveProcessPart[], tool: LiveTool): LiveProcessPart[] {
  const index = parts.findIndex(part => part.type === 'tool' && part.tool.id === tool.id)
  if (index < 0) return [...parts, { id: `tool-${tool.id}`, type: 'tool' as const, tool }]
  return parts.map((part, i) => i === index && part.type === 'tool' ? { ...part, tool } : part)
}

function upsertSkillPart(parts: LiveProcessPart[], skills: LiveSkill[]): LiveProcessPart[] {
  if (skills.length === 0) return parts
  const index = parts.findIndex(part => part.type === 'skill')
  if (index < 0) return [...parts, { id: `skill-${Date.now()}-${parts.length}`, type: 'skill' as const, skills }]
  return parts.map((part, i) => i === index && part.type === 'skill' ? { ...part, skills } : part)
}

function appendA2UiPart(parts: LiveProcessPart[], messages: A2UiMessage[]): LiveProcessPart[] {
  const last = parts[parts.length - 1]
  if (last?.type === 'a2ui') {
    return [...parts.slice(0, -1), { ...last, messages: [...last.messages, ...messages] }]
  }
  return [...parts, { id: `a2ui-${Date.now()}-${parts.length}`, type: 'a2ui' as const, messages }]
}


function hashText(text: string) {
  let hash = 0
  for (let i = 0; i < text.length; i += 1) {
    hash = ((hash << 5) - hash) + text.charCodeAt(i)
    hash |= 0
  }
  return hash
}

function parseTimelinePayload(event: GatewayConversationEvent): any {
  if (!event.payloadJson) return null
  try {
    return JSON.parse(event.payloadJson)
  } catch {
    return null
  }
}

function a2uiMessageFromTimeline(event: GatewayConversationEvent): A2UiMessage[] {
  const payload = parseTimelinePayload(event)
  if (!payload) return []
  if (payload.content && typeof payload.content === 'object') return [payload.content as A2UiMessage]
  if (typeof payload === 'object') return [payload as A2UiMessage]
  return []
}

function skillsFromPayload(payload: any): LiveSkill[] {
  const rawSkills = Array.isArray(payload?.skills) ? payload.skills : []
  return rawSkills.map((item: any, index: number) => {
    const tools = Array.isArray(item?.tools)
      ? item.tools.map((tool: unknown) => primitiveLabel(tool)).filter(Boolean)
      : []
    return {
      id: item?.id ?? item?.skillId ?? item?.skill_id ?? index,
      key: primitiveLabel(item?.key ?? item?.skillKey ?? item?.skill_key) || undefined,
      name: primitiveLabel(item?.name) || primitiveLabel(item?.skillName ?? item?.skill_name) || `技能 ${index + 1}`,
      description: primitiveLabel(item?.description) || undefined,
      tools,
    }
  })
}

function timelineEventsToMessageParts(events: GatewayConversationEvent[]) {
  const byTurn = new Map<string, GatewayConversationEvent[]>()
  for (const event of events) {
    const list = byTurn.get(event.turnId) || []
    list.push(event)
    byTurn.set(event.turnId, list)
  }

  const partsByMessageId = new Map<number, LiveProcessPart[]>()
  byTurn.forEach(turnEvents => {
    const ordered = turnEvents.slice().sort((a, b) => a.sequence - b.sequence)
    const assistantMessage = ordered.find(event => event.eventType === 'message' && event.role === 'assistant' && event.messageId)
    if (!assistantMessage?.messageId) return

    let parts: LiveProcessPart[] = []
    let tools: LiveTool[] = []
    for (const event of ordered) {
      if (event.eventType === 'stream') {
        const text = event.content || ''
        if (!text) continue
        if (event.channel === 'thinking') parts = appendThinkingPart(parts, text)
        else if (event.channel === 'content') parts = appendTextPart(parts, text)
        continue
      }

      if (event.eventType === 'tool') {
        const payload = parseTimelinePayload(event)
        const aguiType = String(payload?.aguiType || payload?.type || '').toUpperCase()
        const status = String(payload?.status || '').toLowerCase()
        const rawToolId = String(event.toolCallId || payload?.toolCallId || '').trim()
        const contentToolIdentity = (event.content || '').match(/command:\s*([^\n]+)/i)?.[1]?.trim()
          || (event.content || '').match(/\[工具调用\]([^\n]+)/)?.[1]?.trim()
          || ''
        const id = rawToolId || `tool-${event.toolName || payload?.toolCallName || payload?.toolName || event.channel || 'call'}-${Math.abs(hashText(contentToolIdentity || event.content || String(event.sequence)))}`
        const name = String(event.toolName || payload?.toolCallName || payload?.toolName || contentToolIdentity || id)
        const content = event.content || ''
        const payloadArgs = payload?.arguments ?? payload?.args ?? payload?.input
        const payloadResult = payload?.result ?? payload?.content ?? payload?.output
        const argsText = payloadArgs == null ? '' : typeof payloadArgs === 'string' ? payloadArgs : JSON.stringify(payloadArgs, null, 2)
        const resultText = payloadResult == null ? '' : typeof payloadResult === 'string' ? payloadResult : JSON.stringify(payloadResult, null, 2)
        const parsedToolName = extractToolNameFromText(resultText) || extractToolNameFromText(content) || extractToolNameFromText(argsText)
        const completedByText = /status:\s*(completed|complete|done|success|succeeded)/i.test(content)
        const failedByText = /status:\s*(failed|error)/i.test(content)
        const isTerminal = aguiType.includes('RESULT') || status === 'completed' || status === 'done' || status === 'error' || completedByText || failedByText
        const patch: Partial<LiveTool> & { id: string } = { id, name: parsedToolName || name, status: status === 'error' || failedByText ? 'error' : isTerminal ? 'done' : 'running' }
        if (isTerminal) patch.result = resultText || (completedByText ? '工具执行完成，未记录输出。' : content)
        else if (aguiType.includes('ARGS') || aguiType.includes('CHUNK')) patch.args = argsText
        else if (argsText || content) patch.args = argsText || content
        tools = appendTool(tools, patch)
        const tool = tools.find(item => item.id === id)
        if (tool) parts = upsertToolPart(parts, tool)
        continue
      }

      if (event.eventType === 'a2ui') {
        const messages = a2uiMessageFromTimeline(event)
        if (messages.length > 0) parts = appendA2UiPart(parts, messages)
        continue
      }

      if (event.eventType === 'agui') {
        const payload = parseTimelinePayload(event)
        if (String(payload?.type || '').toUpperCase() === 'SKILL_CONTEXT') {
          parts = upsertSkillPart(parts, skillsFromPayload(payload))
        }
        continue
      }

      if (event.eventType === 'error' && event.content) {
        parts = appendErrorPart(parts, event.content)
      }
    }

    if (parts.length > 0) {
      partsByMessageId.set(assistantMessage.messageId, finishThinkingParts(parts))
    }
  })
  return partsByMessageId
}

function attachTimelineParts(messages: ChatMessage[], events: GatewayConversationEvent[]) {
  if (events.length === 0) return messages
  const partsByMessageId = timelineEventsToMessageParts(events)
  const requestIdByMessageId = new Map<number, string>()
  events.forEach(event => {
    if (event.messageId && event.requestId) requestIdByMessageId.set(event.messageId, event.requestId)
  })
  if (partsByMessageId.size === 0 && requestIdByMessageId.size === 0) return messages
  return messages.map(message => {
    const parts = partsByMessageId.get(message.id)
    const requestId = requestIdByMessageId.get(message.id)
    return parts || requestId ? {
      ...message,
      requestId: requestId || message.requestId,
      processPartsJson: parts ? JSON.stringify(enrichToolParts(parts, parseJsonArray<Partial<LiveTool>>(message.toolTraceJson))) : message.processPartsJson,
    } : message
  })
}

function normalizeTraceText(value: unknown) {
  if (value == null) return ''
  if (typeof value !== 'string') return JSON.stringify(value, null, 2)
  const trimmed = value.trim()
  if (!trimmed) return ''
  try {
    const parsed = JSON.parse(trimmed)
    if (typeof parsed === 'string') return parsed
    return JSON.stringify(parsed, null, 2)
  } catch {
    return decodeDisplayText(trimmed)
  }
}

export function summarizeToolCommand(name: string, argsText: string, maxLength = 100) {
  const identity = name.toLowerCase()
  const keys = identity.includes('command') || identity.includes('exec')
    ? ['cmd', 'command']
    : identity.includes('search')
      ? ['query', 'url']
      : identity.includes('file') || identity.includes('patch') || identity.includes('image')
        ? ['path', 'file', 'url']
        : []
  let command = ''
  try {
    const parsed = JSON.parse(argsText)
    if (parsed && typeof parsed === 'object') {
      for (const key of keys) {
        if (parsed[key] != null) {
          command = String(parsed[key])
          break
        }
      }
    }
  } catch {
    if (identity.includes('command') || identity.includes('exec')) command = argsText
  }
  command = command.replace(/\s+/g, ' ').trim()
  return command.length <= maxLength ? command : `${command.slice(0, Math.max(0, maxLength - 3))}...`
}

function extractToolNameFromText(text?: string | null) {
  const value = text || ''
  return value.match(/工具\s+([^\s：:]+)\s+结果[:：]/)?.[1]?.trim()
    || value.match(/调用工具\s+([^\s：:]+)/)?.[1]?.trim()
    || value.match(/\[工具调用\]\s*([^\n]+)/)?.[1]?.trim()
    || ''
}

function resolveToolDisplayName(tool: Partial<LiveTool>, argsText = '', resultText = '') {
  const rawName = String(tool.name || '').trim()
  const rawId = String(tool.id || '').trim()
  const parsed = extractToolNameFromText(resultText) || extractToolNameFromText(argsText)
  if (rawName && rawName !== 'tool' && !rawName.startsWith('tool-')) return rawName
  if (parsed) return parsed
  if (rawId && rawId !== 'tool' && !rawId.startsWith('tool-')) return rawId
  return rawName || rawId || 'tool'
}

function enrichToolParts(parts: LiveProcessPart[], traces: Partial<LiveTool>[]) {
  if (traces.length === 0) return parts
  let index = 0
  const normalizeStatus = (status: unknown, fallback: LiveTool['status']): LiveTool['status'] => {
    const text = String(status || '').toLowerCase()
    if (text === 'completed' || text === 'done' || text === 'success' || text === 'succeeded') return 'done'
    if (text === 'failed' || text === 'error') return 'error'
    if (text === 'running' || text === 'started' || text === 'in_progress') return 'running'
    return fallback
  }
  return parts.map(part => {
    if (part.type !== 'tool') return part
    const trace = traces[index++]
    if (!trace) return part
    return {
      ...part,
      tool: {
        ...part.tool,
        name: resolveToolDisplayName(
          { ...part.tool, ...trace, name: String(trace.name || part.tool.name || trace.id || part.tool.id) },
          normalizeTraceText((trace as any).args ?? (trace as any).arguments) || part.tool.args,
          normalizeTraceText((trace as any).result) || part.tool.result),
        args: normalizeTraceText((trace as any).args ?? (trace as any).arguments) || part.tool.args,
        result: normalizeTraceText((trace as any).result) || part.tool.result,
        status: normalizeStatus(trace.status, part.tool.status),
      },
    }
  })
}

function appendErrorPart(parts: LiveProcessPart[], message: string): LiveProcessPart[] {
  if (!message) return parts
  return [...parts, { id: `error-${Date.now()}-${parts.length}`, type: 'error' as const, message }]
}

function isNearBottom(element: HTMLElement | null) {
  if (!element) return true
  return element.scrollHeight - element.scrollTop - element.clientHeight < 80
}

function statusTag(status?: string) {
  const normalized = String(status || '').toLowerCase()
  if (['done', 'completed', 'complete', 'success', 'succeeded'].includes(normalized)) return <Tag color="success" icon={<CheckCircleOutlined />} style={{ margin: 0 }}>已完成</Tag>
  if (['error', 'failed', 'failure'].includes(normalized)) return <Tag color="error" icon={<ExclamationCircleOutlined />} style={{ margin: 0 }}>失败</Tag>
  return <Tag color="processing" icon={<LoadingOutlined />} style={{ margin: 0 }}>运行中</Tag>
}

function ProcessTextBlock({ text }: { text: string }) {
  if (!text.trim()) return null
  return (
    <div style={{ border: '1px solid #e8e8e8', background: '#fff', borderRadius: 10, padding: '10px 12px', overflowWrap: 'anywhere', wordBreak: 'break-word', minWidth: 0, maxWidth: '100%' }}>
      <MarkdownText text={text} />
    </div>
  )
}

function ThoughtCard({ text, status = 'done' }: { text: string; status?: 'running' | 'done' }) {
  if (!text.trim()) return null
  const preview = text.trim().split('\n').find(Boolean) || '正在分析问题'
  return (
    <div style={{ borderLeft: '3px solid #8c8c8c', background: '#fafafa', borderRadius: 8, padding: '8px 10px', minWidth: 0, maxWidth: '100%', overflowWrap: 'anywhere', wordBreak: 'break-word' }}>
      <Collapse
        ghost
        size="small"
        defaultActiveKey={status === 'running' ? ['thinking'] : []}
        items={[{
          key: 'thinking',
          label: (
            <span style={{ display: 'inline-flex', alignItems: 'center', gap: 8, minWidth: 0 }}>
              <CodeOutlined />
              <span style={{ fontWeight: 600 }}>思考过程</span>
              <Text type="secondary" ellipsis style={{ maxWidth: 360 }}>{preview}</Text>
              {status === 'running' && <Tag color="processing" style={{ margin: 0 }}>进行中</Tag>}
            </span>
          ),
          children: <pre style={{ margin: 0, whiteSpace: 'pre-wrap', overflowWrap: 'anywhere', wordBreak: 'break-word', maxWidth: '100%', overflowX: 'hidden', fontFamily: 'inherit', color: '#4f4f4f' }}>{text}</pre>,
        }]}
      />
    </div>
  )
}

function ToolCallCard({ tool }: { tool: Partial<LiveTool> }) {
  const argsText = normalizeTraceText(tool.args)
  const resultText = normalizeTraceText(tool.result)
  const name = resolveToolDisplayName(tool, argsText, resultText)
  const commandSummary = summarizeToolCommand(name, argsText)
  const hasDetails = Boolean(argsText || resultText)
  const hasResult = Boolean(resultText)
  return (
    <div style={{ border: '1px solid #d9e7ff', background: '#fbfdff', borderRadius: 8, padding: 10, minWidth: 0, maxWidth: '100%', overflowWrap: 'anywhere', wordBreak: 'break-word' }}>
      <Collapse
        ghost
        size="small"
        defaultActiveKey={[]}
        items={[{
          key: 'tool',
          label: (
            <span style={{ display: 'inline-flex', alignItems: 'center', justifyContent: 'space-between', gap: 12, width: '100%', minWidth: 0 }}>
              <span style={{ display: 'inline-flex', alignItems: 'center', gap: 8, minWidth: 0 }}>
                <ApiOutlined style={{ color: '#1677ff', flexShrink: 0 }} />
                <Text strong ellipsis style={{ minWidth: 0 }}>工具调用：{name}</Text>
                {commandSummary && <Text type="secondary" ellipsis style={{ maxWidth: 360 }}>· {commandSummary}</Text>}
                {hasResult && <Tag color="blue" style={{ margin: 0, flexShrink: 0 }}>有结果</Tag>}
              </span>
              {statusTag(tool.status)}
            </span>
          ),
          children: hasDetails ? (
              <div style={{ display: 'grid', gap: 8, minWidth: 0, maxWidth: '100%' }}>
                {argsText && (
                  <div>
                    <Text type="secondary" style={{ fontSize: 12 }}>命令输入</Text>
                    <pre style={{ margin: '4px 0 0', maxHeight: hasResult ? 320 : 420, maxWidth: '100%', overflowY: 'auto', overflowX: 'hidden', whiteSpace: 'pre-wrap', overflowWrap: 'anywhere', wordBreak: 'break-word', background: '#fff7e6', border: '1px solid #ffe0a3', borderRadius: 6, padding: 8 }}>{argsText}</pre>
                  </div>
                )}
                {resultText && (
                  <div>
                    <Text type="secondary" style={{ fontSize: 12 }}>结果</Text>
                    <pre style={{ margin: '4px 0 0', maxHeight: 520, maxWidth: '100%', overflowY: 'auto', overflowX: 'hidden', whiteSpace: 'pre-wrap', overflowWrap: 'anywhere', wordBreak: 'break-word', background: '#f6f8fa', borderRadius: 6, padding: 8 }}>{resultText}</pre>
                  </div>
                )}
              </div>
          ) : <Text type="secondary">等待工具返回结果</Text>,
        }]}
      />
    </div>
  )
}

function A2UiInlineCard({ messages, source, onOpen }: { messages: A2UiMessage[]; source: 'live' | 'history'; onOpen: (messages: A2UiMessage[], title: string, source: 'live' | 'history') => void }) {
  const summary = summarizeA2UiRequest(messages)
  return (
    <div style={{ border: '1px solid #d8f0df', background: '#fbfffc', borderRadius: 8, padding: 10, display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 12 }}>
      <span style={{ display: 'inline-flex', alignItems: 'center', gap: 8, minWidth: 0 }}>
        <MessageOutlined style={{ color: '#389e0d', flexShrink: 0 }} />
        <Text ellipsis style={{ minWidth: 0 }}>{summary}</Text>
      </span>
      <Button size="small" type="link" onClick={() => onOpen(messages, summary, source)} style={{ padding: 0, flexShrink: 0 }}>查看</Button>
    </div>
  )
}

function SkillContextCard({ skills }: { skills: LiveSkill[] }) {
  if (skills.length === 0) return null
  return (
    <div style={{ border: '1px solid #d9e7ff', background: '#fbfdff', borderRadius: 8, padding: 10, minWidth: 0, maxWidth: '100%' }}>
      <Collapse
        ghost
        size="small"
        defaultActiveKey={[]}
        items={[{
          key: 'skills',
          label: (
            <span style={{ display: 'inline-flex', alignItems: 'center', gap: 8, minWidth: 0 }}>
              <ThunderboltOutlined style={{ color: '#1677ff', flexShrink: 0 }} />
              <Text strong>使用技能</Text>
              <Text type="secondary" style={{ fontSize: 12 }}>{skills.length} 个</Text>
            </span>
          ),
          children: (
            <div style={{ display: 'grid', gap: 8, minWidth: 0 }}>
              {skills.map(skill => (
                <div key={`${skill.id}-${skill.key || skill.name}`} style={{ display: 'grid', gap: 4, padding: '8px 10px', border: '1px solid #eef2f7', borderRadius: 6, background: '#fff', minWidth: 0 }}>
                  <span style={{ display: 'flex', alignItems: 'center', gap: 6, minWidth: 0, flexWrap: 'wrap' }}>
                    <Text strong style={{ minWidth: 0 }}>{skill.name}</Text>
                    {skill.key && <Tag style={{ margin: 0 }}>{skill.key}</Tag>}
                  </span>
                  {skill.description && <Text type="secondary" style={{ fontSize: 12, overflowWrap: 'anywhere', wordBreak: 'break-word' }}>{skill.description}</Text>}
                  {skill.tools && skill.tools.length > 0 && (
                    <Text type="secondary" style={{ fontSize: 12, overflowWrap: 'anywhere', wordBreak: 'break-word' }}>
                      绑定工具：{skill.tools.join('、')}
                    </Text>
                  )}
                </div>
              ))}
            </div>
          ),
        }]}
      />
    </div>
  )
}

function renderProcessPart(part: LiveProcessPart, source: 'live' | 'history', onOpenA2Ui: (messages: A2UiMessage[], title: string, source: 'live' | 'history') => void) {
  if (part.type === 'text') return <ProcessTextBlock key={part.id} text={part.content} />
  if (part.type === 'thinking') return <ThoughtCard key={part.id} text={part.content} status={part.status} />
  if (part.type === 'tool') return <ToolCallCard key={part.id} tool={part.tool} />
  if (part.type === 'skill') return <SkillContextCard key={part.id} skills={part.skills} />
  if (part.type === 'a2ui') return <A2UiInlineCard key={part.id} messages={part.messages} source={source} onOpen={onOpenA2Ui} />
  return <Alert key={part.id} type="error" showIcon message={part.message} />
}

function ProcessStack({ parts, fallbackText, onOpenA2Ui, source, compact = false }: {
  parts: LiveProcessPart[]
  fallbackText?: string
  onOpenA2Ui: (messages: A2UiMessage[], title: string, source: 'live' | 'history') => void
  source: 'live' | 'history'
  compact?: boolean
}) {
  const visibleParts = parts.length > 0 ? parts : fallbackText?.trim() ? [{ id: 'fallback-text', type: 'text' as const, content: fallbackText }] : []
  const processParts = visibleParts.filter(part => part.type !== 'text')
  const answerParts = visibleParts.filter(part => part.type === 'text')

  if (compact && processParts.length > 0) {
    const lastTextIndex = visibleParts.map(part => part.type).lastIndexOf('text')
    const finalAnswerParts = lastTextIndex >= 0 ? [visibleParts[lastTextIndex]] : []
    const handledParts = visibleParts.filter((_, index) => index !== lastTextIndex)
    const toolCount = handledParts.filter(part => part.type === 'tool').length
    const thinkingCount = handledParts.filter(part => part.type === 'thinking').length
    const skillCount = handledParts.reduce((sum, part) => part.type === 'skill' ? sum + part.skills.length : sum, 0)
    const a2uiCount = handledParts.filter(part => part.type === 'a2ui').length
    const noteCount = handledParts.filter(part => part.type === 'text').length
    const summary = [
      thinkingCount ? `思考 ${thinkingCount}` : '',
      skillCount ? `技能 ${skillCount}` : '',
      toolCount ? `工具 ${toolCount}` : '',
      noteCount ? `说明 ${noteCount}` : '',
      a2uiCount ? `交互 ${a2uiCount}` : '',
    ].filter(Boolean).join(' / ') || '处理过程'
    return (
      <div style={{ display: 'grid', gap: 8, minWidth: 0, maxWidth: '100%' }}>
        <Collapse
          size="small"
          style={{ background: '#fff', borderRadius: 10 }}
          items={[{
            key: 'processed',
            label: (
              <span style={{ display: 'inline-flex', alignItems: 'center', gap: 8 }}>
                <CheckCircleOutlined style={{ color: '#52c41a' }} />
                <Text strong>已处理</Text>
                <Text type="secondary" style={{ fontSize: 12 }}>{summary}</Text>
              </span>
            ),
            children: <div style={{ display: 'grid', gap: 8, minWidth: 0, maxWidth: '100%', overflow: 'hidden' }}>{handledParts.map(part => renderProcessPart(part, source, onOpenA2Ui))}</div>,
          }]}
        />
        {finalAnswerParts.map(part => renderProcessPart(part, source, onOpenA2Ui))}
      </div>
    )
  }

  return (
    <div style={{ display: 'grid', gap: 8, minWidth: 0, maxWidth: '100%' }}>
      {visibleParts.map(part => renderProcessPart(part, source, onOpenA2Ui))}
    </div>
  )
}

function MessageBubble({
  msg,
  agentName,
  onOpenA2Ui,
  onResume,
  resumeDisabled,
}: {
  msg: ChatMessage
  agentName?: string
  onOpenA2Ui: (messages: A2UiMessage[], title: string, source: 'live' | 'history') => void
  onResume: (msg: ChatMessage) => void
  resumeDisabled: boolean
}) {
  const isUser = msg.role === 'user'
  const attachments = parseAttachments(msg.attachmentsJson)
  const a2ui = parseA2UiMessages(msg.a2UiJson)
  const tools = parseJsonArray<Partial<LiveTool>>(msg.toolTraceJson)
  const persistedParts = parseJsonArray<LiveProcessPart>((msg as ChatMessage & { processPartsJson?: string }).processPartsJson)
  const content = displayMessageText(msg.content)
  const hasServerMessageId = msg.id > 0
  const copyId = msg.requestId || (hasServerMessageId ? String(msg.id) : '')
  const copyIdLabel = msg.requestId ? 'request_id' : '消息ID'
  const processParts: LiveProcessPart[] = persistedParts.length > 0 ? persistedParts : [
    ...(content.trim() ? [{ id: `message-${msg.id}-text`, type: 'text' as const, content }] : []),
    ...tools.map((tool, index) => ({
      id: `message-${msg.id}-tool-${tool.id || tool.name || index}`,
      type: 'tool' as const,
      tool: {
        id: String(tool.id || tool.name || `tool-${index + 1}`),
        name: String(tool.name || tool.id || `tool-${index + 1}`),
        args: normalizeTraceText((tool as any).args),
        result: normalizeTraceText((tool as any).result),
        status: tool.status || 'done',
      },
    })),
    ...(a2ui.length > 0 ? [{ id: `message-${msg.id}-a2ui`, type: 'a2ui' as const, messages: a2ui }] : []),
  ]
  const isFailedTurn = !isUser && (
    /^服务响应失败[：:]/.test(content.trim())
    || processParts.some(part => part.type === 'error')
  )

  return (
    <div style={{ display: 'flex', justifyContent: isUser ? 'flex-end' : 'flex-start' }}>
      <div style={{ maxWidth: 'min(1040px, 96%)', minWidth: 0 }}>
        <div style={{ marginBottom: 4, fontSize: 12, color: '#8c8c8c', textAlign: isUser ? 'right' : 'left', display: 'flex', justifyContent: isUser ? 'flex-end' : 'flex-start', alignItems: 'center', gap: 4 }}>
          <span>{isUser ? (msg.senderName || '用户') : (msg.senderName || agentName || '智能体')} · {parseServerTime(msg.createdAt)}</span>
          {copyId ? (
            <Button
              type="text"
              size="small"
              icon={<CopyOutlined />}
              onClick={(event) => {
                event.stopPropagation()
                navigator.clipboard?.writeText(copyId)
                message.success(`已复制${copyIdLabel}`)
              }}
              style={{ width: 18, height: 18, minWidth: 18, padding: 0, color: '#999' }}
            />
          ) : (
            <Tooltip title="发送中，暂无后端消息ID">
              <CopyOutlined style={{ fontSize: 12, color: '#c9c9c9' }} />
            </Tooltip>
          )}
        </div>
        {isUser && content.trim() && (
          <div style={{ border: '1px solid #e8e8e8', background: isUser ? '#e6f4ff' : '#fff', borderRadius: 10, padding: '10px 12px', overflowWrap: 'anywhere', wordBreak: 'break-word', minWidth: 0, maxWidth: '100%' }}>
            <MarkdownText text={content} />
          </div>
        )}
        {!isUser && <ProcessStack parts={processParts} onOpenA2Ui={onOpenA2Ui} source="history" compact />}
        {isFailedTurn && (
          <div style={{ marginTop: 8 }}>
            <Button size="small" type="primary" ghost disabled={resumeDisabled} onClick={() => onResume(msg)}>
              断点续跑
            </Button>
          </div>
        )}
        {attachments.length > 0 && <AttachmentList attachments={attachments} />}
      </div>
    </div>
  )
}

function AttachmentList({ attachments }: { attachments: ChatAttachment[] }) {
  return (
    <div style={{ display: 'grid', gap: 6, marginTop: 8 }}>
      {attachments.map((attachment, index) => {
        const href = attachment.dataUrl || attachment.url || ''
        const name = attachment.name || `附件 ${index + 1}`
        const isImage = href && (attachment.mediaType || '').startsWith('image/')
        return (
          <div key={`${name}-${index}`} style={{ border: '1px solid #e8eef7', borderRadius: 8, background: '#fbfdff', padding: 8 }}>
            {isImage && <img src={href} alt={name} style={{ maxWidth: 220, maxHeight: 160, objectFit: 'contain', display: 'block', marginBottom: 6, borderRadius: 6 }} />}
            <div style={{ display: 'flex', alignItems: 'center', gap: 8, justifyContent: 'space-between' }}>
              <span style={{ minWidth: 0, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{name}</span>
              {href && <a href={href} target="_blank" rel="noreferrer" download={name}>打开</a>}
            </div>
          </div>
        )
      })}
    </div>
  )
}

function LiveResponse({ live, onOpenA2Ui }: { live: LiveState; onOpenA2Ui: (messages: A2UiMessage[], title: string, source: 'live' | 'history') => void }) {
  if (!live.running && !live.text && !live.thinking && live.tools.length === 0 && live.a2ui.length === 0 && live.parts.length === 0 && !live.error) return null
  const fallbackParts: LiveProcessPart[] = [
    ...(live.error ? [{ id: 'live-error', type: 'error' as const, message: live.error }] : []),
    ...(live.text ? [{ id: 'live-text', type: 'text' as const, content: live.text }] : []),
    ...(live.thinking ? [{ id: 'live-thinking', type: 'thinking' as const, content: live.thinking, status: live.running ? 'running' as const : 'done' as const }] : []),
    ...live.tools.map(tool => ({ id: `live-tool-${tool.id}`, type: 'tool' as const, tool })),
    ...(live.a2ui.length > 0 ? [{ id: 'live-a2ui', type: 'a2ui' as const, messages: live.a2ui }] : []),
  ]
  const processParts = live.parts.length > 0 ? live.parts : fallbackParts

  return (
    <div style={{ display: 'flex', justifyContent: 'flex-start' }}>
      <div style={{ maxWidth: 'min(1040px, 96%)', minWidth: 0 }}>
        <div style={{ marginBottom: 4, fontSize: 12, color: '#8c8c8c' }}>智能体</div>
        {processParts.length > 0
          ? <ProcessStack parts={processParts} onOpenA2Ui={onOpenA2Ui} source="live" compact={!live.running} />
          : live.running
            ? <div style={{ border: '1px solid #e8e8e8', background: '#fff', borderRadius: 10, padding: '10px 12px' }}><Text type="secondary"><Spin size="small" /> 正在响应...</Text></div>
            : null}
      </div>
    </div>
  )
}

export default function CleanChatView({ sessionId, agentId, agentName, agentType, agentStatus, studioAgentName, onSessionUpdated }: CleanChatViewProps) {
  const initialLive = readLiveSnapshot(sessionId) || emptyLive()
  const [session, setSession] = useState<SessionType | null>(null)
  const [messagesData, setMessagesData] = useState<ChatMessage[]>([])
  const [input, setInput] = useState('')
  const [attachments, setAttachments] = useState<ChatAttachment[]>([])
  const [enableThinking, setEnableThinking] = useState(false)
  const [codexMessageMode, setCodexMessageMode] = useState<CodexMessageMode>('queue')
  const [queuedMessages, setQueuedMessages] = useState<QueuedMessage[]>(() => readQueueSnapshot(sessionId))
  const [queueCollapsed, setQueueCollapsed] = useState(() => queueCollapsedStore.get(sessionId) || false)
  const [loading, setLoading] = useState(false)
  const [loadingMore, setLoadingMore] = useState(false)
  const [hasMoreHistory, setHasMoreHistory] = useState(false)
  const [timelineEvents, setTimelineEvents] = useState<GatewayConversationEvent[]>([])
  const [sending, setSending] = useState(initialLive.running)
  const [live, setLive] = useState<LiveState>(() => initialLive)
  const [a2uiModal, setA2UiModal] = useState<A2UiModalState>({ open: false, messages: [], title: '交互操作', source: 'history' })
  const [isMobile, setIsMobile] = useState(() => window.innerWidth <= 768)
  const scrollRef = useRef<HTMLDivElement | null>(null)
  const inputRef = useRef<any>(null)
  const abortRef = useRef<() => void>(() => {})
  const speechRecognitionRef = useRef<any>(null)
  const speechInputBaseRef = useRef('')
  const composingRef = useRef(false)
  const shouldStickRef = useRef(true)
  const previousLiveA2UiCountRef = useRef(0)
  const liveRef = useRef<LiveState>(emptyLive())
  const currentAgentId = session?.agentId ?? agentId
  const currentAgentName = session?.agentName || agentName
  const currentStudioAgentName = session?.studioAgentName || studioAgentName
  const currentAgentStatus = session?.agentStatus || agentStatus
  const isAgentActive = !currentAgentStatus || currentAgentStatus === 'Active'
  const isCodexAgent = String(agentType || '').toLowerCase() === 'codex'
  const supportsRuntimeSteer = ['codex', 'goldfish', 'openclaw'].includes(String(agentType || '').toLowerCase())
  const [isListening, setIsListening] = useState(false)

  const updateLive = useCallback((updater: LiveState | ((prev: LiveState) => LiveState)) => {
    setLive(prev => {
      const next = typeof updater === 'function'
        ? (updater as (prev: LiveState) => LiveState)(prev)
        : updater
      liveRef.current = next
      publishLiveSnapshot(sessionId, next)
      return next
    })
  }, [sessionId])

  const updateQueuedMessages = useCallback((updater: (items: QueuedMessage[]) => QueuedMessage[]) => {
    const next = publishQueueSnapshot(sessionId, updater)
    setQueuedMessages(next)
  }, [sessionId])

  useEffect(() => {
    const restored = readLiveSnapshot(sessionId)
    if (restored) {
      liveRef.current = restored
      setLive(restored)
      setSending(restored.running)
    }
    return subscribeLiveSnapshot(sessionId, next => {
      liveRef.current = next
      setLive(next)
      setSending(next.running || activeStreamCount(sessionId) > 0)
    })
  }, [sessionId])

  useEffect(() => {
    setQueuedMessages(readQueueSnapshot(sessionId))
    setQueueCollapsed(queueCollapsedStore.get(sessionId) || false)
    setSending((readLiveSnapshot(sessionId)?.running || false) || activeStreamCount(sessionId) > 0)
    return subscribeQueueSnapshot(sessionId, setQueuedMessages)
  }, [sessionId])

  const toggleQueueCollapsed = () => {
    setQueueCollapsed(prev => {
      const next = !prev
      queueCollapsedStore.set(sessionId, next)
      return next
    })
  }

  const guideQueuedMessage = (item: QueuedMessage) => {
    setCodexMessageMode('steer')
    setInput(item.content)
    requestAnimationFrame(() => inputRef.current?.focus?.())
  }

  useEffect(() => {
    const onResize = () => setIsMobile(window.innerWidth <= 768)
    window.addEventListener('resize', onResize)
    return () => window.removeEventListener('resize', onResize)
  }, [])

  useEffect(() => () => {
    speechRecognitionRef.current?.stop?.()
    speechRecognitionRef.current = null
  }, [])

  const toggleSpeechInput = () => {
    if (isListening) {
      speechRecognitionRef.current?.stop?.()
      return
    }

    const SpeechRecognition = (window as any).SpeechRecognition || (window as any).webkitSpeechRecognition
    if (!SpeechRecognition) {
      message.warning('当前浏览器不支持语音识别，请使用最新版 Chrome 或 Edge。')
      return
    }

    const recognition = new SpeechRecognition()
    recognition.lang = 'zh-CN'
    recognition.continuous = false
    recognition.interimResults = true
    speechInputBaseRef.current = input
    recognition.onstart = () => setIsListening(true)
    recognition.onresult = (event: any) => {
      let transcript = ''
      for (let index = 0; index < event.results.length; index += 1) {
        transcript += event.results[index][0]?.transcript || ''
      }
      setInput(`${speechInputBaseRef.current}${transcript}`)
    }
    recognition.onerror = (event: any) => {
      if (event.error !== 'aborted' && event.error !== 'no-speech') {
        message.warning(`语音识别失败：${event.error || '未知错误'}`)
      }
      setIsListening(false)
    }
    recognition.onend = () => {
      setIsListening(false)
      speechRecognitionRef.current = null
    }
    speechRecognitionRef.current = recognition
    try {
      recognition.start()
    } catch (error: any) {
      speechRecognitionRef.current = null
      setIsListening(false)
      message.warning(`无法启动语音识别：${error?.message || '请检查麦克风权限'}`)
    }
  }

  const stickToBottom = useCallback((force = false) => {
    const element = scrollRef.current
    if (!element) return
    if (force || shouldStickRef.current || isNearBottom(element)) {
      requestAnimationFrame(() => {
        element.scrollTop = element.scrollHeight
      })
    }
  }, [])

  const load = useCallback(async () => {
    setLoading(true)
    try {
      const [messagesRes, sessionRes, timelineRes] = await Promise.all([
        getMessages(sessionId, { take: 10 }),
        getSession(sessionId),
        getSessionTimeline(sessionId, { includePayload: true, take: 1000 }),
      ])
      const nextMessages = messagesRes.data || []
      const nextTimeline = timelineRes.data || []
      setTimelineEvents(nextTimeline)
      setMessagesData(attachTimelineParts(nextMessages, nextTimeline))
      setHasMoreHistory(nextMessages.length >= 10)
      setSession(sessionRes.data)
      const restored = readLiveSnapshot(sessionId)
      updateLive(restored || emptyLive())
      shouldStickRef.current = true
      stickToBottom(true)
    } catch (err: any) {
      message.error(err.response?.data?.message || err.message || '加载会话失败')
    } finally {
      setLoading(false)
    }
  }, [sessionId, stickToBottom])

  const loadMoreHistory = useCallback(async () => {
    if (loadingMore || messagesData.length === 0) return
    const oldestPersistedId = Math.min(...messagesData.filter(item => item.id > 0).map(item => item.id))
    if (!Number.isFinite(oldestPersistedId)) return
    const element = scrollRef.current
    const previousHeight = element?.scrollHeight || 0
    setLoadingMore(true)
    try {
      const res = await getMessages(sessionId, { take: 10, beforeId: oldestPersistedId })
      const older = res.data || []
      setHasMoreHistory(older.length >= 10)
      setMessagesData(prev => {
        const seen = new Set(prev.map(item => item.id))
        return [...attachTimelineParts(older.filter(item => !seen.has(item.id)), timelineEvents), ...prev]
      })
      requestAnimationFrame(() => {
        if (element) element.scrollTop = element.scrollHeight - previousHeight
      })
    } catch (err: any) {
      message.error(err.response?.data?.message || err.message || '加载更早消息失败')
    } finally {
      setLoadingMore(false)
    }
  }, [loadingMore, messagesData, sessionId, timelineEvents])

  useEffect(() => {
    load()
  }, [load])

  useEffect(() => {
    stickToBottom()
  }, [messagesData, live, stickToBottom])

  useEffect(() => {
    liveRef.current = live
  }, [live])

  useEffect(() => {
    const previousCount = previousLiveA2UiCountRef.current
    previousLiveA2UiCountRef.current = live.a2ui.length
    if (live.a2ui.length === 0) return
    const title = summarizeA2UiRequest(live.a2ui)
    if (previousCount === 0) {
      setA2UiModal({ open: true, messages: live.a2ui, title, source: 'live' })
      return
    }
    setA2UiModal(prev => prev.open && prev.source === 'live' ? { ...prev, messages: live.a2ui, title } : prev)
  }, [live.a2ui])

  const onScroll = () => {
    shouldStickRef.current = isNearBottom(scrollRef.current)
  }

  const openA2UiModal = useCallback((messages: A2UiMessage[], title: string, source: 'live' | 'history') => {
    setA2UiModal({ open: true, messages, title, source })
  }, [])

  const handleA2UiAction = useCallback(async (action: A2UiAction) => {
    if ((action as any).type === 'open_url') {
      window.open((action as any).url, '_blank', 'noopener,noreferrer')
      return
    }
    if ((action as any).type === 'send_message') {
      setA2UiModal(prev => ({ ...prev, open: false }))
      await send(String((action as any).text || ''))
      return
    }
    const context = ((action as any).context || {}) as Record<string, unknown>
    const delivery = findInteractionDelivery(a2uiModal.messages)
    const interactionId = String(context.interactionId || context.interaction_id || delivery?.interactionId || '')
    const actionToken = String(context.actionToken || context.action_token || delivery?.actionToken || '')
    if (interactionId && actionToken) {
      const choice = String(context.choice || '').toLowerCase()
      const value = context.value ?? (action as any).dataModel?.value
      const label = String(context.label || value || '')
      const interactionAction = choice === 'no' || choice === 'decline'
        ? 'Decline'
        : choice === 'yes' || choice === 'accept'
          ? 'Accept'
          : (action as any).name === 'cancel'
            ? 'Cancel'
            : 'Submit'
      setA2UiModal(prev => ({ ...prev, open: false }))
      const result = await respondInteraction({
        interactionId,
        actionToken,
        action: interactionAction,
        value: value == null ? undefined : String(value),
        label: label || undefined,
        data: (action as any).dataModel,
        channel: 'webapp',
        idempotencyKey: globalThis.crypto?.randomUUID?.() || `${interactionId}-${Date.now()}`,
      })
      message.success(result.data.message)
      return
    }
    setA2UiModal(prev => ({ ...prev, open: false }))
    const payload = {
      protocol: 'a2ui',
      action,
      sessionId,
      agentId: currentAgentId,
      timestamp: new Date().toISOString(),
    }
    await send(`[A2UI_ACTION]\n${JSON.stringify(payload, null, 2)}`)
  }, [a2uiModal.messages, sessionId, currentAgentId])

  const applyAgUiEvent = (event: any) => {
    const type = String(event?.type || '')
    if (type === 'RUN_STARTED') {
      updateLive(prev => ({ ...prev, running: true, error: '' }))
      return
    }
    if (type === 'SKILL_CONTEXT') {
      const skills = skillsFromPayload(event)
      updateLive(prev => ({ ...prev, running: true, parts: upsertSkillPart(prev.parts, skills) }))
      return
    }
    if (type === 'RUN_FINISHED') {
      updateLive(prev => ({ ...prev, running: false, parts: finishThinkingParts(prev.parts) }))
      return
    }
    if (type === 'RUN_ERROR') {
      const error = readDelta(event) || '服务响应失败'
      updateLive(prev => ({ ...prev, running: false, error, parts: appendErrorPart(finishThinkingParts(prev.parts), error) }))
      return
    }
    if (type === 'REASONING_MESSAGE_END' || type === 'THINKING_TEXT_MESSAGE_END') {
      updateLive(prev => ({ ...prev, parts: finishThinkingParts(prev.parts) }))
      return
    }
    if (type === 'TEXT_MESSAGE_START') {
      updateLive(prev => ({ ...prev, parts: finishThinkingParts(prev.parts) }))
      return
    }
    if (type === 'TEXT_MESSAGE_CONTENT') {
      const delta = readDelta(event)
      if (delta) updateLive(prev => ({ ...prev, text: prev.text + delta, parts: appendTextPart(finishThinkingParts(prev.parts), delta) }))
      return
    }
    if (type === 'REASONING_MESSAGE_CONTENT' || type === 'THINKING_TEXT_MESSAGE_CONTENT') {
      const delta = readDelta(event)
      if (delta) updateLive(prev => ({ ...prev, thinking: prev.thinking + delta, parts: appendThinkingPart(prev.parts, delta) }))
      return
    }
    if (type === 'TOOL_CALL_START') {
      const id = String(event?.toolCallId || event?.toolCallName || event?.toolName || `tool-${Date.now()}`)
      updateLive(prev => {
        const tools = appendTool(prev.tools, { id, name: String(event?.toolCallName || event?.toolName || id), status: 'running' })
        const tool = tools.find(item => item.id === id)!
        return { ...prev, tools, parts: upsertToolPart(prev.parts, tool) }
      })
      return
    }
    if (type === 'TOOL_CALL_ARGS' || type === 'TOOL_CALL_CHUNK') {
      const id = String(event?.toolCallId || event?.toolCallName || 'tool')
      const delta = readDelta(event)
      updateLive(prev => {
        const tools = appendTool(prev.tools, { id, args: delta })
        const tool = tools.find(item => item.id === id)!
        return { ...prev, tools, parts: upsertToolPart(prev.parts, tool) }
      })
      return
    }
    if (type === 'TOOL_CALL_RESULT' || type === 'TOOL_CALL_END') {
      const id = String(event?.toolCallId || event?.toolCallName || 'tool')
      const result = readDelta(event)
      updateLive(prev => {
        const tools = appendTool(prev.tools, { id, result, status: 'done' })
        const tool = tools.find(item => item.id === id)!
        return { ...prev, tools, parts: upsertToolPart(prev.parts, tool) }
      })
    }
  }

  const markQueuedMessage = (id: string | null, status: QueuedMessage['status']) => {
    if (!id) return
    updateQueuedMessages(prev => prev.map(item => item.id === id ? { ...item, status } : item))
  }

  const removeQueuedMessage = (id: string | null) => {
    if (!id) return
    updateQueuedMessages(prev => prev.filter(item => item.id !== id))
  }

  const consumeStream = async (reader: ReadableStreamDefaultReader<Uint8Array>, queueItemId?: string | null, optimisticUserMessageId?: number) => {
    const decoder = new TextDecoder()
    let buffer = ''
    const persisted: { turnId?: string; requestId?: string; userMessageId?: number; assistantMessageId?: number } = {}
    const patchOptimisticUserMessage = (userMessageId?: number, requestId?: string) => {
      if (!optimisticUserMessageId || (!userMessageId && !requestId)) return
      setMessagesData(prev => prev.map(item => (
        item.id === optimisticUserMessageId || (userMessageId && item.id === userMessageId)
          ? {
            ...item,
            id: userMessageId && item.id === optimisticUserMessageId ? userMessageId : item.id,
            requestId: requestId || item.requestId,
          }
          : item
      )))
    }
    while (true) {
      const { value, done } = await reader.read()
      if (done) break
      buffer += decoder.decode(value, { stream: true })
      const frames = buffer.split('\n\n')
      buffer = frames.pop() || ''
      for (const frame of frames) {
        const dataLines = frame.split('\n').filter(line => line.trim().startsWith('data:'))
        if (dataLines.length === 0) continue
        const raw = dataLines.map(line => line.replace(/^data:\s?/, '')).join('\n').trim()
        if (!raw || raw === '[DONE]') continue
        try {
          const data = JSON.parse(raw)
          const agui = parseAgUiEnvelope(data)
          if (agui) {
            if (String(agui?.type || '') === 'RUN_STARTED') markQueuedMessage(queueItemId || null, 'running')
            applyAgUiEvent(agui)
            continue
          }
          const a2ui = parseA2UiEnvelope(data)
          if (a2ui) {
            const message = a2ui as A2UiMessage
            updateLive(prev => ({ ...prev, a2ui: [...prev.a2ui, message], parts: appendA2UiPart(prev.parts, [message]) }))
            continue
          }
          if (data.type === 'stream.error') {
            const error = data.payload?.message || '服务响应失败'
            markQueuedMessage(queueItemId || null, 'error')
            updateLive(prev => ({ ...prev, running: false, error, parts: appendErrorPart(finishThinkingParts(prev.parts), error) }))
          }
          if (data.type === 'stream.start') {
            if (data.payload?.turnId) persisted.turnId = String(data.payload.turnId)
            if (data.payload?.requestId) persisted.requestId = String(data.payload.requestId)
            if (Number(data.payload?.userMessageId) > 0) persisted.userMessageId = Number(data.payload.userMessageId)
            patchOptimisticUserMessage(persisted.userMessageId, persisted.requestId)
          }
          if (data.type === 'stream.persisted') {
            if (data.payload?.turnId) persisted.turnId = String(data.payload.turnId)
            if (data.payload?.requestId) persisted.requestId = String(data.payload.requestId)
            if (Number(data.payload?.userMessageId) > 0) persisted.userMessageId = Number(data.payload.userMessageId)
            if (Number(data.payload?.assistantMessageId) > 0) persisted.assistantMessageId = Number(data.payload.assistantMessageId)
            patchOptimisticUserMessage(persisted.userMessageId, persisted.requestId)
          }
          if (data.type === 'stream.runtime_queue') {
            const payload = data.payload || {}
            if (!payload.sessionId || String(payload.sessionId) === sessionId) {
              const runtimeItems = readRuntimeQueueItems(payload)
              if (runtimeItems) updateQueuedMessages(() => runtimeItems)
            }
          }
          if (data.type === 'stream.runtime_session') {
            const payload = data.payload || {}
            if (!payload.sessionId || String(payload.sessionId) === sessionId) {
              const title = String(payload.displayTitle || payload.title || '').trim()
              const reason = String(payload.reason || '').trim()
              const notice = title
                ? (reason === 'selected' ? `已切换会话：${title}` : reason === 'created' ? `会话已创建：${title}` : `会话已命名：${title}`)
                : 'runtime 会话状态已更新'
              updateLive(prev => ({ ...prev, running: true, parts: appendTextPart(finishThinkingParts(prev.parts), `${notice}\n`) }))
              onSessionUpdated?.()
            }
          }
          if (data.type === 'stream.done') {
            if (data.payload?.requestId) persisted.requestId = String(data.payload.requestId)
            if (Number(data.payload?.userMessageId) > 0) persisted.userMessageId = Number(data.payload.userMessageId)
            if (Number(data.payload?.assistantMessageId) > 0) persisted.assistantMessageId = Number(data.payload.assistantMessageId)
            patchOptimisticUserMessage(persisted.userMessageId, persisted.requestId)
            removeQueuedMessage(queueItemId || null)
            updateLive(prev => ({ ...prev, running: false, parts: finishThinkingParts(prev.parts) }))
          }
          if (data.type === 'stream.delta') {
            const kind = String(data.payload?.metadata?.kind || '')
            const channel = String(data.payload?.channel || 'content')
            const delta = decodeDisplayText(String(data.payload?.delta || ''))
            if (kind && kind !== 'agent_queue_notice') markQueuedMessage(queueItemId || null, kind === 'agent_queue_cancelled' ? 'error' : 'running')
            if (!kind && delta) markQueuedMessage(queueItemId || null, 'running')
            if (delta) {
              updateLive(prev => {
                if (channel === 'thinking') {
                  return { ...prev, running: true, thinking: prev.thinking + delta, parts: appendThinkingPart(prev.parts, delta) }
                }
                if (channel === 'tool') {
                  return { ...prev, running: true, parts: appendTextPart(prev.parts, delta) }
                }
                return { ...prev, running: true, text: prev.text + delta, parts: appendTextPart(finishThinkingParts(prev.parts), delta) }
              })
            }
          }
        } catch {
          // Ignore malformed compatibility frames.
        }
      }
    }
    return persisted
  }

  const readFileAsDataUrl = (file: File) => new Promise<string>((resolve, reject) => {
    const reader = new FileReader()
    reader.onload = () => resolve(String(reader.result || ''))
    reader.onerror = () => reject(reader.error || new Error('读取文件失败'))
    reader.readAsDataURL(file)
  })

  const beforeUpload = async (file: File) => {
    const dataUrl = await readFileAsDataUrl(file)
    setAttachments(prev => [...prev, {
      type: file.type.startsWith('image/') ? 'image' : 'file',
      name: file.name,
      mediaType: file.type || 'application/octet-stream',
      size: file.size,
      dataUrl,
    }])
    return false
  }

  const send = async (override?: string, attachmentOverride?: ChatAttachment[]) => {
    const content = (override ?? input).trim()
    const effectiveAttachments = attachmentOverride ?? attachments
    if (!content && effectiveAttachments.length === 0) return
    if (!isAgentActive) {
      message.warning('当前智能体未启用')
      return
    }

    const shouldTrackQueue = activeStreamCount(sessionId) > 0
    const queueItemId = shouldTrackQueue ? `queue-${Date.now()}-${Math.random().toString(36).slice(2, 8)}` : null
    const optimistic: ChatMessage = {
      id: -Date.now(),
      sessionId,
      role: 'user',
      content,
      attachmentsJson: JSON.stringify(effectiveAttachments),
      createdAt: new Date().toISOString(),
    }
    const outboundAttachments = effectiveAttachments
    setMessagesData(prev => [...prev, optimistic])
    if (queueItemId) {
      updateQueuedMessages(prev => [...prev, {
        id: queueItemId,
        content,
        mode: codexMessageMode,
        status: 'queued',
        createdAt: new Date().toISOString(),
      }])
    }
    setInput('')
    if (attachmentOverride === undefined) setAttachments([])
    updateLive({ ...emptyLive(), running: true })
    previousLiveA2UiCountRef.current = 0
    changeActiveStreamCount(sessionId, 1)
    setSending(true)
    shouldStickRef.current = true
    stickToBottom(true)

    try {
      const { reader, abort } = await streamChat({
        sessionId,
        content,
        agentId: currentAgentId,
        attachments: outboundAttachments,
        enableThinking: enableThinking ? true : undefined,
        messageMode: supportsRuntimeSteer ? codexMessageMode : undefined,
      })
      abortRef.current = abort
      setLiveAborter(sessionId, abort)
      const persisted = await consumeStream(reader, queueItemId, optimistic.id)
      const finalLive = liveRef.current
      const hasAssistantContent = finalLive.text.trim()
        || finalLive.thinking.trim()
        || finalLive.tools.length > 0
        || finalLive.a2ui.length > 0
        || finalLive.error.trim()
      if (hasAssistantContent) {
        try {
          const ids = [persisted.userMessageId, persisted.assistantMessageId].filter((id): id is number => Number(id) > 0)
          if (ids.length === 0) throw new Error('no persisted message ids')
          const [messagesRes, timelineRes] = await Promise.all([
            getMessages(sessionId, { ids: ids.join(',') }),
            persisted.turnId
              ? getSessionTimeline(sessionId, { turnId: persisted.turnId, includePayload: true, take: 1000 })
              : Promise.resolve({ data: [] as GatewayConversationEvent[] }),
          ])
          const nextTimeline = timelineRes.data || []
          setTimelineEvents(prev => {
            const seen = new Set(prev.map(item => item.id))
            return [...prev, ...nextTimeline.filter(item => !seen.has(item.id))]
          })
          const persistedMessages = attachTimelineParts(messagesRes.data || [], nextTimeline)
          setMessagesData(prev => {
            const withoutOptimistic = persisted.userMessageId
              ? prev.filter(item => item.id !== optimistic.id)
              : prev
            const byId = new Map(withoutOptimistic.map(item => [item.id, item]))
            for (const item of persistedMessages) byId.set(item.id, item)
            return Array.from(byId.values()).sort((a, b) => {
              const ai = a.id > 0 ? a.id : Number.MAX_SAFE_INTEGER
              const bi = b.id > 0 ? b.id : Number.MAX_SAFE_INTEGER
              if (ai !== bi) return ai - bi
              return new Date(a.createdAt).getTime() - new Date(b.createdAt).getTime()
            })
          })
        } catch {
          const assistantMessage: ChatMessage = {
            id: -Date.now() - 1,
            sessionId,
            role: 'assistant',
            senderName: currentAgentName || '智能体',
            content: finalLive.error ? `服务响应失败：${finalLive.error}` : finalLive.text,
            processPartsJson: finalLive.parts.length ? JSON.stringify(finalLive.parts) : undefined,
            toolTraceJson: finalLive.parts.length ? undefined : finalLive.tools.length ? JSON.stringify(finalLive.tools) : undefined,
            a2UiJson: finalLive.a2ui.length ? JSON.stringify(finalLive.a2ui) : undefined,
            createdAt: new Date().toISOString(),
          }
          setMessagesData(prev => [...prev, assistantMessage])
        }
      }
      updateLive(emptyLive())
    } catch (err: any) {
      markQueuedMessage(queueItemId, 'error')
      updateLive(prev => ({ ...prev, running: false, error: err.message || '发送失败' }))
    } finally {
      removeQueuedMessage(queueItemId)
      const remainingStreams = changeActiveStreamCount(sessionId, -1)
      if (remainingStreams === 0 && !liveRef.current.running) liveAborters.delete(sessionId)
      setSending(remainingStreams > 0)
    }
  }

  const resumeFromFailure = async (failedMessage: ChatMessage) => {
    if (sending) return
    const checkpoint = failedMessage.requestId || (failedMessage.id > 0 ? `message-${failedMessage.id}` : 'latest-failed-turn')
    await send(`请从上一次失败或中断的位置继续执行（断点：${checkpoint}）。先检查当前会话中已经完成的步骤、工具调用及其结果，不要重复已成功完成或可能产生副作用的操作；从尚未完成的步骤继续，并最终给出完整结果。`, [])
  }

  const stop = () => {
    abortRef.current?.()
    abortLiveStream(sessionId)
    activeStreamCounts.delete(sessionId)
    updateQueuedMessages(() => [])
    setSending(false)
    updateLive(prev => ({ ...prev, running: false }))
  }

  const handleCommand = async (command: string) => {
    if (command === '/reset') {
      await resetSessionContext(sessionId)
      message.success('上下文已重置')
      setInput('')
      return
    }
    setInput(command)
  }

  const commandLabel = (title: string, command: string, desc: string) => (
    <div style={{ display: 'grid', gap: 2, padding: '2px 0' }}>
      <span style={{ display: 'flex', alignItems: 'center', gap: 8, minWidth: 0 }}>
        <Text strong style={{ fontSize: 13 }}>{title}</Text>
        <Text code style={{ marginLeft: 'auto', fontSize: 12 }}>{command.trim()}</Text>
      </span>
      <Text type="secondary" style={{ fontSize: 12, lineHeight: 1.35, whiteSpace: 'normal' }}>{desc}</Text>
    </div>
  )

  const commandMenuItems = [
    {
      type: 'group' as const,
      label: '本地对话',
      children: [
        { key: '/reset', label: commandLabel('重置上下文', '/reset', '清空当前 Web 会话上下文') },
        { key: '/help', label: commandLabel('查看帮助', '/help', '查看当前通道支持的命令') },
      ],
    },
    { type: 'divider' as const },
    {
      type: 'group' as const,
      label: '智能体与资源',
      children: [
        { key: '/agent list', label: commandLabel('实例列表', '/agent list', '查看当前可用的 Agent 实例') },
        { key: '/agent current', label: commandLabel('当前实例', '/agent current', '查看当前路由命中的 Agent 实例') },
        { key: '/agent use ', label: commandLabel('切换实例', '/agent use', '填入实例 ID 或名称后切换') },
        { key: '/bot list', label: commandLabel('Bot 列表', '/bot list', '查看已有 Bot 实例') },
        { key: '/project list', label: commandLabel('项目列表', '/project list', '查看可用于创建实例的项目目录') },
        { key: '/binding current', label: commandLabel('当前绑定', '/binding current', '查看当前对话的路由绑定') },
      ],
    },
    { type: 'divider' as const },
    {
      type: 'group' as const,
      label: '远程会话',
      children: [
        { key: '/session list', label: commandLabel('会话列表', '/session list', '列出远程执行会话') },
        { key: '/session list conversations', label: commandLabel('对话会话', '/session list conversations', '只看对话类远程会话') },
        { key: '/session current', label: commandLabel('当前会话', '/session current', '查看当前绑定的远程会话') },
        { key: '/session use ', label: commandLabel('切换会话', '/session use', '填入会话 ID 后切换') },
        { key: '/session clear', label: commandLabel('清除绑定', '/session clear', '清除当前远程会话绑定') },
      ],
    },
    { type: 'divider' as const },
    {
      type: 'group' as const,
      label: '执行控制',
      children: [
        { key: '/new', label: commandLabel('新建会话', '/new', '开启一个新的执行会话') },
        { key: '/stop', label: commandLabel('停止执行', '/stop', '停止当前正在运行的任务') },
        { key: '/queue', label: commandLabel('执行队列', '/queue', '查看或设置当前会话的队列模式') },
        { key: '补充 ', label: commandLabel('补充引导', '补充', '补充、修正或继续引导当前任务') },
        { key: '/chat rename ', label: commandLabel('命名对话', '/chat rename', '填入名称后修改当前对话名称') },
      ],
    },
    { type: 'divider' as const },
    {
      type: 'group' as const,
      label: '网关管理',
      children: [
        { key: '/gateway status', label: commandLabel('网关状态', '/gateway status', '查看网关、节点、路由和 Bot 状态') },
        { key: '/gateway restart', label: commandLabel('重启网关', '/gateway restart', '重启当前通道对应的网关连接') },
      ],
    },
  ]

  const composerHeight = isMobile ? 120 : 128

  return (
    <div style={{ height: '100%', minHeight: 0, display: 'flex', flexDirection: 'column', background: '#f7f8fa', position: 'relative' }}>
      <div
        ref={scrollRef}
        onScroll={onScroll}
        style={{ flex: '1 1 0', minHeight: 0, overflowY: 'auto', padding: isMobile ? '10px 8px' : '18px 12px' }}
      >
        {loading ? (
          <div style={{ height: '100%', display: 'grid', placeItems: 'center' }}><Spin /></div>
        ) : (
          <div style={{ maxWidth: 1180, margin: '0 auto', display: 'grid', gap: 14 }}>
            {hasMoreHistory && (
              <div style={{ display: 'flex', justifyContent: 'center' }}>
                <Button size="small" loading={loadingMore} onClick={loadMoreHistory}>加载更早消息</Button>
              </div>
            )}
            {currentAgentStatus && currentAgentStatus !== 'Active' && <Alert type="warning" showIcon message="当前智能体未启用，暂不能发送消息" />}
            {messagesData.map(msg => (
              <MessageBubble
                key={msg.id}
                msg={msg}
                agentName={currentAgentName}
                onOpenA2Ui={openA2UiModal}
                onResume={resumeFromFailure}
                resumeDisabled={sending || !isAgentActive}
              />
            ))}
            <LiveResponse live={live} onOpenA2Ui={openA2UiModal} />
          </div>
        )}
      </div>

      <div style={{ position: 'absolute', left: 0, right: 0, bottom: composerHeight + 10, zIndex: 6 }}>
        <QueuePanel items={queuedMessages} collapsed={queueCollapsed} onToggle={toggleQueueCollapsed} onGuide={guideQueuedMessage} />
      </div>

      <div style={{ flex: `0 0 ${composerHeight}px`, height: composerHeight, borderTop: '1px solid #e8e8e8', background: '#fff', padding: isMobile ? 8 : 12 }}>
        <div style={{ maxWidth: 1180, margin: '0 auto', height: '100%', display: 'grid', gridTemplateRows: '1fr 34px', gap: 8 }}>
          <TextArea
            ref={inputRef}
            value={input}
            placeholder="输入消息，Enter 发送，Shift+Enter 换行"
            onChange={event => setInput(event.target.value)}
            onCompositionStart={() => { composingRef.current = true }}
            onCompositionEnd={() => { composingRef.current = false }}
            onKeyDown={event => {
              if (event.key === 'Enter' && !event.shiftKey && !event.metaKey && !event.ctrlKey && !isImeComposing(event, composingRef.current)) {
                event.preventDefault()
                send()
              }
            }}
            style={{ resize: 'none', height: '100%', minHeight: 0, borderRadius: 8 }}
          />
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 8, minWidth: 0 }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 8, minWidth: 0, overflow: 'hidden' }}>
              <Tooltip title="附件">
                <Upload beforeUpload={beforeUpload} showUploadList={false} multiple>
                  <Button size="small" icon={<PaperClipOutlined />} aria-label="附件" />
                </Upload>
              </Tooltip>
              <Tooltip title="开启后本次消息会携带 think 模式参数">
                <span style={{ display: 'inline-flex', alignItems: 'center', gap: 6, whiteSpace: 'nowrap' }}>
                  <Switch
                    size="small"
                    checked={enableThinking}
                    onChange={setEnableThinking}
                    disabled={false}
                    checkedChildren={<ThunderboltOutlined />}
                    unCheckedChildren={<ThunderboltOutlined />}
                  />
                  {!isMobile && <Text type={enableThinking ? undefined : 'secondary'} style={{ fontSize: 12 }}>Think</Text>}
                </span>
              </Tooltip>
              {supportsRuntimeSteer && (
                <Tooltip title={codexMessageMode === 'queue' ? '当前智能体忙时，本条消息按队列策略处理' : '作为补充/修正引导当前或上一轮任务'}>
                  <span style={{ display: 'inline-flex', alignItems: 'center', gap: 2 }}>
                    <Tooltip title="排队">
                      <Button
                        size="small"
                        type={codexMessageMode === 'queue' ? 'primary' : 'default'}
                        icon={<OrderedListOutlined />}
                        aria-label="排队模式"
                        aria-pressed={codexMessageMode === 'queue'}
                        onClick={() => setCodexMessageMode('queue')}
                      />
                    </Tooltip>
                    <Tooltip title="补充">
                      <Button
                        size="small"
                        type={codexMessageMode === 'steer' ? 'primary' : 'default'}
                        icon={<EditOutlined />}
                        aria-label="补充模式"
                        aria-pressed={codexMessageMode === 'steer'}
                        onClick={() => setCodexMessageMode('steer')}
                      />
                    </Tooltip>
                  </span>
                </Tooltip>
              )}
              <Dropdown
                trigger={['click']}
                placement="topLeft"
                overlayStyle={{ minWidth: isMobile ? 280 : 340, maxWidth: isMobile ? 'calc(100vw - 28px)' : 380 }}
                menu={{
                  items: commandMenuItems,
                  onClick: ({ key }) => handleCommand(String(key)),
                }}
                disabled={false}
              >
                <Button
                  size="small"
                  icon={<><ToolOutlined /><DownOutlined /></>}
                  aria-label="常用命令"
                  style={{
                    borderRadius: 999,
                    borderColor: '#b9d3ff',
                    background: 'linear-gradient(135deg, #f7fbff 0%, #edf5ff 100%)',
                    color: '#2459a8',
                    boxShadow: '0 4px 12px rgba(58, 113, 196, 0.12)',
                  }}
                />
              </Dropdown>
              {attachments.length > 0 && <Text type="secondary" ellipsis style={{ maxWidth: isMobile ? 110 : 260 }}>{attachments.map(item => item.name).join('、')}</Text>}
              {currentStudioAgentName && <Text type="secondary" ellipsis title={`智能体：${currentStudioAgentName}`} style={{ fontSize: 12, maxWidth: isMobile ? 120 : 220 }}>智能体：{currentStudioAgentName}</Text>}
              {agentType && <Text type="secondary" style={{ fontSize: 12 }}>{agentType}</Text>}
            </div>
            <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
              <Tooltip title={isListening ? '停止语音输入' : '语音输入'}>
                <Button
                  size="small"
                  icon={isListening ? <StopOutlined /> : <AudioOutlined />}
                  type={isListening ? 'primary' : 'default'}
                  danger={isListening}
                  aria-label={isListening ? '停止语音输入' : '语音输入'}
                  onClick={toggleSpeechInput}
                  disabled={sending}
                />
              </Tooltip>
              {sending ? (
                <>
                  <Tooltip title={supportsRuntimeSteer && codexMessageMode === 'steer' ? '引导' : '排队'}>
                    <Button
                      type={supportsRuntimeSteer && codexMessageMode === 'steer' ? 'primary' : 'default'}
                      icon={<SendOutlined />}
                      aria-label={supportsRuntimeSteer && codexMessageMode === 'steer' ? '引导' : '排队'}
                      onClick={() => send()}
                      disabled={!input.trim() && attachments.length === 0}
                    />
                  </Tooltip>
                  <Tooltip title="停止">
                    <Button danger icon={<StopOutlined />} aria-label="停止" onClick={stop} />
                  </Tooltip>
                </>
              ) : (
                <Tooltip title="发送">
                  <Button type="primary" icon={<SendOutlined />} aria-label="发送" onClick={() => send()} disabled={!input.trim() && attachments.length === 0} />
                </Tooltip>
              )}
            </div>
          </div>
        </div>
      </div>
      <Modal
        open={a2uiModal.open}
        title={a2uiModal.title}
        footer={null}
        width={isMobile ? 'calc(100vw - 24px)' : 640}
        centered
        destroyOnClose
        onCancel={() => setA2UiModal(prev => ({ ...prev, open: false }))}
      >
        <A2UiRenderer messages={a2uiModal.messages} onAction={handleA2UiAction} />
      </Modal>
    </div>
  )
}
