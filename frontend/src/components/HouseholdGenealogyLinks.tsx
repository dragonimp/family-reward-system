import { useEffect, useState } from 'react';
import { getGenealogies, getGenealogyPeople, getHouseholdGenealogyLinks, getHouseholdMembers, linkHouseholdGenealogyPerson, unlinkHouseholdGenealogyPerson } from '../services';
import type { GenealogyPerson, GenealogyTree, HouseholdGenealogyLink, HouseholdMember } from '../types';

export default function HouseholdGenealogyLinks() {
  const [members, setMembers] = useState<HouseholdMember[]>([]);
  const [trees, setTrees] = useState<GenealogyTree[]>([]);
  const [links, setLinks] = useState<HouseholdGenealogyLink[]>([]);
  const [memberId, setMemberId] = useState(0);
  const [treeId, setTreeId] = useState(0);
  const [personId, setPersonId] = useState(0);
  const [query, setQuery] = useState('');
  const [people, setPeople] = useState<GenealogyPerson[]>([]);
  const [hasMore, setHasMore] = useState(false);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState('');

  useEffect(() => {
    Promise.all([getHouseholdMembers(), getGenealogies(), getHouseholdGenealogyLinks()])
      .then(([family, genealogy, mappings]) => { setMembers(family); setTrees(genealogy); setLinks(mappings); })
      .catch((error: unknown) => setMessage(error instanceof Error ? error.message : '家庭关系加载失败'));
  }, []);

  const search = async (id = treeId) => {
    if (!id) return;
    try {
      const result = await getGenealogyPeople(id, query.trim());
      setPeople(result.people); setHasMore(result.hasMore);
    } catch (error) { setMessage(error instanceof Error ? error.message : '族谱人物加载失败'); }
  };

  const save = async () => {
    if (!memberId || !treeId || !personId) { setMessage('请选择家庭成员、族谱和对应人物'); return; }
    setBusy(true); setMessage('');
    try {
      await linkHouseholdGenealogyPerson(memberId, treeId, personId);
      setLinks(await getHouseholdGenealogyLinks());
      setMemberId(0); setTreeId(0); setPersonId(0); setPeople([]); setQuery('');
      setMessage('已关联族谱人物');
    } catch (error) { setMessage(error instanceof Error ? error.message : '关联失败'); }
    finally { setBusy(false); }
  };

  const unlink = async (link: HouseholdGenealogyLink) => {
    setBusy(true); setMessage('');
    try {
      await unlinkHouseholdGenealogyPerson(link.householdMemberId, link.treeId);
      setLinks(await getHouseholdGenealogyLinks());
      setMessage('已解除关联');
    } catch (error) { setMessage(error instanceof Error ? error.message : '解除关联失败'); }
    finally { setBusy(false); }
  };

  return <section className="rounded-2xl border border-emerald-100 bg-white p-5 shadow-sm">
    <h3 className="font-semibold text-gray-900">家庭成员与族谱</h3>
    <p className="mt-1 text-sm text-gray-600">明确指定同一人，便于从家庭资料找到族谱人物。不会按姓名自动合并，也不会自动改写族谱关系。</p>
    {message && <p role="status" className="mt-3 text-sm text-emerald-800">{message}</p>}
    <div className="mt-4 space-y-3">
      {members.map((member) => <div key={member.id} className="rounded-xl bg-gray-50 p-3">
        <div className="font-medium">{member.displayName}{member.isCurrentUser && <span className="ml-2 text-xs text-emerald-700">本人</span>}</div>
        <div className="mt-2 flex flex-wrap gap-2">{links.filter((link) => link.householdMemberId === member.id).map((link) =>
          <span key={link.treeId} className="rounded-lg bg-white px-2 py-1 text-xs text-gray-700">{link.treeName} · {link.personName}
            <button type="button" disabled={busy} onClick={() => void unlink(link)} className="ml-2 text-red-600">解除</button></span>)}
          {!links.some((link) => link.householdMemberId === member.id) && <span className="text-xs text-gray-500">尚未关联族谱</span>}
        </div>
        <button type="button" onClick={() => { setMemberId(member.id); setTreeId(0); setPersonId(0); setPeople([]); }} className="mt-2 text-sm text-emerald-700">关联族谱人物</button>
      </div>)}
    </div>
    {memberId > 0 && <div className="mt-4 space-y-3 rounded-xl border border-emerald-200 p-4">
      <h4 className="font-medium">为 {members.find((item) => item.id === memberId)?.displayName} 选择族谱人物</h4>
      <select aria-label="选择族谱" value={treeId} onChange={(event) => { const id = Number(event.target.value); setTreeId(id); setPersonId(0); setPeople([]); setQuery(''); if (id) void getGenealogyPeople(id).then((result) => { setPeople(result.people); setHasMore(result.hasMore); }).catch((error: unknown) => setMessage(error instanceof Error ? error.message : '族谱人物加载失败')); }} className="w-full rounded-lg border px-3 py-2 text-sm">
        <option value={0}>选择已加入的族谱</option>{trees.map((tree) => <option key={tree.id} value={tree.id}>{tree.name}</option>)}
      </select>
      {treeId > 0 && <><div className="flex gap-2"><input aria-label="搜索族谱人物" value={query} onChange={(event) => setQuery(event.target.value)} onKeyDown={(event) => { if (event.key === 'Enter') void search(); }} placeholder="按姓名或支系搜索" maxLength={80} className="min-w-0 flex-1 rounded-lg border px-3 py-2 text-sm" /><button type="button" onClick={() => void search()} className="rounded-lg border px-3 py-2 text-sm">查找</button></div>
        <select aria-label="选择对应人物" value={personId} onChange={(event) => setPersonId(Number(event.target.value))} className="w-full rounded-lg border px-3 py-2 text-sm"><option value={0}>选择对应人物</option>{people.map((person) => <option key={person.id} value={person.id}>{person.displayName} #{person.id}{person.branchName && ` · ${person.branchName}`}</option>)}</select>
        {hasMore && <p className="text-xs text-gray-500">人物较多，请输入姓名或支系缩小范围。</p>}</>}
      <div className="flex gap-3"><button type="button" disabled={busy || !personId} onClick={() => void save()} className="rounded-lg bg-emerald-600 px-3 py-2 text-sm text-white disabled:opacity-50">确认关联</button><button type="button" onClick={() => setMemberId(0)} className="text-sm text-gray-600">取消</button></div>
    </div>}
  </section>;
}
