import { useEffect, useMemo, useRef, useState } from 'react';
import { getMyFeedback, submitFeedback } from '../services';
import type { FeedbackItem, FeedbackSubmission } from '../types';

const statusLabels: Record<string, string> = {
  pending: '待跟进',
  scheduled: '待调度',
  processing: '处理中',
  pending_release: '待发布复测',
  released_verifying: '生产复测中',
  reviewed: '已解决',
  rejected: '已驳回',
  converted: '已转化',
};

const typeLabels: Record<string, string> = {
  suggestion: '建议',
  defect: '问题',
  question: '咨询',
};

function createRecordId() {
  if (typeof crypto !== 'undefined' && crypto.randomUUID) return crypto.randomUUID();
  return `feedback-${Date.now()}-${Math.random().toString(16).slice(2)}`;
}

function sanitizedLocation() {
  const url = new URL(window.location.href);
  ['token', 'code', 'auth', 'key', 'password', 'secret'].forEach((name) => url.searchParams.delete(name));
  return url.toString();
}

function collectSource(): FeedbackSubmission['source'] {
  return {
    url: sanitizedLocation(),
    pageTitle: document.title,
    path: `${window.location.pathname}${window.location.search}${window.location.hash}`,
    viewport: `${window.innerWidth}x${window.innerHeight}`,
    userAgent: window.navigator.userAgent,
    capturedAt: new Date().toISOString(),
  };
}

function formatDate(value?: string) {
  if (!value) return '';
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? '' : parsed.toLocaleString('zh-CN', { dateStyle: 'short', timeStyle: 'short' });
}

export default function FeedbackWidget() {
  const [open, setOpen] = useState(false);
  const [tab, setTab] = useState<'submit' | 'mine'>('submit');
  const [feedbackType, setFeedbackType] = useState<FeedbackSubmission['feedbackType']>('suggestion');
  const [title, setTitle] = useState('');
  const [content, setContent] = useState('');
  const [contact, setContact] = useState('');
  const [recordId, setRecordId] = useState(createRecordId);
  const [items, setItems] = useState<FeedbackItem[]>([]);
  const [loading, setLoading] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [message, setMessage] = useState('');
  const titleRef = useRef<HTMLInputElement>(null);
  const triggerRef = useRef<HTMLButtonElement>(null);
  const source = useMemo(() => open ? collectSource() : null, [open]);

  useEffect(() => {
    if (!open) return;
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape') setOpen(false);
    };
    document.addEventListener('keydown', onKeyDown);
    window.setTimeout(() => titleRef.current?.focus(), 0);
    return () => document.removeEventListener('keydown', onKeyDown);
  }, [open]);

  useEffect(() => {
    if (open || !triggerRef.current) return;
    triggerRef.current.focus({ preventScroll: true });
  }, [open]);

  const loadMine = async () => {
    try {
      setLoading(true);
      setMessage('');
      const result = await getMyFeedback();
      setItems(Array.isArray(result) ? result : []);
    } catch (error) {
      setMessage(error instanceof Error ? error.message : '反馈记录加载失败');
    } finally {
      setLoading(false);
    }
  };

  const switchTab = (next: 'submit' | 'mine') => {
    setTab(next);
    setMessage('');
    if (next === 'mine') void loadMine();
  };

  const handleSubmit = async (event: React.FormEvent) => {
    event.preventDefault();
    if (!source || submitting) return;
    if (!title.trim() || !content.trim()) {
      setMessage('请填写标题和反馈内容');
      return;
    }
    try {
      setSubmitting(true);
      setMessage('');
      const result = await submitFeedback({
        feedbackType,
        title: title.trim(),
        content: content.trim(),
        submitterContact: contact.trim(),
        sourceRecordId: recordId,
        source,
      });
      const feedbackId = result.id || result.Id || '';
      setMessage(feedbackId ? `已提交，编号 ${feedbackId}` : '已提交');
      setTitle('');
      setContent('');
      setRecordId(createRecordId());
    } catch (error) {
      setMessage(error instanceof Error ? error.message : '提交失败，请稍后重试');
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <>
      <button
        ref={triggerRef}
        type="button"
        onClick={() => setOpen(true)}
        className="fixed bottom-20 right-3 z-40 grid h-11 w-11 place-items-center rounded-full bg-gray-900 text-lg text-white shadow-lg hover:bg-black lg:bottom-5 lg:right-5"
        aria-label="问题反馈"
        title="问题反馈"
      >
        ?
      </button>
      {open && (
        <div className="fixed inset-0 z-[80] flex items-end justify-center bg-black/35 p-0 sm:items-center sm:p-4" onMouseDown={() => setOpen(false)}>
          <section
            role="dialog"
            aria-modal="true"
            aria-label="问题反馈"
            className="flex max-h-[calc(100dvh-4rem)] w-full flex-col rounded-t-lg bg-white shadow-xl sm:max-h-[86vh] sm:max-w-xl sm:rounded-lg"
            onMouseDown={(event) => event.stopPropagation()}
          >
            <header className="flex items-center justify-between border-b border-gray-200 px-4 py-3">
              <h2 className="text-base font-semibold text-gray-900">问题反馈</h2>
              <button type="button" onClick={() => setOpen(false)} className="grid h-8 w-8 place-items-center rounded-md text-xl text-gray-500 hover:bg-gray-100" aria-label="关闭">×</button>
            </header>
            <div className="grid grid-cols-2 border-b border-gray-200 p-1">
              <button type="button" onClick={() => switchTab('submit')} className={`rounded-md px-3 py-2 text-sm font-medium ${tab === 'submit' ? 'bg-gray-900 text-white' : 'text-gray-600'}`}>提交反馈</button>
              <button type="button" onClick={() => switchTab('mine')} className={`rounded-md px-3 py-2 text-sm font-medium ${tab === 'mine' ? 'bg-gray-900 text-white' : 'text-gray-600'}`}>我的反馈</button>
            </div>
            <div className="overflow-y-auto p-4">
              {message && <div aria-live="polite" className="mb-3 rounded-md bg-blue-50 px-3 py-2 text-sm text-blue-700">{message}</div>}
              {tab === 'submit' ? (
                <form onSubmit={handleSubmit} className="space-y-4">
                  <div className="grid grid-cols-3 gap-2">
                    {(['suggestion', 'defect', 'question'] as const).map((value) => (
                      <button key={value} type="button" onClick={() => setFeedbackType(value)} className={`rounded-md border px-2 py-2 text-sm ${feedbackType === value ? 'border-gray-900 bg-gray-900 text-white' : 'border-gray-300 text-gray-600'}`}>{typeLabels[value]}</button>
                    ))}
                  </div>
                  <label className="block text-sm font-medium text-gray-700">标题
                    <input ref={titleRef} value={title} onChange={(event) => setTitle(event.target.value)} maxLength={200} className="mt-1 w-full rounded-md border border-gray-300 px-3 py-2 focus:border-[#4A90D9] focus:outline-none" />
                  </label>
                  <label className="block text-sm font-medium text-gray-700">反馈内容
                    <textarea value={content} onChange={(event) => setContent(event.target.value)} maxLength={5000} rows={5} className="mt-1 w-full resize-y rounded-md border border-gray-300 px-3 py-2 focus:border-[#4A90D9] focus:outline-none" />
                  </label>
                  <label className="block text-sm font-medium text-gray-700">联系方式（可选）
                    <input value={contact} onChange={(event) => setContact(event.target.value)} maxLength={160} className="mt-1 w-full rounded-md border border-gray-300 px-3 py-2 focus:border-[#4A90D9] focus:outline-none" />
                  </label>
                  <details className="text-xs text-gray-500">
                    <summary className="cursor-pointer">页面信息</summary>
                    <pre className="mt-2 whitespace-pre-wrap break-all rounded-md bg-gray-50 p-2">{source ? `${source.pageTitle}\n${source.url}\n${source.viewport}\n${source.capturedAt}` : ''}</pre>
                  </details>
                  <button type="submit" disabled={submitting} className="w-full rounded-md bg-[#4A90D9] px-4 py-2.5 text-sm font-medium text-white disabled:opacity-60">{submitting ? '提交中...' : '提交'}</button>
                </form>
              ) : loading ? (
                <div className="py-12 text-center text-sm text-gray-400">加载中...</div>
              ) : items.length === 0 ? (
                <div className="py-12 text-center text-sm text-gray-400">暂无反馈记录</div>
              ) : (
                <div className="divide-y divide-gray-100">
                  {items.map((item) => (
                    <article key={item.id || item.Id} className="py-3 first:pt-0">
                      <div className="flex items-start justify-between gap-3">
                        <div className="min-w-0"><span className="text-xs text-gray-400">{typeLabels[item.feedback_type] || item.feedback_type}</span><h3 className="truncate text-sm font-semibold text-gray-900">{item.title}</h3></div>
                        <span className="shrink-0 rounded-full bg-gray-100 px-2 py-1 text-xs text-gray-600">{statusLabels[item.status] || item.status}</span>
                      </div>
                      {item.reply_content && <p className="mt-2 rounded-md bg-green-50 px-3 py-2 text-sm text-green-800">{item.reply_content}</p>}
                      <time className="mt-2 block text-xs text-gray-400">{formatDate(item.updatedat || item.createdat)}</time>
                    </article>
                  ))}
                </div>
              )}
            </div>
          </section>
        </div>
      )}
    </>
  );
}
