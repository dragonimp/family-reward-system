import { useEffect, useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import { acceptGenealogyInvitation, getGenealogyInvitation, type GenealogyInvitation } from '../services';

export default function GenealogyInvitationPage() {
  const { token = '' } = useParams();
  const [invitation, setInvitation] = useState<GenealogyInvitation | null>(null);
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  const [accepted, setAccepted] = useState(false);

  useEffect(() => {
    let active = true;
    getGenealogyInvitation(token).then((result) => { if (active) setInvitation(result); })
      .catch((reason: unknown) => { if (active) setError(reason instanceof Error ? reason.message : '邀请读取失败'); });
    return () => { active = false; };
  }, [token]);

  const accept = async () => {
    setBusy(true);
    setError('');
    try {
      await acceptGenealogyInvitation(token);
      setAccepted(true);
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : '接受邀请失败');
    } finally { setBusy(false); }
  };

  return <main className="mx-auto max-w-lg p-6 pt-16">
    <section className="rounded-2xl border border-emerald-100 bg-white p-6 shadow-sm">
      <h1 className="text-2xl font-bold text-gray-900">加入家族族谱</h1>
      {error && <p role="alert" className="mt-4 rounded-lg bg-red-50 p-3 text-red-700">{error}</p>}
      {!invitation && !error && <p className="mt-4 text-gray-600">正在读取邀请…</p>}
      {invitation && <>
        <p className="mt-4 text-gray-700">你受邀加入「{invitation.treeName}」，并绑定人物「{invitation.personName}」。</p>
        <p className="mt-2 text-sm text-gray-500">确认前请核对当前登录的用户中心账号。接受后，该账号会自动成为族谱成员并关联上述人物。</p>
        {accepted ? <p role="status" className="mt-5 text-emerald-700">已加入并完成绑定。<Link className="ml-2 underline" to="/genealogy">查看族谱</Link></p>
          : invitation.available ? <button type="button" disabled={busy} onClick={() => void accept()} className="mt-5 rounded-lg bg-emerald-600 px-5 py-2 text-white disabled:opacity-50">{busy ? '正在加入…' : '确认加入并绑定'}</button>
            : <p className="mt-5 text-amber-700">此链接已过期、被替换或已使用，请联系族谱管理员重新邀请。</p>}
      </>}
    </section>
  </main>;
}
