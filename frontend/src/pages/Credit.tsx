import { useCallback, useEffect, useRef, useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import type { Child, CreditDetail } from '../types';
import {
  adjustChildCredit, createCreditCommitment, enableChildCredit, getChildCredit, getChildren,
  resolveCreditCommitment, resolveCreditDispute, reverseCreditEvent,
} from '../services';

const labels: Record<string, string> = {
  open: '进行中', pending: '等待家长确认', overdue: '已确认逾期', late_pending: '补救完成待确认', completed: '已完成',
  opened: '开通信用分', commitment_completed: '按时守约', commitment_remedied: '主动补救', commitment_overdue: '约定逾期',
  honesty: '诚实说明', responsibility: '承担责任', false_report: '虚报完成', adjustment: '家长调整', reversal: '撤销记录',
};

export default function Credit() {
  const { childId } = useParams();
  const id = Number(childId);
  const [child, setChild] = useState<Child | null>(null);
  const [detail, setDetail] = useState<CreditDetail | null>(null);
  const [title, setTitle] = useState('');
  const [dueAt, setDueAt] = useState('');
  const [reasonCode, setReasonCode] = useState('honesty');
  const [delta, setDelta] = useState(1);
  const [note, setNote] = useState('');
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  const commitmentRequestId = useRef(crypto.randomUUID());
  const adjustmentRequestId = useRef(crypto.randomUUID());

  const refresh = useCallback(async () => {
    if (!Number.isInteger(id) || id < 1) return;
    const [children, credit] = await Promise.all([getChildren({ ownedOnly: true }), getChildCredit(id)]);
    const owned = (Array.isArray(children) ? children : children.data || []) as Child[];
    setChild(owned.find(item => item.id === id) || null);
    setDetail(credit);
  }, [id]);

  useEffect(() => { refresh().catch(() => setError('信用分加载失败，请刷新重试')); }, [refresh]);

  const perform = async (action: () => Promise<CreditDetail>) => {
    setBusy(true); setError('');
    try { setDetail(await action()); }
    catch (failure) { setError(failure instanceof Error ? failure.message : '操作失败，请重试'); }
    finally { setBusy(false); }
  };

  if (!child) return <div className="p-6"><Link to="/children" className="text-blue-700">返回孩子列表</Link><p className="mt-4">{error || '正在加载孩子资料…'}</p></div>;

  return <div className="mx-auto max-w-4xl space-y-5 p-4 pb-24 sm:p-6">
    <Link to="/children" className="text-sm text-blue-700">← 返回孩子列表</Link>
    <header className="rounded-2xl bg-emerald-50 p-5">
      <h2 className="text-xl font-bold text-emerald-950">{child.name}的信用分</h2>
      <p className="mt-1 text-sm text-emerald-800">记录守约和责任行为，与可兑换积分分别计算。</p>
      <div className="mt-4 text-4xl font-bold text-emerald-700">{detail?.enabled ? detail.score : '未开通'}{detail?.enabled && <span className="ml-1 text-base font-normal">/ 100</span>}</div>
      {detail?.enabled && detail.score !== null && detail.score < 60 && <p className="mt-2 text-sm">可以一起商量一项容易完成的新约定。</p>}
      {detail && !detail.enabled && <button disabled={busy} onClick={() => perform(() => enableChildCredit(id))} className="mt-4 rounded-lg bg-emerald-700 px-4 py-2 text-white disabled:opacity-50">开通信用分，从 80 分开始</button>}
    </header>
    {error && <p role="alert" className="rounded-lg bg-red-50 p-3 text-red-700">{error}</p>}
    {detail?.enabled && <>
      <section className="rounded-2xl bg-white p-5 shadow-sm">
        <h3 className="font-semibold">新建约定</h3>
        <div className="mt-3 grid gap-3 sm:grid-cols-[1fr_auto_auto]">
          <input value={title} onChange={event => { setTitle(event.target.value); commitmentRequestId.current = crypto.randomUUID(); }} maxLength={160} placeholder="例如：周五前整理书桌" aria-label="约定内容" className="rounded-lg border p-2" />
          <input type="datetime-local" value={dueAt} onChange={event => { setDueAt(event.target.value); commitmentRequestId.current = crypto.randomUUID(); }} aria-label="截止时间" className="rounded-lg border p-2" />
          <button disabled={busy || title.trim().length < 2 || !dueAt} onClick={() => perform(async () => {
            const result = await createCreditCommitment(id, { title: title.trim(), dueAt: new Date(dueAt).toISOString(), requestId: commitmentRequestId.current });
            setTitle(''); setDueAt(''); commitmentRequestId.current = crypto.randomUUID(); return result;
          })} className="rounded-lg bg-emerald-700 px-4 py-2 text-white disabled:opacity-50">保存约定</button>
        </div>
      </section>
      <section className="rounded-2xl bg-white p-5 shadow-sm">
        <h3 className="font-semibold">约定</h3>
        {detail.commitments.length === 0 && <p className="mt-3 text-sm text-gray-500">还没有约定。</p>}
        <div className="mt-3 space-y-3">{detail.commitments.map(item => <div key={item.id} className="rounded-xl border p-3">
          <div className="flex flex-wrap items-start justify-between gap-2"><b>{item.title}</b><span className="text-sm text-gray-600">{labels[item.status]}</span></div>
          <p className="mt-1 text-sm text-gray-500">截止：{new Date(item.dueAt).toLocaleString('zh-CN')}</p>
          {(item.status === 'open' || item.status === 'pending' || item.status === 'late_pending') && <div className="mt-3 flex flex-wrap gap-2">
            <button disabled={busy} onClick={() => {
              const add = item.status === 'late_pending' || (item.completionRequestedAt && item.completionRequestedAt > item.dueAt) ? 1 : 2;
              if (window.confirm(`确认完成此约定？信用分预计 +${add}，当前 ${detail.score} 分。`)) perform(() => resolveCreditCommitment(id, item.id, { action: 'completed' }));
            }} className="rounded-lg bg-emerald-100 px-3 py-1 text-emerald-800">确认完成</button>
            {new Date(item.dueAt) <= new Date() && item.status !== 'late_pending' && <button disabled={busy} onClick={() => {
              if (window.confirm(`确认约定逾期？信用分预计 -2，当前 ${detail.score} 分。`)) perform(() => resolveCreditCommitment(id, item.id, { action: 'overdue' }));
            }} className="rounded-lg bg-amber-100 px-3 py-1 text-amber-900">确认逾期</button>}
          </div>}
        </div>)}</div>
      </section>
      <section className="rounded-2xl bg-white p-5 shadow-sm">
        <h3 className="font-semibold">家长调整</h3>
        <p className="mt-1 text-sm text-gray-500">同一原因每天一次，手工调整每天最多 10 分。</p>
        <div className="mt-3 grid gap-3 sm:grid-cols-4">
          <select value={reasonCode} onChange={event => { setReasonCode(event.target.value); adjustmentRequestId.current = crypto.randomUUID(); }} aria-label="调整原因" className="rounded-lg border p-2">
            <option value="honesty">诚实说明</option><option value="responsibility">承担责任</option><option value="false_report">虚报完成</option><option value="adjustment">其他调整</option>
          </select>
          <input type="number" min={-5} max={5} value={delta} onChange={event => { setDelta(Number(event.target.value)); adjustmentRequestId.current = crypto.randomUUID(); }} aria-label="分值变化" className="rounded-lg border p-2" />
          <input value={note} onChange={event => { setNote(event.target.value); adjustmentRequestId.current = crypto.randomUUID(); }} maxLength={500} placeholder="说明原因" aria-label="调整说明" className="rounded-lg border p-2" />
          <button disabled={busy} onClick={() => {
            if (window.confirm(`确认信用分 ${delta > 0 ? '+' : ''}${delta}，当前 ${detail.score} 分？`)) perform(async () => {
              const result = await adjustChildCredit(id, { reasonCode, delta, note: note.trim(), requestId: adjustmentRequestId.current });
              setNote(''); adjustmentRequestId.current = crypto.randomUUID(); return result;
            });
          }} className="rounded-lg bg-emerald-700 px-3 py-2 text-white disabled:opacity-50">确认调整</button>
        </div>
      </section>
      <section className="rounded-2xl bg-white p-5 shadow-sm">
        <h3 className="font-semibold">变动记录</h3>
        <div className="mt-3 space-y-3">{detail.events.map(event => <div key={event.id} className="flex flex-wrap items-center justify-between gap-2 border-b pb-3 text-sm">
          <div><b>{labels[event.reasonCode] || event.reasonCode}</b><p className="text-gray-500">{event.note} · {new Date(event.createdAt).toLocaleString('zh-CN')}</p></div>
          <div className="flex items-center gap-3"><b className={event.delta < 0 ? 'text-red-700' : 'text-emerald-700'}>{event.delta > 0 ? '+' : ''}{event.delta}</b>
            {event.reasonCode !== 'opened' && event.reasonCode !== 'reversal' && !detail.events.some(other => other.reversalOfEventId === event.id) && <button disabled={busy} onClick={() => {
              const why = window.prompt('请填写撤销原因（至少 2 字）');
              if (why) perform(() => reverseCreditEvent(id, event.id, why));
            }} className="text-blue-700">撤销</button>}
          </div>
        </div>)}</div>
      </section>
      {detail.disputes.length > 0 && <section className="rounded-2xl bg-white p-5 shadow-sm"><h3 className="font-semibold">孩子的异议</h3>
        <div className="mt-3 space-y-3">{detail.disputes.map(dispute => <div key={dispute.id} className="rounded-xl border p-3 text-sm">
          <p>{dispute.reason}</p><p className="mt-1 text-gray-500">{dispute.status === 'pending' ? '待处理' : dispute.status === 'accepted' ? '已采纳' : '已保留'} {dispute.parentResponse}</p>
          {dispute.status === 'pending' && <div className="mt-2 flex gap-3">{(['accepted', 'rejected'] as const).map(action => <button key={action} disabled={busy} onClick={() => {
            const response = window.prompt(action === 'accepted' ? '写下采纳原因（将撤销原扣分）' : '写下保留扣分的说明');
            if (response) perform(() => resolveCreditDispute(id, dispute.id, { action, response }));
          }} className="text-blue-700">{action === 'accepted' ? '采纳并撤销扣分' : '保留扣分'}</button>)}</div>}
        </div>)}</div>
      </section>}
    </>}
  </div>;
}
