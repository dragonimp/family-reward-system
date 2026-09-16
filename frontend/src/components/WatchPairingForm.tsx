import { useState } from 'react';
import type { Child } from '../types';
import { pairChildWatchDevice } from '../services';

export default function WatchPairingForm({ children, initialCode = '', fixedChild, onBound }: {
  children: Child[];
  initialCode?: string;
  fixedChild?: Child;
  onBound?: () => void;
}) {
  const [code, setCode] = useState(initialCode);
  const [childId, setChildId] = useState(fixedChild ? String(fixedChild.id) : '');
  const [busy, setBusy] = useState(false);
  const [done, setDone] = useState(false);
  const [error, setError] = useState('');
  const normalized = code.replace(/[\s-]/g, '').toUpperCase();
  const child = fixedChild ?? children.find(item => String(item.id) === childId);
  const bind = async () => {
    if (!child || busy || done) return;
    setBusy(true);
    setError('');
    try {
      await pairChildWatchDevice(child.id, normalized);
      setDone(true);
      onBound?.();
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : '绑定失败，请重试');
    } finally { setBusy(false); }
  };
  return (
    <section className="space-y-3 rounded-lg border border-blue-200 bg-blue-50 p-4" aria-label="添加手表">
      <h3 className="font-semibold text-gray-900">添加手表</h3>
      <p className="text-sm text-gray-600">用手机相机扫描手表二维码，或输入手表显示的 8 位设备码，再确认绑定的孩子。</p>
      <label className="block text-sm text-gray-700">
        手表设备码
        <input value={code} maxLength={12} autoCapitalize="characters" autoComplete="off" spellCheck={false}
          onChange={event => { setCode(event.target.value); setDone(false); setError(''); }}
          disabled={busy} placeholder="例如 ABCD 2345"
          className="mt-1 block w-full rounded-lg border border-gray-300 bg-white px-3 py-2 font-mono uppercase tracking-widest" />
      </label>
      {!fixedChild && <label className="block text-sm text-gray-700">
        绑定给哪个孩子
        <select value={childId} disabled={busy} onChange={event => { setChildId(event.target.value); setDone(false); setError(''); }}
          className="mt-1 block w-full rounded-lg border border-gray-300 bg-white px-3 py-2">
          <option value="">请选择孩子</option>
          {children.map(item => <option key={item.id} value={item.id}>{item.name}</option>)}
        </select>
      </label>}
      {done ? <p role="status" className="text-sm font-medium text-green-700">已绑定给{child?.name}，手表联网后会自动进入首页。</p>
        : <button type="button" className="btn-primary" onClick={bind}
          disabled={busy || !child || !/^[A-HJ-NP-Z2-9]{8}$/.test(normalized)}>
          {busy ? '正在绑定…' : child ? `确认绑定给${child.name}` : '确认绑定'}
        </button>}
      {error && <p role="alert" className="text-sm text-red-700">{error}</p>}
    </section>
  );
}
