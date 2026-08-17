import React, { useState, useEffect, useMemo, useRef } from 'react'
import { useNavigate, useLocation } from 'react-router-dom'
import { Layout, Menu, Button, Drawer, Popconfirm, message, theme, Input, Space, Tooltip } from 'antd'
import { PlusOutlined, InboxOutlined, MenuFoldOutlined, EditOutlined, WechatOutlined, WechatWorkOutlined, GlobalOutlined, SendOutlined } from '@ant-design/icons'
import { getSessions, getAgents, getStudioAgents, createSession, updateSession, archiveSession, setAgentFreeWebAppBotId, setAgentFreeWebAppCurrentUser } from './api'
import type { Session, Agent, StudioAgent } from './types'
import CleanChatView from './CleanChatView'
import { readCurrentUser } from '../../auth'

const { Sider, Content } = Layout
const routedGatewayTypes = ['WebApp', 'WeCom', 'Wechat', 'Feishu'] as const
type RoutedGatewayType = typeof routedGatewayTypes[number]
const agentTypeIcons: Record<string, string> = {
  goldfish: '🐠',
  openclaw: '🔗',
  hermes: '🦄',
  codex: '🧠',
  opencode: '⌘',
  claudecode: '🤖',
  kiro: '⚡',
  '大模型直连': '⚡',
}

export const resolveSelectedAgent = (agents: Agent[], selectedAgentId: number | null, currentAgent: Agent | null) =>
  agents.find((agent) => agent.id === selectedAgentId)
  || currentAgent
  || agents.find((agent) => agent.status === 'Active')
  || null

export const resolveEmptySessionAgent = (agents: Agent[], sessions: Session[], routeAgentIds: Set<number>) => {
  if (sessions.length > 0) return null
  return agents.find(agent => agent.status === 'Active' && routeAgentIds.has(agent.id)) || null
}

export const normalizeSessionGatewayType = (session?: Pick<Session, 'gatewayType' | 'id'> | null): RoutedGatewayType => {
  const raw = String(session?.gatewayType || '').trim().toLowerCase()
  if (raw === 'wecom' || raw === '企业微信') return 'WeCom'
  if (raw === 'wechat' || raw === '微信' || raw === 'weixin') return 'Wechat'
  if (raw === 'feishu' || raw === '飞书') return 'Feishu'
  if (raw === 'webapp' || raw === 'webap' || raw === '网页') return 'WebApp'
  return 'WebApp'
}

export const availableSessionGatewayTypes = (sessions: Session[]): RoutedGatewayType[] => {
  const present = new Set<RoutedGatewayType>(['WebApp'])
  sessions.forEach(session => present.add(normalizeSessionGatewayType(session)))
  return routedGatewayTypes.filter(type => present.has(type))
}

export const groupAgentsWithSessions = (
  agents: Agent[],
  sessions: Session[],
  selectedGatewayType: RoutedGatewayType,
  compareAgents: (a: Agent, b: Agent) => number,
) => agents
  .slice()
  .sort(compareAgents)
  .map(agent => ({
    agent,
    sessions: sessions
      .filter(session => session.agentId === agent.id && normalizeSessionGatewayType(session) === selectedGatewayType)
      .sort(
        (a, b) => new Date(b.updatedAt).getTime() - new Date(a.updatedAt).getTime(),
      ),
  }))

export const agentInstanceIcon = (agent?: Pick<Agent, 'agentType'> | null) =>
  agentTypeIcons[String(agent?.agentType || '').trim().toLowerCase()] || '🤖'

export interface AgentFreeWebAppChatProps {
  routeBase?: string
  webAppBotId?: string
  emptyAgentText?: string
  welcomeTitle?: string
  welcomeHint?: string
  mobileWelcomeHint?: string
  storageKey?: string
  currentUser?: { username?: string; displayName?: string; realName?: string; role?: string } | null
}

export function AgentFreeWebAppChat({
  routeBase = '/chat',
  webAppBotId,
  emptyAgentText = '暂无可访问智能体',
  welcomeTitle = '欢迎使用 Orbit',
  welcomeHint = '从左侧选择智能体或会话开始聊天',
  mobileWelcomeHint = '打开右侧菜单选择智能体或会话',
  storageKey = 'agentfree.chatSidebarWidth',
  currentUser,
}: AgentFreeWebAppChatProps) {
  const navigate = useNavigate()
  const location = useLocation()
  const { token } = theme.useToken()

  const [sessions, setSessions] = useState<Session[]>([])
  const [agents, setAgents] = useState<Agent[]>([])
  const [studioAgents, setStudioAgents] = useState<StudioAgent[]>([])
  const [loading, setLoading] = useState(false)
  const [renameModal, setRenameModal] = useState(false)
  const [renamingSession, setRenamingSession] = useState<Session | null>(null)
  const [renameValue, setRenameValue] = useState('')
  const [collapsed, setCollapsed] = useState(false)
  const [isMobile, setIsMobile] = useState(window.innerWidth <= 768)
  const [drawerOpen, setDrawerOpen] = useState(false)
  const [selectedAgentId, setSelectedAgentId] = useState<number | null>(null)
  const [selectedGatewayType, setSelectedGatewayType] = useState<RoutedGatewayType>('WebApp')
  const [webAppRouteAgentIds, setWebAppRouteAgentIds] = useState<Set<number>>(new Set())
  const [sidebarWidth, setSidebarWidth] = useState(() => {
    const saved = Number(window.localStorage.getItem(storageKey))
    return Number.isFinite(saved) && saved >= 220 && saved <= 460 ? saved : 280
  })
  const [resizing, setResizing] = useState(false)
  const emptySessionCreationInFlight = useRef(false)
  const currentUserName = useMemo(() => {
    return currentUser?.username || readCurrentUser()?.username || '当前用户'
  }, [currentUser?.username])
  const currentUserDisplayName = useMemo(() => {
    const user = currentUser || readCurrentUser()
    return user?.displayName || user?.realName || user?.username || currentUserName
  }, [currentUser, currentUserName])

  useEffect(() => {
    setAgentFreeWebAppCurrentUser(currentUser || null)
  }, [currentUser])
  useEffect(() => {
    if (webAppBotId) setAgentFreeWebAppBotId(webAppBotId)
  }, [webAppBotId])
  const getDefaultSessionName = () => {
    const d = new Date()
    const yyyy = d.getFullYear()
    const mm = String(d.getMonth() + 1).padStart(2, '0')
    const dd = String(d.getDate()).padStart(2, '0')
    return `main-${yyyy}-${mm}-${dd}`
  }

  const normalizedRouteBase = routeBase === '/' ? '' : routeBase.replace(/\/+$/, '')
  const currentSessionId = location.pathname.startsWith(`${normalizedRouteBase}/`)
    ? location.pathname.slice(normalizedRouteBase.length + 1)
    : undefined
  const sessionPath = (sessionId: string) => `${normalizedRouteBase}/${encodeURIComponent(sessionId)}`

  // 当前会话及其关联智能体信息
  const currentSession = useMemo(
    () => sessions.find((s) => s.id === currentSessionId) || null,
    [sessions, currentSessionId],
  )
  const currentAgent = useMemo(
    () => agents.find((a) => a.id === currentSession?.agentId) || null,
    [agents, currentSession?.agentId],
  )
  const selectedAgent = useMemo(
    () => resolveSelectedAgent(agents, selectedAgentId, currentAgent),
    [agents, selectedAgentId, currentAgent],
  )
  const currentAgentName = currentSession?.agentName || currentAgent?.name
  const currentAgentType = currentSession?.agentType || currentAgent?.agentType
  const currentAgentCode = currentSession?.agentCode || currentAgent?.agentCode
  const currentAgentConfigJson = currentSession?.agentConfigJson || currentAgent?.configJson
  const currentAgentStatus = currentSession?.agentStatus || currentAgent?.status
  const currentStudioAgentName = currentSession?.studioAgentName || studioAgents.find(item => item.id === currentAgent?.agentId)?.name

  useEffect(() => {
    const handler = () => setIsMobile(window.innerWidth <= 768)
    window.addEventListener('resize', handler)
    return () => window.removeEventListener('resize', handler)
  }, [])

  useEffect(() => {
    if (isMobile) setCollapsed(true)
  }, [isMobile])

  useEffect(() => {
    if (!resizing) return undefined
    const onPointerMove = (event: PointerEvent) => {
      const nextWidth = Math.min(460, Math.max(220, event.clientX))
      setSidebarWidth(nextWidth)
    }
    const onPointerUp = () => setResizing(false)
    document.body.style.cursor = 'col-resize'
    document.body.style.userSelect = 'none'
    window.addEventListener('pointermove', onPointerMove)
    window.addEventListener('pointerup', onPointerUp)
    return () => {
      document.body.style.cursor = ''
      document.body.style.userSelect = ''
      window.removeEventListener('pointermove', onPointerMove)
      window.removeEventListener('pointerup', onPointerUp)
    }
  }, [resizing])

  useEffect(() => {
    if (!isMobile && !collapsed) {
      window.localStorage.setItem(storageKey, String(sidebarWidth))
    }
  }, [sidebarWidth, collapsed, isMobile, storageKey])

  useEffect(() => {
    if (currentSession?.agentId) {
      setSelectedAgentId(currentSession.agentId)
    }
  }, [currentSession?.agentId])

  useEffect(() => {
    if (selectedAgentId && !agents.some(agent => agent.id === selectedAgentId)) {
      setSelectedAgentId(null)
    }
  }, [agents, selectedAgentId])

  const createSessionForAgent = async (agent: Agent, routeAgentIds = webAppRouteAgentIds, announce = true) => {
    if (agent.status !== 'Active') {
      if (announce) message.warning(`智能体“${agent.name}”当前已停止，不能创建会话`)
      return null
    }
    if (!routeAgentIds.has(agent.id)) {
      if (announce) message.warning(`智能体“${agent.name}”没有 WEBAP 路由，不能在网页对话中新建会话`)
      return null
    }
    try {
      const res = await createSession({ agentId: agent.id, name: getDefaultSessionName(), webAppBotId })
      const newSession = res.data
      const hydratedSession: Session = {
        ...newSession,
        agentName: agent.name || newSession.agentName || `智能体#${agent.id}`,
      }
      setSessions(prev => [hydratedSession, ...prev.filter(session => session.id !== hydratedSession.id)])
      if (announce) message.success('创建成功')
      if (newSession?.id) navigate(sessionPath(newSession.id), { replace: !announce })
      return hydratedSession
    } catch (err: any) {
      message.error(`${announce ? '创建失败' : '自动创建首个会话失败'}: ` + (err.response?.data?.message || err.message))
      return null
    }
  }

  const fetchData = async () => {
    setLoading(true)
    try {
      const [sessionsRes, agentsRes, studioAgentsRes] = await Promise.all([
        getSessions('WebApp', currentUserName, webAppBotId),
        getAgents(true, 'WebApp', currentUserName, false, webAppBotId),
        getStudioAgents({ mine: true }),
      ])
      const webAppAgentIds = new Set((agentsRes.data || []).map(agent => agent.id))
      setWebAppRouteAgentIds(webAppAgentIds)
      const nextSessions = (sessionsRes.data || []).filter(session => webAppAgentIds.has(session.agentId))
      const nextAgents = agentsRes.data || []
      setSessions(nextSessions)
      setAgents(nextAgents)
      setStudioAgents(studioAgentsRes.data || [])
      const emptySessionAgent = resolveEmptySessionAgent(nextAgents, nextSessions, webAppAgentIds)
      if (emptySessionAgent && !emptySessionCreationInFlight.current) {
        emptySessionCreationInFlight.current = true
        try {
          await createSessionForAgent(emptySessionAgent, webAppAgentIds, false)
        } finally {
          emptySessionCreationInFlight.current = false
        }
      } else if (nextSessions.length > 0 && !currentSessionId) {
        const firstSession = nextSessions
          .slice()
          .sort((a, b) => new Date(b.updatedAt).getTime() - new Date(a.updatedAt).getTime())[0]
        if (firstSession?.id) navigate(sessionPath(firstSession.id), { replace: true })
      }
    } catch (err: any) {
      message.error('加载失败: ' + (err.response?.data?.message || err.message))
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => { fetchData() }, [currentUserName, webAppBotId])

  const getAgentGroup = (agent: Agent) => agent.groupName?.trim() || agent.agentType || '默认分组'
  const compareAgentsByManagementOrder = (a: Agent, b: Agent) => {
    const groupCompare = getAgentGroup(a).localeCompare(getAgentGroup(b), 'zh-CN')
    if (groupCompare !== 0) return groupCompare
    const sortCompare = (a.sortOrder ?? 0) - (b.sortOrder ?? 0)
    if (sortCompare !== 0) return sortCompare
    return a.id - b.id
  }

  // 默认先展示所有可访问智能体，再展示该智能体下的会话；顺序与智能体管理分组/排序一致。
  const groupedAgents = useMemo(() => {
    return groupAgentsWithSessions(agents, sessions, selectedGatewayType, compareAgentsByManagementOrder)
  }, [agents, sessions, selectedGatewayType])
  const agentMenuOpenKeys = useMemo(() => groupedAgents.map(group => `agent-${group.agent.id}`), [groupedAgents])
  const handleCreateForAgent = async (agent: Agent) => {
    await createSessionForAgent(agent)
  }

  const openRename = (session: Session) => {
    setRenamingSession(session)
    setRenameValue(session.name || '')
    setRenameModal(true)
  }

  const handleRename = async () => {
    if (!renamingSession) return
    const name = renameValue.trim()
    if (!name) {
      message.warning('请输入会话名称')
      return
    }
    try {
      await updateSession(renamingSession.id, { name })
      setSessions(prev => prev.map(s => s.id === renamingSession.id ? { ...s, name, updatedAt: new Date().toISOString() } : s))
      setRenameModal(false)
      setRenamingSession(null)
      message.success('已修改会话名称')
      await fetchData()
    } catch (err: any) {
      message.error('修改失败: ' + (err.response?.data?.message || err.message))
    }
  }

  const handleArchive = async (id: string) => {
    try {
      await archiveSession(id)
      message.success('已归档')
      fetchData()
      if (currentSessionId === id) navigate(normalizedRouteBase || '/')
    } catch (err: any) {
      message.error('归档失败: ' + (err.response?.data?.message || err.message))
    }
  }

  const sessionGatewayTypeLabel = (type: RoutedGatewayType) => type === 'WeCom'
    ? '企业微信'
    : type === 'Wechat'
      ? '微信'
      : type === 'Feishu'
        ? '飞书'
        : 'WEBAP'

  const sessionGatewayLabel = (session?: Session | null) => session?.gatewayTypeLabel || (normalizeSessionGatewayType(session) === 'WeCom'
    ? '企业微信'
    : normalizeSessionGatewayType(session) === 'Wechat'
      ? '微信'
    : normalizeSessionGatewayType(session) === 'Feishu'
      ? '飞书'
      : 'WEBAP')

  const sessionGatewayTypeIcon = (type: RoutedGatewayType, label = sessionGatewayTypeLabel(type), style?: React.CSSProperties) => {
    const common = { title: label, style: { fontSize: 13, flexShrink: 0, ...style } }
    if (type === 'WeCom') return <WechatWorkOutlined {...common} style={{ ...common.style, color: '#1677ff' }} />
    if (type === 'Wechat') return <WechatOutlined {...common} style={{ ...common.style, color: '#52c41a' }} />
    if (type === 'Feishu') return <SendOutlined {...common} style={{ ...common.style, color: '#3370ff' }} />
    return <GlobalOutlined {...common} style={{ ...common.style, color: '#1677ff' }} />
  }

  const sessionGatewayIcon = (session?: Session | null) => {
    return sessionGatewayTypeIcon(normalizeSessionGatewayType(session), sessionGatewayLabel(session))
  }

  const gatewayTypeFilters = useMemo(() => availableSessionGatewayTypes(sessions), [sessions])

  const sessionOwnerLabel = (session?: Session | null) => session?.userName || currentUserDisplayName
  const sessionDisplayTitle = (session?: Session | null) => {
    return session?.name || '会话'
  }

  const siderContent = (
    <div style={{ height: '100%', display: 'flex', flexDirection: 'column' }}>
      <div style={{ padding: collapsed ? '8px 8px 6px' : '10px 10px 8px', display: 'grid', gap: 8 }}>
        {!collapsed && (
          <>
            <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 10, minWidth: 0, minHeight: 30 }}>
              <span style={{ fontSize: 12, color: '#8c8c8c', whiteSpace: 'nowrap', lineHeight: '24px' }}>会话列表</span>
              <div style={{ display: 'flex', alignItems: 'center', gap: 4, flexShrink: 0 }}>
                {gatewayTypeFilters.map(type => {
                  const active = selectedGatewayType === type
                  const label = sessionGatewayTypeLabel(type)
                  return (
                    <Tooltip title={label} key={type}>
                      <button
                        type="button"
                        aria-label={`筛选${label}会话`}
                        aria-pressed={active}
                        onClick={() => setSelectedGatewayType(type)}
                        style={{
                          width: 26,
                          height: 26,
                          border: `1px solid ${active ? '#1677ff' : '#d9d9d9'}`,
                          background: active ? '#e6f4ff' : '#fff',
                          borderRadius: 6,
                          display: 'inline-flex',
                          alignItems: 'center',
                          justifyContent: 'center',
                          padding: 0,
                          cursor: 'pointer',
                          boxShadow: active ? '0 0 0 2px rgba(22,119,255,.08)' : undefined,
                        }}
                      >
                        {sessionGatewayTypeIcon(type, label, { fontSize: 14 })}
                      </button>
                    </Tooltip>
                  )
                })}
              </div>
            </div>
          </>
        )}
      </div>
      <div style={{ flex: 1, overflowY: 'auto', padding: '0 4px 8px 0' }}>
        {agents.length === 0 ? (
          <div style={{ textAlign: 'center', padding: '32px 16px', color: '#bbb', fontSize: 13 }}>
            <div style={{ fontSize: 32, marginBottom: 8 }}>📭</div>
            {emptyAgentText}
          </div>
        ) : (
          <Menu
            mode="inline"
            selectedKeys={currentSessionId ? [currentSessionId] : []}
            openKeys={agentMenuOpenKeys}
            items={[
              ...groupedAgents.map(group => ({
                key: `agent-${group.agent.id}`,
                label: (
                  <div style={{ display: 'flex', alignItems: 'center', gap: 8, minWidth: 0 }}>
                    <span
                      aria-hidden
                      style={{
                        width: 20,
                        height: 20,
                        borderRadius: 6,
                        background: '#f5f7fb',
                        display: 'inline-flex',
                        alignItems: 'center',
                        justifyContent: 'center',
                        fontSize: 13,
                        flexShrink: 0,
                      }}
                    >
                      {agentInstanceIcon(group.agent)}
                    </span>
                    <span
                      onClick={() => setSelectedAgentId(group.agent.id)}
                      title={group.agent.name}
                      style={{
                        flex: '1 1 auto',
                        minWidth: 0,
                        overflow: 'hidden',
                        textOverflow: 'ellipsis',
                        whiteSpace: 'nowrap',
                        fontWeight: 600,
                        color: group.agent.id === selectedAgent?.id ? '#1677ff' : (group.agent.status === 'Active' ? undefined : '#999'),
                      }}
                    >
                      {group.agent.name}
                      {group.agent.status !== 'Active' ? '（已停止）' : ''}
                    </span>
                    <Button
                      type="text"
                      size="small"
                      icon={<PlusOutlined />}
                      disabled={group.agent.status !== 'Active' || !webAppRouteAgentIds.has(group.agent.id)}
                      onClick={(e) => {
                        e.stopPropagation()
                        setSelectedAgentId(group.agent.id)
                        handleCreateForAgent(group.agent)
                      }}
                      aria-label={`新增${group.agent.name}会话`}
                      style={{ width: 24, height: 24, minWidth: 24, padding: 0, borderRadius: 6, flexShrink: 0, marginLeft: 'auto' }}
                    />
                  </div>
                ),
                children: group.sessions.length > 0
                  ? group.sessions.map(s => ({
                      key: s.id,
                      label: (
                        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', minWidth: 0, gap: 5 }}>
                          {sessionGatewayIcon(s)}
                          <span title={`${sessionGatewayLabel(s)} · ${sessionDisplayTitle(s)}`} style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap', flex: 1, fontSize: 13 }}>
                            {sessionDisplayTitle(s)}
                          </span>
                          <EditOutlined
                            title="修改名称"
                            onClick={(e) => {
                              e.stopPropagation()
                              openRename(s)
                            }}
                            style={{ color: '#999', fontSize: 12, flexShrink: 0 }}
                          />
                          <Popconfirm title="归档此会话？" onConfirm={() => handleArchive(s.id)} okText="归档" cancelText="取消">
                            <InboxOutlined
                              onClick={(e) => e.stopPropagation()}
                              title="归档"
                              style={{ color: '#bbb', fontSize: 12, flexShrink: 0 }}
                            />
                          </Popconfirm>
                        </div>
                      ),
                    }))
                  : undefined,
              })),
            ]}
            onClick={({ key }) => {
              if (/^agent-\d+$/.test(key)) {
                setSelectedAgentId(Number(key.replace('agent-', '')))
                return
              }
              navigate(sessionPath(String(key)))
              setCollapsed(false)
              setDrawerOpen(false)
            }}
            style={{ borderRight: 0 }}
            className="agentfree-chat-session-menu"
          />
        )}
      </div>
    </div>
  )

  // Mobile layout with fixed chat area
  if (isMobile) {
    return (
      <Layout style={{ height: '100%', minHeight: 0, overflow: 'hidden' }}>
        <Drawer
          title="会话列表"
          placement="right"
          width={280}
          open={drawerOpen}
          onClose={() => setDrawerOpen(false)}
          styles={{ body: { padding: 0 } }}
        >
          {siderContent}
        </Drawer>
        <Layout style={{ height: '100%', minHeight: 0, overflow: 'hidden' }}>
          <Content style={{ padding: 0, height: '100%', overflow: 'hidden', display: 'flex', flexDirection: 'column' }}>
            {/* Mobile header bar */}
            <div style={{ background: '#fff', padding: '10px 12px', display: 'flex', alignItems: 'center', borderBottom: '1px solid #f0f0f0', flexShrink: 0 }}>
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ fontSize: 15, fontWeight: 600, color: '#333', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                  {sessionDisplayTitle(currentSession)}
                </div>
                <div style={{ fontSize: 11, color: '#999', marginTop: 2, display: 'flex', alignItems: 'center', gap: 6, overflow: 'hidden', whiteSpace: 'nowrap' }}>
                  <span style={{ overflow: 'hidden', textOverflow: 'ellipsis' }}>
                    {sessionGatewayLabel(currentSession)} - {(currentAgentName || '未命名智能体')} - {(currentSession?.name || '会话')} - 用户: {sessionOwnerLabel(currentSession)}
                  </span>
                </div>
              </div>
              <Button type="text" icon={<MenuFoldOutlined />} onClick={() => setDrawerOpen(true)} style={{ marginLeft: 8 }} />
            </div>
            {/* Chat area fills remaining space */}
            <div style={{ flex: '1 1 0', minHeight: 0, overflow: 'hidden', display: 'flex', flexDirection: 'column' }}>
            {currentSessionId ? (
              <CleanChatView
                sessionId={currentSessionId}
                agentId={currentSession?.agentId}
                agentName={currentAgentName}
                agentType={currentAgentType}
                agentCode={currentAgentCode}
                agentConfigJson={currentAgentConfigJson}
                agentStatus={currentAgentStatus}
                studioAgentName={currentStudioAgentName}
                onSessionUpdated={fetchData}
              />
            ) : (
                <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', height: '100%', flexDirection: 'column', color: '#bbb' }}>
                  <div style={{ fontSize: 48, marginBottom: 12 }}>🪐</div>
                  <div style={{ fontSize: 16, marginBottom: 4 }}>{welcomeTitle}</div>
                  <div style={{ fontSize: 13 }}>{mobileWelcomeHint}</div>
                </div>
              )}
            </div>
          </Content>
        </Layout>
        <Drawer
          title="修改会话名称"
          open={renameModal}
          onClose={() => setRenameModal(false)}
          width="100%"
          extra={
            <Space>
              <Button onClick={() => setRenameModal(false)}>取消</Button>
              <Button type="primary" onClick={handleRename}>保存</Button>
            </Space>
          }
        >
          <Input value={renameValue} onChange={(e) => setRenameValue(e.target.value)} placeholder="输入会话名称" onPressEnter={handleRename} />
        </Drawer>
      </Layout>
    )
  }

  // Desktop layout with fixed chat area
  return (
    <Layout style={{ height: '100%', minHeight: 0, overflow: 'hidden' }}>
      <Sider
        collapsible
        collapsed={collapsed}
        onCollapse={setCollapsed}
        width={collapsed ? 80 : sidebarWidth}
        theme="light"
        style={{
          borderRight: `1px solid ${token.colorBorderSecondary}`,
          background: '#fff',
          overflow: 'hidden',
        }}
        breakpoint="lg"
        collapsedWidth={80}
      >
        {siderContent}
      </Sider>
      {!collapsed && (
        <div
          role="separator"
          aria-orientation="vertical"
          aria-label="调整会话列表宽度"
          title="拖动调整会话列表宽度"
          onPointerDown={(event) => {
            event.preventDefault()
            setResizing(true)
          }}
          style={{
            width: 6,
            flex: '0 0 6px',
            cursor: 'col-resize',
            background: resizing ? '#e6f4ff' : 'transparent',
            borderRight: `1px solid ${token.colorBorderSecondary}`,
            transition: resizing ? undefined : 'background .15s',
          }}
          onMouseEnter={(event) => {
            event.currentTarget.style.background = '#f0f5ff'
          }}
          onMouseLeave={(event) => {
            if (!resizing) event.currentTarget.style.background = 'transparent'
          }}
        />
      )}
      <Content style={{ padding: 0, background: 'linear-gradient(180deg, #f7f9fc 0%, #f2f5fa 100%)', height: '100%', overflow: 'hidden', display: 'flex', flexDirection: 'column' }}>
        <div style={{ flex: '1 1 0', minHeight: 0, overflow: 'hidden', display: 'flex' }}>
          <div style={{ width: '100%', height: '100%', display: 'flex', flexDirection: 'column', minHeight: 0 }}>
            {currentSessionId ? (
              <>
                {/* Session Header */}
                <div style={{
                  padding: '10px 20px',
                  background: '#fff',
                  borderBottom: '1px solid #f0f0f0',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'space-between',
                  flexShrink: 0,
                }}>
                  <div style={{ flex: 1, minWidth: 0, overflow: 'hidden', whiteSpace: 'nowrap' }}>
                    <span style={{ fontSize: 13, color: '#333', overflow: 'hidden', textOverflow: 'ellipsis', display: 'block' }}>
                      {sessionGatewayLabel(currentSession)} - {(currentAgentName || '未命名智能体')} - {(currentSession?.name || '会话')} - 用户: {sessionOwnerLabel(currentSession)}
                    </span>
                  </div>
                </div>
                <CleanChatView
                  sessionId={currentSessionId}
                agentId={currentSession?.agentId}
                agentName={currentAgentName}
                agentType={currentAgentType}
                agentCode={currentAgentCode}
                agentConfigJson={currentAgentConfigJson}
                agentStatus={currentAgentStatus}
                studioAgentName={currentStudioAgentName}
                onSessionUpdated={fetchData}
              />
              </>
            ) : (
              <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', height: '100%', flexDirection: 'column', color: '#bbb' }}>
                <div style={{ fontSize: 64, marginBottom: 16 }}>🪐</div>
                <div style={{ fontSize: 20, marginBottom: 8, fontWeight: 500 }}>{welcomeTitle}</div>
                <div style={{ fontSize: 14 }}>{welcomeHint}</div>
              </div>
            )}
          </div>
        </div>
      </Content>
      <Drawer
        title="修改会话名称"
        open={renameModal}
        onClose={() => setRenameModal(false)}
        width={420}
        extra={
          <Space>
            <Button onClick={() => setRenameModal(false)}>取消</Button>
            <Button type="primary" onClick={handleRename}>保存</Button>
          </Space>
        }
      >
        <Input value={renameValue} onChange={(e) => setRenameValue(e.target.value)} placeholder="输入会话名称" onPressEnter={handleRename} />
      </Drawer>
    </Layout>
  )
}

export default function ChatLayout() {
  return <AgentFreeWebAppChat />
}
