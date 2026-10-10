import { useCallback, useEffect, useRef, useState } from 'react';
import { Link, useNavigate, useParams, useSearchParams } from 'react-router-dom';
import { useAuth } from '../contexts/AuthContext';

type Space = { id: string; name: string; role: string };
type Activity = { id: string; title: string; description: string; createdAt: string; canEdit: boolean };
type Photo = { id: string; sourceDisplayName: string; originalFileName: string; createdAt: string; thumbnailAvailable: boolean };
type Invitation = { id: string; tenantId: string; activityId: string; activityTitle: string; joined: boolean };
type Moment = { id: string; authorName: string; text: string; createdAt: string; canDelete: boolean };
type SocialMember = { subject: string; displayName: string; isSelf: boolean };
type Relationship = { id: string; peerSubject: string; peerName: string; status: 'pending' | 'accepted'; direction: 'incoming' | 'outgoing' };

const gateway = '/api/dear/social/';
async function social<T>(path: string, method = 'GET', body?: object): Promise<T> {
  const response = await fetch(gateway + path, {
    method, credentials: 'include',
    headers: body ? { 'Content-Type': 'application/json' } : undefined,
    body: body ? JSON.stringify(body) : undefined,
  });
  const value = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(value.error || value.message || `Linko Social 请求失败（${response.status}）`);
  return value as T;
}

function DearMoments({ spaceId, activityId }: { spaceId: string; activityId: string }) {
  const path = `tenants/${spaceId}/activities/${activityId}/moments`;
  const [items, setItems] = useState<Moment[]>([]);
  const [draft, setDraft] = useState('');
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  const requestId = useRef(crypto.randomUUID());
  const reload = useCallback(async () => setItems(await social<Moment[]>(path)), [path]);
  useEffect(() => {
    let active = true;
    const refresh = () => { if (!document.hidden) void social<Moment[]>(path).then(value => { if (active) setItems(value); }).catch(e => { if (active) setError(e.message); }); };
    refresh();
    const timer = window.setInterval(refresh, 20_000);
    window.addEventListener('focus', refresh);
    return () => { active = false; window.clearInterval(timer); window.removeEventListener('focus', refresh); };
  }, [path]);
  const publish = async () => {
    setBusy(true); setError('');
    try {
      await social(path, 'POST', { text: draft.trim(), requestId: requestId.current });
      setDraft(''); requestId.current = crypto.randomUUID(); await reload();
    } catch (e) { setError(e instanceof Error ? e.message : '发布失败'); }
    finally { setBusy(false); }
  };
  const remove = async (id: string) => {
    setBusy(true); setError('');
    try { await social(`${path}/${id}`, 'DELETE'); await reload(); }
    catch (e) { setError(e instanceof Error ? e.message : '删除失败'); }
    finally { setBusy(false); }
  };
  return <section className="rounded-2xl bg-white p-5 shadow-sm">
    <div className="flex items-center justify-between"><div><h2 className="text-xl font-bold">生活日常</h2><p className="text-sm text-slate-500">只向这场活动的成员展示。</p></div><button className="text-sm text-teal-700" onClick={() => void reload().catch(e => setError(e.message))}>刷新</button></div>
    {error && <p role="alert" className="mt-3 rounded-lg bg-red-50 p-3 text-sm text-red-700">{error}</p>}
    <div className="mt-4 flex flex-col gap-2 sm:flex-row"><textarea aria-label="写下生活日常" className="min-h-20 min-w-0 flex-1 rounded-xl border p-3" maxLength={1000} placeholder="今天想和大家分享什么？" value={draft} onChange={e => { setDraft(e.target.value); requestId.current = crypto.randomUUID(); }} /><button disabled={busy || !draft.trim()} className="self-end rounded-xl bg-teal-700 px-5 py-2 text-white disabled:opacity-50" onClick={publish}>发布</button></div>
    <div className="mt-4 space-y-3">{items.map(item => <article key={item.id} className="rounded-xl bg-slate-50 p-4"><div className="flex justify-between gap-3 text-sm"><b>{item.authorName}</b><time className="text-slate-500">{new Date(item.createdAt).toLocaleString('zh-CN', { timeZone: 'Asia/Shanghai' })}</time></div><p className="mt-2 whitespace-pre-wrap break-words">{item.text}</p>{item.canDelete && <button disabled={busy} className="mt-2 text-xs text-red-700" onClick={() => void remove(item.id)}>删除我的记录</button>}</article>)}{items.length === 0 && <p className="text-sm text-slate-500">还没有分享的日常。</p>}</div>
  </section>;
}

function DearRelationships({ spaceId, activityId }: { spaceId: string; activityId: string }) {
  const [members, setMembers] = useState<SocialMember[]>([]);
  const [relations, setRelations] = useState<Relationship[]>([]);
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  const reload = useCallback(async () => {
    const [people, links] = await Promise.all([
      spaceId && activityId ? social<SocialMember[]>(`tenants/${spaceId}/activities/${activityId}/members`) : Promise.resolve([]),
      social<Relationship[]>('relationships'),
    ]);
    setMembers(people); setRelations(links);
  }, [spaceId, activityId]);
  useEffect(() => { void reload().catch(e => setError(e.message)); }, [reload]);
  const update = async (path: string, method: string, body?: object) => {
    setBusy(true); setError('');
    try { await social(path, method, body); await reload(); }
    catch (e) { setError(e instanceof Error ? e.message : '关系操作失败'); }
    finally { setBusy(false); }
  };
  return <section className="rounded-2xl bg-white p-5 shadow-sm">
    <div className="flex items-center justify-between"><div><h2 className="text-xl font-bold">朋友关系</h2><p className="text-sm text-slate-500">好友关系需要双方确认，与空间归属分开。</p></div><button className="text-sm text-teal-700" onClick={() => void reload().catch(e => setError(e.message))}>刷新</button></div>
    {error && <p role="alert" className="mt-3 rounded-lg bg-red-50 p-3 text-sm text-red-700">{error}</p>}
    <div className={`mt-4 grid gap-5 ${activityId ? 'md:grid-cols-2' : ''}`}>
      {activityId && <div><h3 className="font-semibold">这场活动的成员</h3><div className="mt-2 space-y-2">{members.filter(item => !item.isSelf).map(item => {
        const relation = relations.find(link => link.peerSubject === item.subject);
        return <div key={item.subject} className="flex items-center justify-between gap-2 rounded-xl bg-slate-50 p-3 text-sm"><span>{item.displayName}</span>{relation ? <span className="text-slate-500">{relation.status === 'accepted' ? '已是朋友' : relation.direction === 'incoming' ? '对方邀请了你' : '待对方确认'}</span> : <button disabled={busy} className="text-teal-700" onClick={() => void update('relationships/requests', 'POST', { targetSubject: item.subject, tenantId: spaceId, activityId })}>申请好友</button>}</div>;
      })}{members.filter(item => !item.isSelf).length === 0 && <p className="text-sm text-slate-500">邀请其他人参加活动后，可从这里申请好友。</p>}</div></div>}
      <div><h3 className="font-semibold">我的好友与申请</h3><div className="mt-2 space-y-2">{relations.map(item => <div key={item.id} className="flex flex-wrap items-center justify-between gap-2 rounded-xl bg-slate-50 p-3 text-sm"><span>{item.peerName} · {item.status === 'accepted' ? '朋友' : item.direction === 'incoming' ? '邀请你成为朋友' : '等待对方确认'}</span><div className="flex gap-3">{item.status === 'pending' && item.direction === 'incoming' && <button disabled={busy} className="text-teal-700" onClick={() => void update(`relationships/${item.id}/accept`, 'POST', {})}>接受</button>}<button disabled={busy} className="text-red-700" onClick={() => void update(`relationships/${item.id}`, 'DELETE')}>{item.status === 'accepted' ? '解除' : '移除'}</button></div></div>)}{relations.length === 0 && <p className="text-sm text-slate-500">还没有确认的好友关系。</p>}</div></div>
    </div>
  </section>;
}

export default function DearSocial() {
  const { appProfile, logout } = useAuth();
  const navigate = useNavigate();
  const { spaceId: routeSpaceId, activityId: routeActivityId } = useParams();
  const detailMode = Boolean(routeSpaceId && routeActivityId);
  const [params, setParams] = useSearchParams();
  const [spaces, setSpaces] = useState<Space[]>([]);
  const [spaceId, setSpaceId] = useState(routeSpaceId || '');
  const [activities, setActivities] = useState<Activity[]>([]);
  const [activityId, setActivityId] = useState(routeActivityId || '');
  const [photos, setPhotos] = useState<Photo[]>([]);
  const [invitations, setInvitations] = useState<Invitation[]>([]);
  const [spaceName, setSpaceName] = useState('');
  const [activityName, setActivityName] = useState('');
  const [inviteUsername, setInviteUsername] = useState('');
  const [inviteUrl, setInviteUrl] = useState('');
  const [busy, setBusy] = useState(false);
  const [loading, setLoading] = useState(true);
  const [activityLoading, setActivityLoading] = useState(false);
  const [activityError, setActivityError] = useState('');
  const [refreshIndex, setRefreshIndex] = useState(0);
  const [error, setError] = useState('');
  const [message, setMessage] = useState('');
  const selected = activities.find(item => item.id === activityId);
  const chosenSpace = spaces.find(item => item.id === spaceId);
  const activityPath = (id: string) => `/dear/spaces/${encodeURIComponent(spaceId)}/activities/${encodeURIComponent(id)}`;

  useEffect(() => {
    if (detailMode) { setSpaceId(routeSpaceId || ''); setActivityId(routeActivityId || ''); }
  }, [detailMode, routeSpaceId, routeActivityId]);

  const reload = useCallback(async () => {
    const found = await social<Space[]>('tenants');
    setSpaces(found);
    setSpaceId(previous => found.some(item => item.id === previous) ? previous : detailMode ? routeSpaceId || '' : found[0]?.id || '');
    setRefreshIndex(previous => previous + 1);
    try { setInvitations(await social<Invitation[]>('invites/username/pending')); }
    catch (e) { setError(e instanceof Error ? `活动邀请暂时无法读取：${e.message}` : '活动邀请暂时无法读取'); }
  }, [detailMode, routeSpaceId]);
  useEffect(() => {
    let current = true;
    setLoading(true);
    void reload().catch(e => { if (current) setError(e.message); })
      .finally(() => { if (current) setLoading(false); });
    return () => { current = false; };
  }, [reload]);
  useEffect(() => {
    if (!spaceId) { setActivities([]); setActivityId(''); setActivityLoading(false); return; }
    let current = true;
    setActivityLoading(true);
    setActivityError('');
    void social<Activity[]>(`tenants/${spaceId}/activities`).then(items => {
      if (!current) return;
      setActivities(items);
      setActivityId(detailMode && items.some(item => item.id === routeActivityId) ? routeActivityId || '' : '');
    }).catch(e => { if (current) { setActivities([]); setActivityError(e.message); } })
      .finally(() => { if (current) setActivityLoading(false); });
    return () => { current = false; };
  }, [spaceId, refreshIndex, detailMode, routeActivityId]);
  useEffect(() => {
    if (!detailMode || !spaceId || !activityId) { setPhotos([]); return; }
    let current = true;
    void social<Photo[]>(`tenants/${spaceId}/activities/${activityId}/live/photos`)
      .then(items => { if (current) setPhotos(items); })
      .catch(e => { if (current) setError(e.message); });
    return () => { current = false; };
  }, [spaceId, activityId, detailMode]);

  async function act(action: () => Promise<void>) {
    setBusy(true); setError(''); setMessage('');
    try { await action(); } catch (e) { setError(e instanceof Error ? e.message : '操作失败'); }
    finally { setBusy(false); }
  }
  const createSpace = () => act(async () => {
    const item = await social<Space>('tenants', 'POST', { name: spaceName.trim() });
    setSpaceName(''); await reload(); setSpaceId(item.id); setMessage('生活空间已创建。');
  });
  const createActivity = () => act(async () => {
    const item = await social<Activity>(`tenants/${spaceId}/activities`, 'POST', { title: activityName.trim(), description: '' });
    setActivityName('');
    setActivities(await social<Activity[]>(`tenants/${spaceId}/activities`));
    navigate(`/dear/spaces/${spaceId}/activities/${item.id}`);
  });
  const inviteByName = () => act(async () => {
    await social(`tenants/${spaceId}/activities/${activityId}/invites/username`, 'POST', { username: inviteUsername.trim() });
    setInviteUsername(''); setMessage('邀请已发出，对方确认后才能参加活动。');
  });
  const makeLink = () => act(async () => {
    const invite = await social<{ token: string }>(`tenants/${spaceId}/activities/${activityId}/invites/link`, 'POST', {});
    setInviteUrl(`${window.location.origin}/dear?invite=${encodeURIComponent(invite.token)}`);
  });
  const acceptLink = () => act(async () => {
    const token = params.get('invite');
    if (!token) return;
    await social(`invites/link/${encodeURIComponent(token)}/accept`, 'POST', {});
    setParams({}, { replace: true }); await reload(); setMessage('已加入共同活动。');
  });
  const refreshPhotos = () => act(async () => {
    setPhotos(await social<Photo[]>(`tenants/${spaceId}/activities/${activityId}/live/photos`));
    setMessage('相册已刷新。');
  });

  return <div className="min-h-screen bg-[#F7F9FC] px-4 py-6 text-slate-800 sm:px-6">
    <div className="mx-auto max-w-5xl space-y-5">
      <header className="flex flex-wrap items-center justify-between gap-3">
        <div><p className="text-sm font-semibold tracking-widest text-teal-700">LINKO DEAR</p><h1 className="text-3xl font-bold">{detailMode ? '活动详情' : '活动与分享'}</h1><p className="mt-1 text-sm text-slate-600">空间收纳一组活动；邀请、相册和日常只属于各自的活动。</p></div>
        <div className="flex gap-2">{detailMode && <Link className="rounded-xl border bg-white px-4 py-2 text-sm" to="/dear">返回活动</Link>}{appProfile?.role === 'parent' ? <Link className="rounded-xl border bg-white px-4 py-2 text-sm" to="/dashboard">家庭积分</Link> : <a className="rounded-xl border bg-white px-4 py-2 text-sm" href="/watch">手表端</a>}<button className="rounded-xl border bg-white px-4 py-2 text-sm" onClick={logout}>退出</button></div>
      </header>
      {params.get('invite') && <section className="rounded-2xl border border-teal-200 bg-teal-50 p-4"><p className="mb-2">有人邀请你加入共同活动。确认后，该活动成员可看到你在活动中分享的内容。</p><button disabled={busy} className="rounded-lg bg-teal-700 px-4 py-2 text-white" onClick={acceptLink}>确认加入</button></section>}
      {error && <p role="alert" className="rounded-xl bg-red-50 p-3 text-red-700">{error}</p>}
      {message && <p role="status" className="rounded-xl bg-teal-50 p-3 text-teal-800">{message}</p>}
      {detailMode ? <>
        <nav aria-label="当前位置" className="text-sm text-slate-600"><Link to="/dear" className="text-teal-700">活动</Link><span className="mx-2">/</span>{chosenSpace?.name || '空间'}<span className="mx-2">/</span>{selected?.title || '活动详情'}</nav>
        {loading || activityLoading ? <p className="rounded-2xl bg-white p-6 text-slate-500">正在读取活动…</p> : activityError ? <p role="alert" className="rounded-2xl bg-red-50 p-6 text-red-700">活动读取失败：{activityError}</p> : !chosenSpace || !selected ? <section className="rounded-2xl bg-white p-6"><p>找不到这场活动，或你尚未加入。</p><Link to="/dear" className="mt-3 inline-block text-teal-700">返回活动列表</Link></section> : <>
          <section className="rounded-2xl bg-white p-5 shadow-sm"><p className="text-sm text-teal-700">所属空间：{chosenSpace.name}</p><h2 className="mt-1 text-2xl font-bold">{selected.title}</h2><p className="mt-2 text-sm text-slate-500">{selected.description || '一起留下相聚记忆。'}</p></section>
          <section className="rounded-2xl bg-white p-5 shadow-sm"><h3 className="font-semibold">邀请家人或朋友参加这场活动</h3><p className="mt-1 text-xs text-slate-500">受邀人确认后才能参加；空间本身不代表亲属或好友关系。</p><div className="mt-3 flex gap-2"><input aria-label="被邀请人的用户名" className="min-w-0 flex-1 rounded-lg border p-2" placeholder="用户中心用户名" value={inviteUsername} onChange={e => setInviteUsername(e.target.value)} /><button disabled={busy || !inviteUsername.trim()} className="rounded-lg border px-3 disabled:opacity-50" onClick={inviteByName}>邀请</button></div><button disabled={busy} className="mt-3 text-sm text-teal-700" onClick={makeLink}>生成七天有效的邀请链接</button>{inviteUrl && <input aria-label="活动邀请链接" className="mt-2 w-full rounded-lg border p-2 text-sm" readOnly value={inviteUrl} onFocus={e => e.target.select()} />}</section>
          <section className="rounded-2xl bg-white p-5 shadow-sm"><div className="flex flex-wrap justify-between gap-2"><div><h3 className="text-xl font-bold">共同相册</h3><p className="text-sm text-slate-500">只向这场活动的成员展示。</p></div><div className="flex gap-3"><button className="text-sm text-teal-700" onClick={refreshPhotos}>刷新照片</button><a className="text-sm text-teal-700" href="https://linko.ai.impx.net/" target="_blank" rel="noopener noreferrer">分享照片与获取原图</a></div></div><div className="mt-3 grid gap-3 sm:grid-cols-2">{photos.map(photo => <article key={photo.id} className="overflow-hidden rounded-xl border"><div className="flex h-40 items-center justify-center bg-slate-100">{photo.thumbnailAvailable ? <img className="h-full w-full object-cover" src={`${gateway}tenants/${spaceId}/activities/${activityId}/native-photos/${photo.id}/thumbnail`} alt={photo.originalFileName} /> : <span className="text-sm text-slate-500">原图保存在分享者设备</span>}</div><div className="p-3 text-sm"><b>{photo.sourceDisplayName}</b><p className="truncate text-slate-500">{photo.originalFileName}</p></div></article>)}{photos.length === 0 && <p className="text-sm text-slate-500">还没有分享的照片。</p>}</div></section>
          <DearMoments key={`${spaceId}:${activityId}`} spaceId={spaceId} activityId={activityId} />
          <DearRelationships key={`${spaceId}:${activityId}`} spaceId={spaceId} activityId={activityId} />
        </>}
      </> : <>
        <section className="rounded-2xl bg-white p-5 shadow-sm"><div className="flex flex-wrap justify-between gap-3"><div><h2 className="text-xl font-bold">生活空间</h2><p className="text-sm text-slate-500">空间用来归拢活动；加入某场活动才可查看该场的分享。</p></div><button className="text-sm text-teal-700" onClick={() => void act(reload)}>刷新</button></div>{loading ? <p className="py-6 text-slate-500">正在读取生活空间…</p> : <div className="mt-4 grid gap-3 sm:grid-cols-[1fr_auto]"><select aria-label="选择生活空间" className="rounded-xl border p-3" value={spaceId} onChange={e => setSpaceId(e.target.value)}><option value="">选择空间</option>{spaces.map(item => <option key={item.id} value={item.id}>{item.name}</option>)}</select><div className="flex gap-2"><input aria-label="新空间名称" className="min-w-0 rounded-xl border p-3" maxLength={200} placeholder="例如：周末好友" value={spaceName} onChange={e => setSpaceName(e.target.value)} /><button disabled={busy || !spaceName.trim()} className="rounded-xl bg-teal-700 px-4 text-white disabled:opacity-50" onClick={createSpace}>创建空间</button></div></div>}</section>
        {chosenSpace && <section className="rounded-2xl bg-white p-5 shadow-sm"><div><p className="text-sm text-teal-700">当前空间</p><h2 className="text-xl font-bold">{chosenSpace.name}的活动</h2><p className="mt-1 text-sm text-slate-500">点开活动查看邀请、照片、日常与成员。</p></div><div className="mt-4 flex gap-2"><input aria-label="新活动名称" className="min-w-0 flex-1 rounded-xl border p-2" maxLength={200} placeholder="一起做什么？" value={activityName} onChange={e => setActivityName(e.target.value)} /><button disabled={busy || !activityName.trim()} className="rounded-xl bg-teal-700 px-3 text-white disabled:opacity-50" onClick={createActivity}>创建活动</button></div><div className="mt-4 divide-y">{activityLoading && <p className="py-3 text-sm text-slate-500">正在读取已有活动…</p>}{activityError && <p role="alert" className="py-3 text-sm text-red-700">{activityError}</p>}{activities.map(item => <Link key={item.id} to={activityPath(item.id)} className="flex items-center justify-between gap-3 py-4 hover:text-teal-700"><span><b className="block">{item.title}</b><span className="mt-1 block text-sm text-slate-500">{item.description || '查看活动详情与共同记忆'}</span></span><span aria-hidden="true">›</span></Link>)}{!activityLoading && !activityError && activities.length === 0 && <p className="py-4 text-sm text-slate-500">尚无活动。创建一个相聚计划吧。</p>}</div></section>}
        {invitations.some(item => !item.joined) && <section className="rounded-2xl bg-white p-5 shadow-sm"><h2 className="text-xl font-bold">收到的活动邀请</h2><p className="mb-3 text-xs text-slate-500">确认后才会加入对应活动。</p>{invitations.filter(item => !item.joined).map(item => <div key={item.id} className="flex items-center justify-between border-t py-3"><span>{item.activityTitle}</span><button disabled={busy} className="text-teal-700" onClick={() => void act(async () => { const user = await social<{ username: string }>('me'); await social(`tenants/${item.tenantId}/activities/${item.activityId}/invites/username/${encodeURIComponent(user.username)}/accept`, 'POST', {}); await reload(); navigate(`/dear/spaces/${encodeURIComponent(item.tenantId)}/activities/${encodeURIComponent(item.activityId)}`); })}>确认加入</button></div>)}</section>}
        <details className="rounded-2xl bg-white p-5 shadow-sm"><summary className="cursor-pointer font-semibold">好友与申请（跨空间）</summary><div className="mt-4"><DearRelationships spaceId="" activityId="" /></div></details>
      </>}
      <footer className="pb-6 text-center text-xs text-slate-500"><a className="underline" href="/legal/linko-family-privacy.html" target="_blank" rel="noopener noreferrer">隐私政策与支持</a></footer>
    </div>
  </div>;
}
