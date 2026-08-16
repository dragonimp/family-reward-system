// 用户点击 A2UI 组件后回传给智能体的 [A2UI_ACTION] 消息，在聊天里以友好标签展示而非裸 JSON。
export function parseA2UiActionMessage(content?: string): { label: string; ok: boolean } | null {
  if (!content) return null
  const t = content.trimStart()
  if (!t.startsWith('[A2UI_ACTION]')) return null
  try {
    const obj = JSON.parse(t.slice('[A2UI_ACTION]'.length).trim())
    const a = obj.action || obj
    const ctx = a.context || {}
    const label = ctx.label || a.text || ctx.choice || a.name || '交互操作'
    const ok = ctx.choice ? ctx.choice === 'yes' : a.name !== 'cancel'
    return { label: String(label), ok }
  } catch {
    return { label: '交互操作', ok: true }
  }
}
