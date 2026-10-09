import { useCallback, useEffect, useMemo, useState } from 'react';
import { useAuth } from '../contexts/AuthContext';
import {
  createGenealogy, createGenealogyPerson, createGenealogyRelationship, createGenealogyInvitation, decideGenealogyJoin,
  deleteGenealogyRelationship, discoverGenealogies, getGenealogies, getGenealogy,
  getGenealogyInferredRelationships, getGenealogyJoinRequests, getGenealogyPeople, getGenealogyPerson, getGenealogyRelationships, getMyGenealogyJoinRequests,
  requestGenealogyJoin, updateGenealogyPerson,
} from '../services';
import type { GenealogyDiscovery, GenealogyInferredRelationship, GenealogyJoinRequest, GenealogyPerson, GenealogyRelationship, GenealogyTree, MyGenealogyJoinRequest } from '../types';

const emptyPerson = { displayName: '', generationLabel: '', branchName: '', note: '' };
const errorText = (error: unknown) => error instanceof Error ? error.message : '操作失败，请稍后重试';
const inferredKinds = [
  ['sibling', '兄弟姐妹'], ['grandparent', '祖辈'], ['grandchild', '孙辈'],
  ['parentSibling', '父母的兄弟姐妹'], ['siblingChild', '兄弟姐妹的子女'], ['cousin', '堂表亲'],
] as const;

export default function Genealogy() {
  const { user } = useAuth();
  const [trees, setTrees] = useState<GenealogyTree[]>([]);
  const [selectedId, setSelectedId] = useState<number | null>(null);
  const [tree, setTree] = useState<GenealogyTree | null>(null);
  const [people, setPeople] = useState<GenealogyPerson[]>([]);
  const [knownPeople, setKnownPeople] = useState<GenealogyPerson[]>([]);
  const [hasMore, setHasMore] = useState(false);
  const [relationships, setRelationships] = useState<GenealogyRelationship[]>([]);
  const [inferred, setInferred] = useState<GenealogyInferredRelationship[]>([]);
  const [inferredLoading, setInferredLoading] = useState(false);
  const [inferredError, setInferredError] = useState('');
  const [requests, setRequests] = useState<GenealogyJoinRequest[]>([]);
  const [requestMatches, setRequestMatches] = useState<Record<number, number>>({});
  const [myRequests, setMyRequests] = useState<MyGenealogyJoinRequest[]>([]);
  const [selectedPersonId, setSelectedPersonId] = useState<number | null>(null);
  const [personQuery, setPersonQuery] = useState('');
  const [discoverQuery, setDiscoverQuery] = useState('');
  const [discovered, setDiscovered] = useState<GenealogyDiscovery[]>([]);
  const [requestTreeId, setRequestTreeId] = useState<number | null>(null);
  const [requestName, setRequestName] = useState(user?.displayName || user?.realName || user?.username || '');
  const [requestMessage, setRequestMessage] = useState('');
  const [newTree, setNewTree] = useState({ name: '', surname: '', description: '' });
  const [personForm, setPersonForm] = useState(emptyPerson);
  const [editingPersonId, setEditingPersonId] = useState<number | null>(null);
  const [relationTarget, setRelationTarget] = useState(0);
  const [relationKind, setRelationKind] = useState<'parent' | 'child' | 'spouse'>('parent');
  const [invitationUrl, setInvitationUrl] = useState('');
  const [busy, setBusy] = useState(false);
  const [loading, setLoading] = useState(false);
  const [message, setMessage] = useState('');

  useEffect(() => {
    if (!requestName && user) setRequestName(user.displayName || user.realName || user.username || '');
  }, [requestName, user]);

  const refreshTrees = useCallback(async () => {
    const rows = await getGenealogies();
    setTrees(rows);
    return rows;
  }, []);

  const refreshTree = useCallback(async (id: number, q = '', shouldApply: () => boolean = () => true) => {
    const detail = await getGenealogy(id);
    const [peopleResult, links, pending] = await Promise.all([
      getGenealogyPeople(id, q), getGenealogyRelationships(id),
      detail.role === 'owner' ? getGenealogyJoinRequests(id) : Promise.resolve([] as GenealogyJoinRequest[]),
    ]);
    if (!shouldApply()) return;
    setTree(detail);
    setPeople(peopleResult.people);
    setKnownPeople((current) => {
      const map = new Map(current.map((person) => [person.id, person]));
      for (const person of peopleResult.people) map.set(person.id, person);
      return [...map.values()];
    });
    setHasMore(peopleResult.hasMore);
    setRelationships(links);
    setRequests(pending);
  }, []);

  useEffect(() => {
    let active = true;
    Promise.all([refreshTrees(), getMyGenealogyJoinRequests()]).then(([rows, applications]) => {
      if (active) setMyRequests(applications);
      if (active && rows.length) setSelectedId((id) => id ?? rows[0].id);
    }).catch((error) => { if (active) setMessage(errorText(error)); });
    return () => { active = false; };
  }, [refreshTrees]);

  useEffect(() => {
    if (!selectedId) { setTree(null); setPeople([]); return; }
    let active = true;
    setLoading(true);
    const timer = window.setTimeout(() => {
      refreshTree(selectedId, personQuery, () => active).catch((error) => { if (active) setMessage(errorText(error)); })
        .finally(() => { if (active) setLoading(false); });
    }, 250);
    return () => { active = false; window.clearTimeout(timer); };
  }, [selectedId, personQuery, refreshTree]);

  useEffect(() => {
    if (!selectedId || !selectedPersonId) { setInferred([]); setInferredError(''); setInferredLoading(false); return; }
    let active = true;
    setInferred([]);
    setInferredError('');
    setInferredLoading(true);
    getGenealogyInferredRelationships(selectedId, selectedPersonId)
      .then((items) => { if (active) { setInferred(items); setInferredError(''); } })
      .catch((error: unknown) => { if (active) setInferredError(errorText(error)); })
      .finally(() => { if (active) setInferredLoading(false); });
    return () => { active = false; };
  }, [selectedId, selectedPersonId, relationships]);

  const selectedPerson = useMemo(() => knownPeople.find((person) => person.id === selectedPersonId) || null, [knownPeople, selectedPersonId]);
  const related = useMemo(() => relationships.filter((item) => item.fromPersonId === selectedPersonId || item.toPersonId === selectedPersonId), [relationships, selectedPersonId]);
  const canEdit = tree?.role === 'owner';

  const run = async (action: () => Promise<void>) => {
    try { setBusy(true); setMessage(''); await action(); }
    catch (error) { setMessage(errorText(error)); }
    finally { setBusy(false); }
  };

  const handleCreateTree = () => run(async () => {
    const created = await createGenealogy({ name: newTree.name.trim(), surname: newTree.surname.trim(), description: newTree.description.trim() });
    await refreshTrees();
    setTree(null);
    setPeople([]);
    setKnownPeople([]);
    setSelectedPersonId(null);
    setSelectedId(created.id);
    setNewTree({ name: '', surname: '', description: '' });
    setMessage(`已创建「${created.name}」`);
  });

  const handleDiscover = () => run(async () => {
    setDiscovered(await discoverGenealogies(discoverQuery.trim()));
  });

  const handleJoin = () => run(async () => {
    if (!requestTreeId) return;
    await requestGenealogyJoin(requestTreeId, { displayName: requestName.trim(), message: requestMessage.trim() });
    setMyRequests(await getMyGenealogyJoinRequests());
    setMessage('加入申请已提交，管理员通过后即可查看成员资料');
    setRequestTreeId(null);
    setRequestMessage('');
  });

  const handleDecision = (requestId: number, decision: 'approve' | 'reject') => run(async () => {
    if (!selectedId) return;
    await decideGenealogyJoin(selectedId, requestId, decision, decision === 'approve' ? requestMatches[requestId] : undefined);
    await refreshTree(selectedId, personQuery);
    setMessage(decision === 'approve' ? '已通过加入申请' : '已拒绝加入申请');
  });

  const handleSavePerson = () => run(async () => {
    if (!selectedId) return;
    const data = { displayName: personForm.displayName.trim(), generationLabel: personForm.generationLabel.trim(), branchName: personForm.branchName.trim(), note: personForm.note.trim() };
    if (editingPersonId) await updateGenealogyPerson(selectedId, editingPersonId, data);
    else await createGenealogyPerson(selectedId, data);
    setPersonForm(emptyPerson);
    setEditingPersonId(null);
    setSelectedPersonId(null);
    setKnownPeople([]);
    await refreshTree(selectedId, personQuery);
    setMessage('成员资料已保存');
  });

  const handleAddRelation = () => run(async () => {
    if (!selectedId) return;
    if (!selectedPersonId || !relationTarget || selectedPersonId === relationTarget) return;
    const isParent = relationKind === 'parent';
    await createGenealogyRelationship(selectedId, { fromPersonId: isParent ? relationTarget : selectedPersonId, toPersonId: isParent ? selectedPersonId : relationTarget, kind: relationKind === 'spouse' ? 'spouse' : 'parent' });
    await refreshTree(selectedId, personQuery);
    setRelationTarget(0);
    setMessage('关系已添加');
  });

  const handleCreateInvitation = () => run(async () => {
    if (!selectedId || !selectedPersonId) return;
    const invitation = await createGenealogyInvitation(selectedId, selectedPersonId);
    const url = new URL(invitation.path, window.location.origin).toString();
    setInvitationUrl(url);
    try {
      await navigator.clipboard.writeText(url);
      setMessage('邀请链接已复制，7 天内有效且只能使用一次。重新生成会使旧链接失效。');
    } catch {
      setMessage('邀请链接已生成，请从下方文本框复制。7 天内有效且只能使用一次。');
    }
  });

  const handleDeleteRelation = (relationId: number) => run(async () => {
    if (!selectedId) return;
    await deleteGenealogyRelationship(selectedId, relationId);
    await refreshTree(selectedId, personQuery);
    setMessage('关系已移除');
  });

  const handleSelectPerson = async (personId: number) => {
    if (!selectedId) return;
    try {
      if (!knownPeople.some((person) => person.id === personId)) {
        const person = await getGenealogyPerson(selectedId, personId);
        setKnownPeople((current) => current.some((item) => item.id === person.id) ? current : [...current, person]);
      }
      setSelectedPersonId(personId);
      setRelationTarget(0);
      setInvitationUrl('');
    } catch (error) { setMessage(errorText(error)); }
  };

  return <div className="mx-auto max-w-6xl space-y-5 p-4 pb-12 sm:p-6">
    <div>
      <h2 className="text-2xl font-bold text-gray-900">家族族谱</h2>
      <p className="mt-1 text-sm text-gray-600">寻找族谱并申请加入；加入后可查找成员、查看辈分与亲属关系。成员资料仅族谱成员可见。</p>
    </div>
    {message && <div role="status" className="rounded-xl border border-blue-200 bg-blue-50 p-3 text-sm text-blue-800">{message}</div>}

    <div className="grid gap-5 lg:grid-cols-[300px_minmax(0,1fr)]">
      <aside className="space-y-5">
        <section className="rounded-2xl border border-gray-200 bg-white p-4 shadow-sm">
          <h3 className="font-semibold">我的族谱</h3>
          <div className="mt-3 space-y-2">
            {trees.length === 0 && <p className="text-sm text-gray-500">还没有加入族谱</p>}
            {trees.map((item) => <button key={item.id} type="button" onClick={() => { setSelectedId(item.id); setTree(null); setPeople([]); setRelationships([]); setRequests([]); setPersonQuery(''); setKnownPeople([]); setSelectedPersonId(null); setEditingPersonId(null); setPersonForm(emptyPerson); setRelationTarget(0); setInvitationUrl(''); }} className={`w-full rounded-xl border p-3 text-left ${selectedId === item.id ? 'border-[#4A90D9] bg-blue-50' : 'border-gray-200 hover:bg-gray-50'}`}>
              <span className="block font-semibold text-gray-900">{item.name}</span>
              <span className="text-xs text-gray-500">{item.surname ? `${item.surname}氏 · ` : ''}{item.peopleCount} 位人物 · {item.role === 'owner' ? '管理员' : '成员'}</span>
            </button>)}
          </div>
        </section>
        <section className="rounded-2xl border border-gray-200 bg-white p-4 shadow-sm">
          <h3 className="font-semibold">寻找族谱</h3>
          {myRequests.length > 0 && <div className="mt-3 space-y-1 text-xs text-gray-600">{myRequests.slice(0, 5).map((item) => <p key={item.id}>「{item.treeName}」：{item.status === 'pending' ? '等待审核' : item.status === 'approved' ? '已通过' : '未通过'}</p>)}</div>}
          <div className="mt-3 flex gap-2"><input aria-label="族谱名称或姓氏" value={discoverQuery} onChange={(event) => setDiscoverQuery(event.target.value)} onKeyDown={(event) => { if (event.key === 'Enter') void handleDiscover(); }} placeholder="输入族谱名或姓氏" className="min-w-0 flex-1 rounded-lg border border-gray-300 px-3 py-2 text-sm" /><button type="button" disabled={busy} onClick={() => void handleDiscover()} className="rounded-lg bg-[#4A90D9] px-3 py-2 text-sm text-white disabled:opacity-50">查找</button></div>
          <div className="mt-3 space-y-2">{discovered.map((item) => <div key={item.id} className="flex items-center justify-between gap-2 rounded-lg bg-gray-50 p-2 text-sm"><div><b>{item.name}</b><span className="ml-1 text-gray-500">{item.surname && `${item.surname}氏`} #{item.id}</span></div><button type="button" onClick={() => setRequestTreeId(item.id)} className="shrink-0 text-[#2878c7]">申请加入</button></div>)}</div>
          {requestTreeId && <div className="mt-3 space-y-2 border-t pt-3"><p className="text-sm font-medium">申请加入「{discovered.find((item) => item.id === requestTreeId)?.name}」</p><input aria-label="加入族谱时显示的姓名" value={requestName} onChange={(event) => setRequestName(event.target.value)} placeholder="你的姓名" className="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm" /><textarea aria-label="加入说明" value={requestMessage} onChange={(event) => setRequestMessage(event.target.value)} placeholder="介绍你与家族的关系（可选）" maxLength={300} className="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm" /><button type="button" disabled={busy} onClick={() => void handleJoin()} className="rounded-lg bg-[#4A90D9] px-3 py-2 text-sm text-white disabled:opacity-50">提交申请</button></div>}
        </section>
        <section className="rounded-2xl border border-gray-200 bg-white p-4 shadow-sm">
          <h3 className="font-semibold">建立新族谱</h3>
          <div className="mt-3 space-y-2"><input aria-label="族谱名称" value={newTree.name} onChange={(event) => setNewTree({ ...newTree, name: event.target.value })} placeholder="例如：张氏家族" maxLength={100} className="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm" /><input aria-label="家族姓氏" value={newTree.surname} onChange={(event) => setNewTree({ ...newTree, surname: event.target.value })} placeholder="姓氏（可选）" maxLength={30} className="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm" /><textarea aria-label="族谱简介" value={newTree.description} onChange={(event) => setNewTree({ ...newTree, description: event.target.value })} placeholder="简介仅向族谱成员展示" maxLength={500} className="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm" /><button type="button" disabled={busy} onClick={() => void handleCreateTree()} className="rounded-lg bg-emerald-600 px-3 py-2 text-sm text-white disabled:opacity-50">创建族谱</button></div>
        </section>
      </aside>

      <main className="space-y-5">
        {!tree && <div className="rounded-2xl border border-gray-200 bg-white p-8 text-center text-gray-500">请选择或创建一个族谱</div>}
        {tree && <>
          <section className="rounded-2xl border border-gray-200 bg-white p-5 shadow-sm"><div className="flex flex-wrap items-start justify-between gap-3"><div><h3 className="text-xl font-bold text-gray-900">{tree.name}</h3><p className="mt-1 text-sm text-gray-500">{tree.surname && `${tree.surname}氏 · `}{tree.peopleCount} 位人物 · {tree.memberCount} 位已加入成员</p>{tree.description && <p className="mt-2 text-sm text-gray-700">{tree.description}</p>}</div><span className="rounded-full bg-blue-50 px-3 py-1 text-xs text-blue-700">{canEdit ? '管理员' : '成员'}</span></div></section>
          {canEdit && requests.length > 0 && <section className="rounded-2xl border border-amber-200 bg-amber-50 p-4"><h3 className="font-semibold">待审核加入申请（{requests.length}）</h3><div className="mt-3 space-y-2">{requests.map((item) => <div key={item.id} className="rounded-lg bg-white p-3 text-sm"><div className="flex flex-wrap items-center justify-between gap-2"><b>{item.displayName}</b><div className="flex gap-3"><button type="button" disabled={busy} onClick={() => void handleDecision(item.id, 'approve')} className="text-emerald-700">通过</button><button type="button" disabled={busy} onClick={() => void handleDecision(item.id, 'reject')} className="text-red-600">拒绝</button></div></div><p className="mt-1 text-xs text-gray-500">用户中心账号：{item.accountName}</p>{item.message && <p className="mt-1 text-gray-600">{item.message}</p>}<label className="mt-2 block text-xs text-gray-600">关联已有的人物（可选）<select value={requestMatches[item.id] || 0} onChange={(event) => setRequestMatches({ ...requestMatches, [item.id]: Number(event.target.value) })} className="mt-1 w-full rounded-lg border border-gray-300 px-2 py-1.5 text-sm"><option value={0}>新建本人记录</option>{knownPeople.filter((person) => !person.isLinked).map((person) => <option key={person.id} value={person.id}>{person.displayName} #{person.id}{person.branchName && ` · ${person.branchName}`}</option>)}</select></label></div>)}</div></section>}
          <section className="rounded-2xl border border-gray-200 bg-white p-5 shadow-sm"><h3 className="font-semibold">查找家族成员</h3><input aria-label="搜索姓名或支系" value={personQuery} onChange={(event) => setPersonQuery(event.target.value)} placeholder="按姓名或支系搜索" maxLength={80} className="mt-3 w-full rounded-lg border border-gray-300 px-3 py-2" />{loading && <p className="mt-2 text-sm text-gray-500">正在查找…</p>}<div className="mt-4 grid gap-2 sm:grid-cols-2">{people.map((person) => <button type="button" key={person.id} onClick={() => void handleSelectPerson(person.id)} className={`rounded-xl border p-3 text-left ${selectedPersonId === person.id ? 'border-[#4A90D9] bg-blue-50' : 'border-gray-200 hover:bg-gray-50'}`}><span className="font-semibold text-gray-900">{person.displayName}</span>{person.isSelf && <span className="ml-2 rounded bg-emerald-50 px-1.5 py-0.5 text-xs text-emerald-700">我</span>}<span className="mt-1 block text-xs text-gray-500">{[person.generationLabel, person.branchName].filter(Boolean).join(' · ') || '待补充辈分与支系'}</span></button>)}</div>{people.length === 0 && !loading && <p className="mt-3 text-sm text-gray-500">暂无匹配成员</p>}{hasMore && <p className="mt-3 text-xs text-gray-500">结果超过 100 位，请输入姓名或支系缩小范围。</p>}</section>
          {selectedPerson && <section className="rounded-2xl border border-gray-200 bg-white p-5 shadow-sm"><div className="flex items-start justify-between gap-2"><div><h3 className="text-lg font-bold">{selectedPerson.displayName}</h3><p className="text-sm text-gray-500">{[selectedPerson.generationLabel, selectedPerson.branchName].filter(Boolean).join(' · ') || '辈分、支系待补充'}</p></div>{canEdit && <button type="button" onClick={() => { setEditingPersonId(selectedPerson.id); setPersonForm({ displayName: selectedPerson.displayName, generationLabel: selectedPerson.generationLabel, branchName: selectedPerson.branchName, note: selectedPerson.note }); }} className="text-sm text-[#2878c7]">编辑</button>}</div>{selectedPerson.note && <p className="mt-2 text-sm text-gray-700">{selectedPerson.note}</p>}<div className="mt-4 grid gap-2 sm:grid-cols-3">{(['parent','child','spouse'] as const).map((kind) => { const values=related.filter((item) => kind === 'parent' ? item.kind === 'parent' && item.toPersonId === selectedPerson.id : kind === 'child' ? item.kind === 'parent' && item.fromPersonId === selectedPerson.id : item.kind === 'spouse'); return <div key={kind} className="rounded-xl bg-gray-50 p-3"><b className="text-sm">{kind === 'parent' ? '父母' : kind === 'child' ? '子女' : '配偶'}</b><div className="mt-2 space-y-1">{values.length ? values.map((item) => { const otherId=item.fromPersonId === selectedPerson.id ? item.toPersonId : item.fromPersonId; return <div key={item.id} className="flex justify-between gap-2 text-sm"><button type="button" onClick={() => void handleSelectPerson(otherId)} className="text-left text-[#2878c7]">{item.fromPersonId === selectedPerson.id ? item.toName : item.fromName}</button>{canEdit && <button type="button" disabled={busy} onClick={() => void handleDeleteRelation(item.id)} className="text-xs text-red-600">移除</button>}</div>; }) : <span className="text-xs text-gray-500">未记录</span>}</div></div>; })}</div>{canEdit && <div className="mt-5 grid gap-4 border-t border-gray-100 pt-4 md:grid-cols-2"><div><h4 className="font-semibold">为 {selectedPerson.displayName} 添加关系</h4><p className="mt-1 text-xs text-gray-500">选择相对于此人的关系和另一位成员。</p><select aria-label="与此人的关系" value={relationKind} onChange={(event) => setRelationKind(event.target.value as 'parent' | 'child' | 'spouse')} className="mt-2 w-full rounded-lg border border-gray-300 px-3 py-2 text-sm"><option value="parent">父母</option><option value="child">子女</option><option value="spouse">配偶</option></select><select aria-label="关联的成员" value={relationTarget} onChange={(event) => setRelationTarget(Number(event.target.value))} className="mt-2 w-full rounded-lg border border-gray-300 px-3 py-2 text-sm"><option value={0}>选择另一位成员</option>{knownPeople.filter((person) => person.id !== selectedPerson.id).map((person) => <option key={person.id} value={person.id}>{person.displayName} #{person.id}</option>)}</select><button type="button" disabled={busy || !relationTarget} onClick={() => void handleAddRelation()} className="mt-2 rounded-lg bg-emerald-600 px-3 py-2 text-sm text-white disabled:opacity-50">添加关系</button></div><div><h4 className="font-semibold">邀请本人加入</h4>{selectedPerson.isLinked ? <p className="mt-2 text-sm text-gray-500">此人物已绑定用户。</p> : <><p className="mt-1 text-xs text-gray-500">生成专属链接，对方登录后确认，即自动加入族谱并绑定此人物。</p><button type="button" disabled={busy} onClick={() => void handleCreateInvitation()} className="mt-2 rounded-lg bg-emerald-600 px-3 py-2 text-sm text-white disabled:opacity-50">生成并复制邀请链接</button>{invitationUrl && <input aria-label="邀请链接" readOnly value={invitationUrl} onFocus={(event) => event.target.select()} className="mt-2 w-full rounded-lg border border-gray-300 px-3 py-2 text-xs" />}</>}</div></div>}</section>}
          {selectedPerson && <section className="rounded-2xl border border-emerald-100 bg-white p-5 shadow-sm">
            <h3 className="font-semibold">根据已有关系推导</h3>
            <p className="mt-1 text-xs text-gray-500">由父母与子女关系自动计算，不单独保存；基础关系变化后会更新。缺少性别和年龄信息时使用中性称谓。</p>
            {inferredLoading && <p className="mt-3 text-sm text-gray-500">正在计算亲属关系…</p>}
            {inferredError && <p role="alert" className="mt-3 text-sm text-red-700">{inferredError}</p>}
            {!inferredLoading && !inferredError && inferred.length === 0 && <p className="mt-3 text-sm text-gray-500">暂无可推导的关系</p>}
            {!inferredLoading && !inferredError && inferred.length > 0 && <div className="mt-4 grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
              {inferredKinds.map(([kind, label]) => {
                const matches = inferred.filter((item) => item.kind === kind);
                return matches.length > 0 && <div key={kind} className="rounded-xl bg-emerald-50 p-3">
                  <h4 className="text-sm font-semibold text-emerald-900">{label}</h4>
                  <div className="mt-2 flex flex-wrap gap-2">{matches.map((item) => <button key={item.personId} type="button" onClick={() => void handleSelectPerson(item.personId)} className="rounded-lg bg-white px-2 py-1 text-sm text-emerald-800 underline">{item.displayName}</button>)}</div>
                </div>;
              })}
            </div>}
          </section>}
          {canEdit && <section className="grid gap-5 xl:grid-cols-2"><div className="rounded-2xl border border-gray-200 bg-white p-5 shadow-sm"><h3 className="font-semibold">{editingPersonId ? '编辑成员' : '补录家族成员'}</h3><div className="mt-3 space-y-2"><input aria-label="成员姓名" value={personForm.displayName} onChange={(event) => setPersonForm({ ...personForm, displayName: event.target.value })} placeholder="姓名" maxLength={80} className="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm" /><div className="grid grid-cols-2 gap-2"><input aria-label="辈分" value={personForm.generationLabel} onChange={(event) => setPersonForm({ ...personForm, generationLabel: event.target.value })} placeholder="辈分（可选）" maxLength={40} className="min-w-0 rounded-lg border border-gray-300 px-3 py-2 text-sm" /><input aria-label="支系" value={personForm.branchName} onChange={(event) => setPersonForm({ ...personForm, branchName: event.target.value })} placeholder="支系（可选）" maxLength={80} className="min-w-0 rounded-lg border border-gray-300 px-3 py-2 text-sm" /></div><textarea aria-label="成员备注" value={personForm.note} onChange={(event) => setPersonForm({ ...personForm, note: event.target.value })} placeholder="备注仅族谱成员可见" maxLength={500} className="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm" /><div className="flex gap-2"><button type="button" disabled={busy} onClick={() => void handleSavePerson()} className="rounded-lg bg-emerald-600 px-3 py-2 text-sm text-white disabled:opacity-50">保存成员</button>{editingPersonId && <button type="button" onClick={() => { setEditingPersonId(null); setPersonForm(emptyPerson); }} className="px-3 py-2 text-sm text-gray-600">取消</button>}</div></div></div></section>}
        </>}
      </main>
    </div>
  </div>;
}
