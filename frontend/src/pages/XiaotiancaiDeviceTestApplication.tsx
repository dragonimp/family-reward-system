import { useCallback, useEffect, useState } from 'react';
import {
  getXiaotiancaiDeviceTestApplication,
  sendXiaotiancaiDeviceTestApplication,
} from '../services';
import type {
  XiaotiancaiDeviceTestEmailPreview,
  XiaotiancaiDeviceTestEmailSubmission,
} from '../types';

const statusText: Record<XiaotiancaiDeviceTestEmailSubmission['status'], string> = {
  sending: '发送中',
  sent: '已发送',
  failed: '发送失败',
};

const statusClass: Record<XiaotiancaiDeviceTestEmailSubmission['status'], string> = {
  sending: 'bg-amber-50 text-amber-700',
  sent: 'bg-emerald-50 text-emerald-700',
  failed: 'bg-red-50 text-red-700',
};

function formatDate(value?: string | null) {
  if (!value) return '-';
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? value : date.toLocaleString('zh-CN');
}

export default function XiaotiancaiDeviceTestApplication() {
  const [preview, setPreview] = useState<XiaotiancaiDeviceTestEmailPreview | null>(null);
  const [deviceModel, setDeviceModel] = useState('Z8A');
  const [confirmed, setConfirmed] = useState(false);
  const [loading, setLoading] = useState(true);
  const [sending, setSending] = useState(false);
  const [error, setError] = useState('');
  const [success, setSuccess] = useState('');

  const loadPreview = useCallback(async () => {
    setLoading(true);
    setError('');
    try {
      const next = await getXiaotiancaiDeviceTestApplication();
      setPreview(next);
      setDeviceModel(next.deviceModel || 'Z8A');
    } catch (loadError) {
      setError(loadError instanceof Error ? loadError.message : '读取申请材料失败');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void loadPreview();
  }, [loadPreview]);

  const sendApplication = async () => {
    if (!preview || !confirmed || sending) return;
    if (!window.confirm(`确认从 ${preview.sender} 向 ${preview.recipient} 发送 ${deviceModel} 真机测试申请？`)) return;
    setSending(true);
    setError('');
    setSuccess('');
    try {
      const result = await sendXiaotiancaiDeviceTestApplication({
        deviceModel,
        confirmed: true,
        expectedApkSha256: preview.apkSha256,
        expectedReportSha256: preview.reportSha256,
      });
      setSuccess(`发送成功，Message-ID：${result.messageId || '-'}`);
      setConfirmed(false);
      await loadPreview();
    } catch (sendError) {
      setError(sendError instanceof Error ? sendError.message : '发送失败');
    } finally {
      setSending(false);
    }
  };

  if (loading) {
    return <div className="py-16 text-center text-gray-500">正在校验最新发布材料和邮箱凭证...</div>;
  }

  if (!preview) {
    return (
      <div className="mx-auto max-w-3xl rounded-xl border border-red-200 bg-red-50 p-5 text-red-700">
        <h2 className="text-lg font-semibold">无法打开小天才真机测试申请</h2>
        <p className="mt-2 text-sm">{error || '申请功能暂不可用'}</p>
        <button type="button" onClick={() => void loadPreview()} className="mt-4 rounded-lg bg-red-600 px-4 py-2 text-sm text-white">
          重新检查
        </button>
      </div>
    );
  }

  const canSend = preview.sendingConfigured && preview.credentialReady && confirmed && !sending;

  return (
    <div className="mx-auto max-w-5xl space-y-5 pb-8">
      <header>
        <h2 className="text-xl font-bold text-gray-900 sm:text-2xl">小天才真机测试申请</h2>
        <p className="mt-1 text-sm text-gray-500">校验当前正式发布材料，通过用户中心受限凭证发送并保存邮件回执。</p>
      </header>

      {error && <div className="rounded-lg border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700">{error}</div>}
      {success && <div className="rounded-lg border border-emerald-200 bg-emerald-50 px-4 py-3 text-sm text-emerald-700">{success}</div>}

      <section className="rounded-xl border border-gray-200 bg-white p-4 shadow-sm sm:p-5">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div>
            <h3 className="font-semibold text-gray-900">发送准备</h3>
            <p className="mt-1 text-xs text-gray-500">操作人：{preview.requestedBy}</p>
          </div>
          <div className="flex gap-2 text-xs">
            <span className={`rounded-full px-3 py-1 ${preview.sendingConfigured ? 'bg-emerald-50 text-emerald-700' : 'bg-red-50 text-red-700'}`}>
              发送配置{preview.sendingConfigured ? '正常' : '缺失'}
            </span>
            <span className={`rounded-full px-3 py-1 ${preview.credentialReady ? 'bg-emerald-50 text-emerald-700' : 'bg-red-50 text-red-700'}`}>
              邮箱凭证{preview.credentialReady ? '可用' : '不可用'}
            </span>
          </div>
        </div>
        <div className="mt-4 grid grid-cols-1 gap-4 sm:grid-cols-2">
          <label className="text-sm text-gray-700">
            目标机型
            <input
              value={deviceModel}
              onChange={(event) => {
                setDeviceModel(event.target.value.toUpperCase());
                setConfirmed(false);
              }}
              maxLength={20}
              className="mt-1 w-full rounded-lg border border-gray-300 px-3 py-2"
            />
          </label>
          <div className="text-sm text-gray-700">
            当前版本
            <div className="mt-1 rounded-lg border border-gray-200 bg-gray-50 px-3 py-2">
              {preview.versionName} / versionCode {preview.versionCode}
            </div>
          </div>
          <div className="text-sm text-gray-700">
            发件人
            <div className="mt-1 rounded-lg border border-gray-200 bg-gray-50 px-3 py-2 break-all">{preview.sender}</div>
          </div>
          <div className="text-sm text-gray-700">
            收件人
            <div className="mt-1 rounded-lg border border-gray-200 bg-gray-50 px-3 py-2 break-all">{preview.recipient}</div>
          </div>
        </div>
      </section>

      <section className="rounded-xl border border-gray-200 bg-white p-4 shadow-sm sm:p-5">
        <h3 className="font-semibold text-gray-900">邮件预览</h3>
        <div className="mt-3 text-sm text-gray-700">
          <div className="font-medium">主题</div>
          <div className="mt-1 rounded-lg border border-gray-200 bg-gray-50 px-3 py-2">{preview.subject}</div>
        </div>
        <div className="mt-3 text-sm text-gray-700">
          <div className="font-medium">正文</div>
          <pre className="mt-1 max-h-96 overflow-auto whitespace-pre-wrap rounded-lg border border-gray-200 bg-gray-50 p-3 font-sans text-xs leading-6 text-gray-700">
            {preview.body.split('Z8A').join(deviceModel || 'Z8A')}
          </pre>
        </div>
        {preview.previousMessageId && (
          <p className="mt-3 break-all text-xs text-gray-500">回复线程：{preview.previousMessageId}</p>
        )}
      </section>

      <section className="rounded-xl border border-gray-200 bg-white p-4 shadow-sm sm:p-5">
        <h3 className="font-semibold text-gray-900">附件与校验值</h3>
        <div className="mt-3 space-y-3">
          {preview.attachments.map((attachment) => (
            <div key={attachment.fileName} className="rounded-lg border border-gray-200 p-3 text-sm">
              <div className="font-medium text-gray-800">{attachment.fileName}</div>
              <div className="mt-1 text-xs text-gray-500">{attachment.sizeBytes.toLocaleString()} 字节 · {attachment.contentType}</div>
              <div className="mt-1 break-all font-mono text-xs text-gray-600">SHA-256：{attachment.sha256}</div>
            </div>
          ))}
        </div>
        <label className="mt-4 flex items-start gap-3 rounded-lg bg-amber-50 p-3 text-sm text-amber-900">
          <input
            type="checkbox"
            checked={confirmed}
            onChange={(event) => setConfirmed(event.target.checked)}
            className="mt-0.5"
          />
          <span>我已核对目标机型、收件人、邮件正文及上述附件哈希，确认发送真实外部邮件。</span>
        </label>
        <button
          type="button"
          disabled={!canSend}
          onClick={() => void sendApplication()}
          className="mt-4 w-full rounded-lg bg-[#4A90D9] px-4 py-3 font-medium text-white disabled:cursor-not-allowed disabled:opacity-50 sm:w-auto"
        >
          {sending ? '正在发送...' : preview.previousMessageId ? '按原线程重新发送' : '发送真机测试申请'}
        </button>
      </section>

      <section className="rounded-xl border border-gray-200 bg-white p-4 shadow-sm sm:p-5">
        <h3 className="font-semibold text-gray-900">发送记录</h3>
        {preview.submissions.length === 0 ? (
          <p className="mt-3 text-sm text-gray-500">功能上线后尚无发送记录；已有历史 Message-ID 将继续用于邮件线程。</p>
        ) : (
          <div className="mt-3 space-y-3">
            {preview.submissions.map((submission) => (
              <article key={submission.id} className="rounded-lg border border-gray-200 p-3 text-sm">
                <div className="flex flex-wrap items-center justify-between gap-2">
                  <span className="font-medium text-gray-800">{submission.deviceModel} · {submission.versionName} ({submission.versionCode})</span>
                  <span className={`rounded-full px-2.5 py-1 text-xs ${statusClass[submission.status]}`}>{statusText[submission.status]}</span>
                </div>
                <div className="mt-2 text-xs text-gray-500">{formatDate(submission.sentAt || submission.createdAt)} · {submission.requestedBy}</div>
                {submission.messageId && <div className="mt-1 break-all font-mono text-xs text-gray-600">{submission.messageId}</div>}
                {submission.errorMessage && <div className="mt-2 text-xs text-red-600">{submission.errorMessage}</div>}
              </article>
            ))}
          </div>
        )}
      </section>
    </div>
  );
}
