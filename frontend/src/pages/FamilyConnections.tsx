import { useCallback, useEffect, useRef, useState } from 'react';
import type { Child } from '../types';
import {
  addFamilyConnectionEntry, createFamilyConnection, getChildren, getFamilyConnections,
  transitionFamilyConnection, type ConnectionEntryType, type ConnectionKind, type ConnectionsPayload,
} from '../services';

const kinds: Record<ConnectionKind, { name: string; hint: string }> = {
  special_time: { name: '孩子决定的十分钟', hint: '由孩子选活动，家长约定一个专心陪伴的时间。' },
  listen: { name: '先听我说', hint: '先问孩子需要分享、安慰，还是一起想办法。' },
  reconnect: { name: '吵架后的重连', hint: '双方说出感受与期待，慢慢修复。' },
  meeting: { name: '家庭小会议', hint: '双方提出想法，试行一个小改变，一周后复盘。' },
};
const entryLabels: Record<ConnectionEntryType, string> = {
  message: '想说的话', feeling: '我的感受', hope: '我的期待', proposal: '我的提议', reflection: '复盘',
};
const statusLabels: Record<string, string> = { open: '待交流', scheduled: '已约时间', trial: '试行中', completed: '已完成', cancelled: '已取消' };

export default function FamilyConnections() {
  const [children, setChildren] = useState<Child[]>([]);
  const [data, setData] = useState<ConnectionsPayload>({ threads: [], entries: [] });
  const [childId, setChildId] = useState(0);
  const [kind, setKind] = useState<ConnectionKind>('special_time');
  const [intent, setIntent] = useState('share');
  const [title, setTitle] = useState('');
  const [drafts, setDrafts] = useState<Record<number, string>>({});
  const [entryTypes, setEntryTypes] = useState<Record<number, ConnectionEntryType>>({});
  const [dates, setDates] = useState<Record<number, string>>({});
  const [plans, setPlans] = useState<Record<number, string>>({});
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const createId = useRef(crypto.randomUUID());
  const entryIds = useRef<Record<number, string>>({});
  const busyRef = useRef(false);
  const refreshSerial = useRef(0);

  const refresh = useCallback(async (includeChildren = false) => {
    if (busyRef.current) return;
    const serial = ++refreshSerial.current;
    try {
      const [result, payload] = await Promise.all([
        includeChildren ? getChildren({ ownedOnly: true }) : Promise.resolve(null),
        getFamilyConnections(),
      ]);
      if (serial !== refreshSerial.current || busyRef.current) return;
      if (result !== null) {
        const list = (Array.isArray(result) ? result : result?.data || []) as Child[];
        setChildren(list);
        setChildId(current => list.some(child => child.id === current) ? current : list[0]?.id || 0);
      }
      setData(payload);
      setError('');
    } catch (e) {
      if (serial === refreshSerial.current) setError(e instanceof Error ? e.message : '刷新失败，请重试');
    }
  }, []);
  useEffect(() => {
    const serial = refreshSerial;
    void refresh(true);
    const refreshWhenVisible = () => { if (!document.hidden) void refresh(); };
    document.addEventListener('visibilitychange', refreshWhenVisible);
    window.addEventListener('focus', refreshWhenVisible);
    const timer = window.setInterval(refreshWhenVisible, 20_000);
    return () => {
      window.clearInterval(timer);
      document.removeEventListener('visibilitychange', refreshWhenVisible);
      window.removeEventListener('focus', refreshWhenVisible);
      serial.current++;
    };
  }, [refresh]);

  const act = async (action: () => Promise<ConnectionsPayload>, done?: () => void) => {
    busyRef.current = true;
    refreshSerial.current++;
    setBusy(true); setError('');
    try { const payload = await action(); refreshSerial.current++; setData(payload); done?.(); }
    catch (e) { setError(e instanceof Error ? e.message : '操作失败，请重试'); }
    finally { busyRef.current = false; setBusy(false); }
  };
  return <div className="mx-auto max-w-4xl space-y-5 p-4 pb-24 sm:p-6">
    <header><h2 className="text-2xl font-bold">💛 亲子互动</h2><p className="text-sm text-gray-600">把倾听、陪伴和修复留在家庭里。这些记录不计积分，也不评分。</p></header>
    {error && <p role="alert" className="rounded-lg bg-red-50 p-3 text-red-700">{error}</p>}
    <section className="rounded-2xl bg-white p-5 shadow-sm space-y-3">
      <h3 className="font-semibold">开始一段互动</h3>
      <div className="grid gap-3 sm:grid-cols-2">
        <select aria-label="选择孩子" className="rounded-lg border p-2" value={childId} onChange={e => setChildId(Number(e.target.value))}>{children.map(child => <option key={child.id} value={child.id}>{child.name}</option>)}</select>
        <select aria-label="互动方式" className="rounded-lg border p-2" value={kind} onChange={e => { setKind(e.target.value as ConnectionKind); createId.current = crypto.randomUUID(); }}>
          {Object.entries(kinds).map(([code, item]) => <option key={code} value={code}>{item.name}</option>)}
        </select>
      </div>
      <p className="text-sm text-gray-500">{kinds[kind].hint}</p>
      {kind === 'listen' && <select aria-label="孩子希望怎样被倾听" className="w-full rounded-lg border p-2" value={intent} onChange={e => setIntent(e.target.value)}><option value="share">只想说说</option><option value="comfort">想要安慰</option><option value="ideas">一起想办法</option></select>}
      <input className="w-full rounded-lg border p-2" maxLength={160} value={title} onChange={e => { setTitle(e.target.value); createId.current = crypto.randomUUID(); }} placeholder="写个主题，例如：周末一起做早餐" aria-label="互动主题" />
      <button disabled={busy || !childId || title.trim().length < 2} className="rounded-lg bg-rose-700 px-4 py-2 text-white disabled:opacity-50" onClick={() => act(() => createFamilyConnection({ childId, kind, title: title.trim(), intent: kind === 'listen' ? intent : '', requestId: createId.current }), () => { setTitle(''); createId.current = crypto.randomUUID(); })}>发起互动</button>
    </section>
    <section className="space-y-4" aria-label="互动记录">
      {data.threads.length === 0 && <p className="text-gray-500">还没有互动记录。孩子也可以从手表发起。</p>}
      {data.threads.map(thread => {
        const entries = data.entries.filter(entry => entry.connectionId === thread.id);
        const entryType = entryTypes[thread.id] || (thread.kind === 'meeting' ? 'proposal' : thread.kind === 'reconnect' ? 'feeling' : 'message');
        const active = !['completed', 'cancelled'].includes(thread.status);
        return <article key={thread.id} className="rounded-2xl bg-white p-5 shadow-sm space-y-3">
          <div className="flex flex-wrap justify-between gap-2"><div><h3 className="font-semibold">{kinds[thread.kind].name} · {thread.childName}</h3><p className="text-sm text-gray-700">{thread.title}</p></div><span className="text-sm text-rose-700">{statusLabels[thread.status]}</span></div>
          {thread.kind === 'listen' && <p className="text-sm text-gray-600">孩子希望：{{ share: '只想说说', comfort: '获得安慰', ideas: '一起想办法' }[thread.intent] || '先听听'}</p>}
          {thread.scheduledAt && <p className="text-sm">约定时间：{new Date(thread.scheduledAt).toLocaleString('zh-CN')}</p>}
          {thread.trialPlan && <p className="rounded-lg bg-amber-50 p-3 text-sm">本周试行：{thread.trialPlan} · {thread.reviewAt && `复盘时间 ${new Date(thread.reviewAt).toLocaleDateString('zh-CN')}`}</p>}
          {entries.map(entry => <div key={entry.id} className="rounded-lg bg-gray-50 p-3 text-sm"><b>{entry.authorRole === 'child' ? '孩子' : '家长'} · {entryLabels[entry.type]}</b><p className="mt-1 whitespace-pre-wrap">{entry.content}</p></div>)}
          {active && <>
            <div className="flex flex-col gap-2 sm:flex-row"><select aria-label="记录类型" className="rounded-lg border p-2" value={entryType} onChange={e => setEntryTypes(current => ({ ...current, [thread.id]: e.target.value as ConnectionEntryType }))}>
              {(['message', ...(thread.kind === 'reconnect' ? ['feeling', 'hope'] : []), ...(thread.kind === 'meeting' ? ['proposal'] : []), ...(thread.status === 'trial' || thread.kind === 'special_time' ? ['reflection'] : [])] as ConnectionEntryType[]).map(type => <option key={type} value={type}>{entryLabels[type]}</option>)}
            </select><input aria-label="写下内容" className="min-w-0 flex-1 rounded-lg border p-2" maxLength={500} value={drafts[thread.id] || ''} onChange={e => { setDrafts(current => ({ ...current, [thread.id]: e.target.value })); entryIds.current[thread.id] = crypto.randomUUID(); }} placeholder="温和地写下你想表达的内容" />
              <button disabled={busy || (drafts[thread.id] || '').trim().length < 2} className="rounded-lg bg-rose-100 px-3 py-2 text-rose-800 disabled:opacity-50" onClick={() => act(() => addFamilyConnectionEntry(thread.id, { type: entryType, content: drafts[thread.id].trim(), requestId: entryIds.current[thread.id] ||= crypto.randomUUID() }), () => { setDrafts(current => ({ ...current, [thread.id]: '' })); entryIds.current[thread.id] = crypto.randomUUID(); })}>发送</button></div>
            {thread.kind === 'special_time' && thread.status === 'open' && <div className="flex flex-col gap-2 sm:flex-row"><input aria-label="约定陪伴时间" type="datetime-local" className="min-w-0 rounded-lg border p-2" value={dates[thread.id] || ''} onChange={e => setDates(current => ({ ...current, [thread.id]: e.target.value }))} /><button disabled={busy || !dates[thread.id]} onClick={() => act(() => transitionFamilyConnection(thread.id, { action: 'schedule', scheduledAt: new Date(dates[thread.id]).toISOString() }))} className="px-2 py-2 text-rose-700">约定时间</button></div>}
            {thread.kind === 'meeting' && thread.status === 'open' && <div className="flex flex-col gap-2 sm:flex-row"><input aria-label="一周试行安排" maxLength={500} className="min-w-0 flex-1 rounded-lg border p-2" placeholder="双方各提一个想法后，写下本周试行安排" value={plans[thread.id] || ''} onChange={e => setPlans(current => ({ ...current, [thread.id]: e.target.value }))}/><button disabled={busy || (plans[thread.id] || '').trim().length < 2} onClick={() => act(() => transitionFamilyConnection(thread.id, { action: 'start_trial', plan: plans[thread.id].trim() }))} className="px-2 py-2 text-rose-700">开始试行</button></div>}
            <div className="flex gap-4 text-sm">
              {(thread.kind === 'meeting' ? thread.status === 'trial' : thread.kind === 'special_time' ? thread.status === 'scheduled' : thread.status === 'open') && <button disabled={busy} className="text-rose-700" onClick={() => act(() => transitionFamilyConnection(thread.id, { action: thread.kind === 'meeting' ? 'review' : 'complete' }))}>{thread.kind === 'meeting' ? '七天后完成复盘' : '完成互动'}</button>}
              <button disabled={busy} className="text-gray-500" onClick={() => act(() => transitionFamilyConnection(thread.id, { action: 'cancel' }))}>取消</button>
            </div>
          </>}
        </article>;
      })}
    </section>
    <div className="flex items-center gap-3 text-sm"><button className="text-rose-700" onClick={() => void refresh(true)}>刷新互动记录</button><span className="text-gray-500">页面打开时自动更新</span></div>
  </div>;
}
