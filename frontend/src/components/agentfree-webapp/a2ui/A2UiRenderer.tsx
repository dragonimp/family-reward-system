import React, { useMemo, useRef, useState } from 'react'
import { Button, Card, Checkbox, DatePicker, Divider, Empty, Image, Input, Radio, Select, Space, Tabs, Typography } from 'antd'
import ReactMarkdown from 'react-markdown'
import remarkBreaks from 'remark-breaks'
import remarkGfm from 'remark-gfm'
import type { A2UiAction, A2UiComponent, A2UiMessage, A2UiRendererProps, A2UiSurface } from './types'

const { Text } = Typography

export function A2UiRenderer({ messages, onAction }: A2UiRendererProps) {
  const dataModelCacheRef = useRef(new Map<string, unknown>())
  const surfaces = useMemo(() => {
    const next = buildSurfaces(messages)
    for (const surface of next) {
      const cached = dataModelCacheRef.current.get(surface.surfaceId)
      if (cached !== undefined) surface.dataModel = mergeDataModel(surface.dataModel, cached)
    }
    return next
  }, [messages])
  const [, forceRender] = useState(0)
  const rememberSurface = (surface: A2UiSurface) => {
    dataModelCacheRef.current.set(surface.surfaceId, surface.dataModel)
  }

  if (surfaces.length === 0) {
    return <Empty image={Empty.PRESENTED_IMAGE_SIMPLE} description="A2UI 暂无可渲染内容" />
  }

  return (
    <div style={{ display: 'grid', gap: 10 }}>
      {surfaces.map(surface => (
        <Card key={surface.surfaceId} size="small" styles={{ body: { padding: 10 } }}>
          {renderComponent(surface, surface.rootId, async action => {
            await onAction({ ...action, dataModel: surface.dataModel } as A2UiAction)
            forceRender(v => v + 1)
          }, 0, () => forceRender(v => v + 1), rememberSurface)}
        </Card>
      ))}
    </div>
  )
}

function buildSurfaces(messages: A2UiMessage[]) {
  const surfaces = new Map<string, A2UiSurface>()

  for (const message of messages) {
    const payload = unwrapMessage(message)
    if (!payload || typeof payload !== 'object') continue

    const deleteSurface = readProp(payload, 'deleteSurface', 'delete_surface')
    if (deleteSurface) {
      const surfaceId = readString(readProp(deleteSurface, 'surfaceId', 'surface_id'))
      if (surfaceId) surfaces.delete(surfaceId)
      continue
    }

    const createSurfaceSpec = readProp(payload, 'createSurface', 'create_surface')
    if (createSurfaceSpec) {
      const spec = createSurfaceSpec || {}
      const surfaceId = readString(readProp(spec, 'surfaceId', 'surface_id')) || `surface-${surfaces.size + 1}`
      const surface = surfaces.get(surfaceId) || createSurface(surfaceId)
      surface.catalogId = readString(readProp(spec, 'catalogId', 'catalog_id')) || surface.catalogId
      surface.dataModel = readProp(spec, 'dataModel', 'data_model') ?? surface.dataModel ?? {}
      const components = readProp(spec, 'components')
      applyComponents(surface, Array.isArray(components) ? components : [])
      surfaces.set(surfaceId, surface)
      continue
    }

    const updateComponents = readProp(payload, 'updateComponents', 'update_components')
    if (updateComponents) {
      const spec = updateComponents || {}
      const surfaceId = readString(readProp(spec, 'surfaceId', 'surface_id')) || 'default'
      const surface = surfaces.get(surfaceId) || createSurface(surfaceId)
      const components = readProp(spec, 'components')
      applyComponents(surface, Array.isArray(components) ? components : [])
      surfaces.set(surfaceId, surface)
      continue
    }

    const updateDataModel = readProp(payload, 'updateDataModel', 'update_data_model')
    if (updateDataModel) {
      const spec = updateDataModel || {}
      const surfaceId = readString(readProp(spec, 'surfaceId', 'surface_id')) || 'default'
      const surface = surfaces.get(surfaceId) || createSurface(surfaceId)
      surface.dataModel = setJsonPath(surface.dataModel ?? {}, readString(readProp(spec, 'path')) || '/', readProp(spec, 'value') ?? readProp(spec, 'dataModel', 'data_model') ?? {})
      surfaces.set(surfaceId, surface)
      continue
    }

    if (looksLikeComponent(payload)) {
      const surface = surfaces.get('default') || createSurface('default')
      applyComponents(surface, [payload])
      surfaces.set(surface.surfaceId, surface)
    }
  }

  return Array.from(surfaces.values()).filter(s => s.components.size > 0)
}

function unwrapMessage(message: A2UiMessage): Record<string, unknown> | null {
  const content = (message as any).content
  if (Array.isArray(content)) return { updateComponents: { surfaceId: 'default', components: content } }
  if (content && typeof content === 'object') return content
  if (Array.isArray((message as any).data)) return { updateComponents: { surfaceId: 'default', components: (message as any).data } }
  return message
}

function readProp(source: unknown, ...names: string[]): any {
  if (!source || typeof source !== 'object') return undefined
  const record = source as Record<string, unknown>
  for (const name of names) {
    if (Object.prototype.hasOwnProperty.call(record, name)) return record[name]
  }
  return undefined
}

function createSurface(surfaceId: string): A2UiSurface {
  return { surfaceId, components: new Map(), dataModel: {}, rootId: 'root' }
}

function applyComponents(surface: A2UiSurface, components: unknown[]) {
  for (const raw of components) {
    if (!looksLikeComponent(raw)) continue
    const component = raw as A2UiComponent
    surface.components.set(component.id, component)
    if (component.id === 'root') surface.rootId = 'root'
  }
  if (!surface.components.has(surface.rootId) && components.length > 0) {
    const first = components.find(looksLikeComponent) as A2UiComponent | undefined
    if (first) surface.rootId = first.id
  }
}

function renderComponent(surface: A2UiSurface, id: string, onAction: (action: A2UiAction) => void | Promise<void>, depth = 0, rerender: () => void = () => {}, onSurfaceChange: (surface: A2UiSurface) => void = () => {}): React.ReactNode {
  const component = surface.components.get(id)
  if (!component) return null
  if (depth > 24) return null

  const child = readString(component.child)
  const children = readChildList(component.children)
  const renderChildren = () => (
    <>
      {child && renderComponent(surface, child, onAction, depth + 1, rerender, onSurfaceChange)}
      {children.map(childId => <React.Fragment key={childId}>{renderComponent(surface, childId, onAction, depth + 1, rerender, onSurfaceChange)}</React.Fragment>)}
    </>
  )

  switch (normalizeComponentName(component.component)) {
    case 'text':
      return <MarkdownText>{readDynamicString(component.text, surface.dataModel) || ''}</MarkdownText>
    case 'image':
      return <Image src={readDynamicString(component.url ?? component.src, surface.dataModel)} alt={readDynamicString(component.alt, surface.dataModel)} style={{ maxWidth: '100%' }} />
    case 'video':
      return <video controls src={readDynamicString(component.url ?? component.src, surface.dataModel)} style={{ maxWidth: '100%', borderRadius: 6 }} />
    case 'audioplayer':
    case 'audio':
      return <audio controls src={readDynamicString(component.url ?? component.src, surface.dataModel)} style={{ width: '100%' }} />
    case 'row':
      return <div style={{ display: 'flex', gap: 8, alignItems: mapAlign(component.align), justifyContent: mapJustify(component.justify), flexWrap: 'wrap' }}>{renderChildren()}</div>
    case 'column':
      return <div style={{ display: 'grid', gap: 8 }}>{renderChildren()}</div>
    case 'list':
      return <div style={{ display: 'grid', gap: 6 }}>{renderChildren()}</div>
    case 'card':
      return <Card size="small" style={{ borderRadius: 8 }}>{renderChildren()}</Card>
    case 'divider':
      return <Divider style={{ margin: '8px 0' }} />
    case 'button':
      return (
        <Button type={component.variant === 'primary' ? 'primary' : 'default'} onClick={() => emitAction(component.action, surface, onAction)}>
          {child ? renderComponent(surface, child, onAction, depth + 1, rerender, onSurfaceChange) : readDynamicString(component.text ?? component.label, surface.dataModel) || '操作'}
        </Button>
      )
    case 'checkbox':
      return (
        <Checkbox
          checked={Boolean(readDynamicValue(component.value, surface.dataModel))}
          onChange={event => { writeDynamicValue(surface, component.value, event.target.checked); onSurfaceChange(surface); rerender() }}
        >
          {readDynamicString(component.label, surface.dataModel)}
        </Checkbox>
      )
    case 'textfield':
      return (
        <Input
          placeholder={readDynamicString(component.label ?? component.placeholder, surface.dataModel)}
          value={String(readDynamicValue(component.value, surface.dataModel) ?? '')}
          onChange={event => { writeDynamicValue(surface, component.value, event.target.value); onSurfaceChange(surface); rerender() }}
        />
      )
    case 'datetimeinput':
    case 'dateinput':
    case 'date':
      return (
        <DatePicker
          style={{ width: '100%' }}
          placeholder={readDynamicString(component.label, surface.dataModel) || '请选择日期'}
          onChange={(_d, dateString) => {
            const value = Array.isArray(dateString) ? dateString[0] : dateString
            writeDynamicValue(surface, resolveValueBinding(component), value)
            onSurfaceChange(surface)
            rerender()
          }}
        />
      )
    case 'choicepicker':
      return renderChoicePicker(surface, component, rerender, onSurfaceChange)
    case 'tabs':
      return <Tabs size="small" items={children.map(childId => ({ key: childId, label: surface.components.get(childId)?.title as string || childId, children: renderComponent(surface, childId, onAction, depth + 1, rerender, onSurfaceChange) }))} />
    default:
      return <Text type="secondary">未支持组件：{component.component}</Text>
  }
}

function renderChoicePicker(surface: A2UiSurface, component: A2UiComponent, rerender: () => void = () => {}, onSurfaceChange: (surface: A2UiSurface) => void = () => {}) {
  const options = Array.isArray(component.options) ? component.options.map((item: any) => ({
    label: readDynamicString(item.label, surface.dataModel) || String(item.value ?? ''),
    value: String(item.value ?? item.label ?? ''),
  })) : []
  const value = readDynamicValue(component.value, surface.dataModel)
  if (component.variant === 'mutuallyExclusive') {
    return <Radio.Group options={options} value={value} onChange={event => { writeDynamicValue(surface, component.value, event.target.value); onSurfaceChange(surface); rerender() }} />
  }
  return <Select mode="multiple" style={{ minWidth: 180 }} options={options} value={Array.isArray(value) ? value : []} onChange={next => { writeDynamicValue(surface, component.value, next); onSurfaceChange(surface); rerender() }} />
}

function emitAction(action: unknown, surface: A2UiSurface, onAction: (action: A2UiAction) => void | Promise<void>) {
  if (!action || typeof action !== 'object') {
    void onAction({ type: 'unknown', payload: action, dataModel: surface.dataModel })
    return
  }
  const raw = action as any
  if (raw.event) {
    void onAction({ type: 'event', name: String(raw.event.name || 'a2ui_event'), context: mergeActionPayload(raw.event.context, surface.dataModel), dataModel: surface.dataModel })
    return
  }
  if (raw.function) {
    void onAction({ type: 'function', name: String(raw.function.name || raw.function.call || 'a2ui_function'), args: mergeActionPayload(raw.function.args, surface.dataModel), dataModel: surface.dataModel })
    return
  }
  if (raw.openUrl || raw.open_url || raw.url) {
    void onAction({ type: 'open_url', url: String(raw.openUrl || raw.open_url || raw.url), dataModel: surface.dataModel })
    return
  }
  if (raw.sendMessage || raw.send_message) {
    void onAction({ type: 'send_message', text: String(raw.sendMessage || raw.send_message), dataModel: surface.dataModel })
    return
  }
  void onAction({ type: 'unknown', payload: action, dataModel: surface.dataModel })
}

function readChildList(value: unknown): string[] {
  if (Array.isArray(value)) return value.map(String)
  if (value && typeof value === 'object' && Array.isArray((value as any).array)) return (value as any).array.map(String)
  return []
}

function readDynamicString(value: unknown, model: unknown) {
  const resolved = readDynamicValue(value, model)
  return resolved == null ? '' : String(resolved)
}

function readDynamicValue(value: unknown, model: unknown): unknown {
  if (value && typeof value === 'object' && typeof (value as any).path === 'string') {
    return getJsonPath(model, (value as any).path)
  }
  if (value && typeof value === 'object' && typeof (value as any).call === 'string') return ''
  return value
}

function writeDynamicValue(surface: A2UiSurface, binding: unknown, value: unknown) {
  if (binding && typeof binding === 'object' && typeof (binding as any).path === 'string') {
    surface.dataModel = setJsonPath(surface.dataModel ?? {}, (binding as any).path, value)
  }
}

function resolveValueBinding(component: A2UiComponent) {
  if (component.value && typeof component.value === 'object' && typeof (component.value as any).path === 'string') return component.value
  if (typeof component.name === 'string' && component.name.trim()) return { path: `/${component.name.trim()}` }
  if (typeof component.id === 'string' && component.id.trim()) return { path: `/${component.id.trim()}` }
  return { path: '/value' }
}

function mergeActionPayload(payload: unknown, dataModel: unknown): Record<string, unknown> | undefined {
  const base = payload && typeof payload === 'object' && !Array.isArray(payload) ? { ...(payload as Record<string, unknown>) } : {}
  const model = flattenDataModel(dataModel)
  const merged = { ...model, ...base }
  return Object.keys(merged).length > 0 ? merged : undefined
}

function flattenDataModel(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return {}
  const source = value as Record<string, unknown>
  const result: Record<string, unknown> = {}
  for (const [key, item] of Object.entries(source)) {
    if (item == null) continue
    if (typeof item === 'string' || typeof item === 'number' || typeof item === 'boolean' || Array.isArray(item)) {
      result[key] = item
    }
  }
  if (result.value != null && result.date == null) result.date = result.value
  return result
}

function mergeDataModel(base: unknown, cached: unknown): unknown {
  if (!cached || typeof cached !== 'object' || Array.isArray(cached)) return base
  if (!base || typeof base !== 'object' || Array.isArray(base)) return cached
  return { ...(base as Record<string, unknown>), ...(cached as Record<string, unknown>) }
}

function getJsonPath(model: unknown, path: string) {
  if (!path || path === '/') return model
  return path.split('/').slice(1).reduce<any>((cur, part) => cur == null ? undefined : cur[decodeURIComponent(part)], model as any)
}

function setJsonPath(model: unknown, path: string, value: unknown) {
  if (!path || path === '/') return value
  const root: any = Array.isArray(model) ? [...model] : { ...(model as any || {}) }
  let cur = root
  const parts = path.split('/').slice(1).map(decodeURIComponent)
  parts.forEach((part, index) => {
    if (index === parts.length - 1) {
      cur[part] = value
    } else {
      cur[part] = Array.isArray(cur[part]) ? [...cur[part]] : { ...(cur[part] || {}) }
      cur = cur[part]
    }
  })
  return root
}

function looksLikeComponent(value: unknown): value is A2UiComponent {
  return !!value && typeof value === 'object' && typeof (value as any).id === 'string' && typeof (value as any).component === 'string'
}

function normalizeComponentName(value: string) {
  return value.replace(/[\s_-]/g, '').toLowerCase()
}

function readString(value: unknown) {
  return typeof value === 'string' && value.trim() ? value.trim() : undefined
}

function mapAlign(value: unknown) {
  return value === 'end' ? 'flex-end' : value === 'center' ? 'center' : value === 'stretch' ? 'stretch' : 'flex-start'
}

function mapJustify(value: unknown) {
  return value === 'spaceBetween' ? 'space-between' : value === 'end' ? 'flex-end' : value === 'center' ? 'center' : 'flex-start'
}

function MarkdownText({ children }: { children: string }) {
  return <ReactMarkdown remarkPlugins={[remarkGfm, remarkBreaks]}>{children}</ReactMarkdown>
}
