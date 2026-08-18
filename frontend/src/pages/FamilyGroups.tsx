import { useEffect, useMemo, useState } from 'react';
import { useSearchParams } from 'react-router-dom';
import { Card, StatCard } from '../components/Card';
import { Modal } from '../components/Modal';
import {
  createFamilyGroup,
  deleteFamilyGroup,
  getFamilyGroupChildren,
  getFamilyGroupInvite,
  joinFamilyGroup,
  removeFamilyGroupChild,
  updateFamilyGroup,
} from '../services';
import { useAuth } from '../contexts/AuthContext';
import { useFamilyGroup } from '../contexts/FamilyGroupContext';
import type { Child, FamilyGroup, FamilyGroupInvite } from '../types';

type FamilyTab = 'view' | 'create' | 'invite' | 'join';

export default function FamilyGroups() {
  const { userId, appProfile } = useAuth();
  const appUserId = appProfile?.appUserId || userId;
  const {
    groups,
    selectedGroupId,
    selectedGroup,
    loading,
    error,
    selectGroup,
    refreshGroups,
  } = useFamilyGroup();
  const [searchParams, setSearchParams] = useSearchParams();
  const [activeTab, setActiveTab] = useState<FamilyTab>(searchParams.get('inviteCode') ? 'join' : 'view');
  const [newName, setNewName] = useState('');
  const [newDescription, setNewDescription] = useState('');
  const [joinInviteCode, setJoinInviteCode] = useState(searchParams.get('inviteCode') || '');
  const [invite, setInvite] = useState<FamilyGroupInvite | null>(null);
  const [familyChildren, setFamilyChildren] = useState<Child[]>([]);
  const [childrenLoading, setChildrenLoading] = useState(false);
  const [childToRemove, setChildToRemove] = useState<Child | null>(null);
  const [familyToEdit, setFamilyToEdit] = useState<FamilyGroup | null>(null);
  const [editName, setEditName] = useState('');
  const [editDescription, setEditDescription] = useState('');
  const [familyToDelete, setFamilyToDelete] = useState<{ id: number; name: string } | null>(null);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState('');

  const selectedGroupLabel = selectedGroup
    ? `${selectedGroup.name} #${selectedGroup.id}`
    : '未选择';

  const ownedCount = useMemo(
    () => groups.filter((group) => group.role === 'owner' || group.createdBy === appUserId).length,
    [groups, appUserId],
  );
  const canManageSelectedGroup = Boolean(
    selectedGroup && (selectedGroup.role === 'owner' || selectedGroup.createdBy === appUserId),
  );

  useEffect(() => {
    if (!selectedGroupId) {
      setInvite(null);
      return;
    }

    let cancelled = false;
    getFamilyGroupInvite(selectedGroupId)
      .then((payload) => {
        if (!cancelled) setInvite(payload);
      })
      .catch(() => {
        if (!cancelled) setInvite(null);
      });

    return () => {
      cancelled = true;
    };
  }, [selectedGroupId]);

  useEffect(() => {
    if (!selectedGroupId) {
      setFamilyChildren([]);
      return;
    }

    let cancelled = false;
    setChildrenLoading(true);
    getFamilyGroupChildren(selectedGroupId)
      .then((children) => {
        if (!cancelled) setFamilyChildren(Array.isArray(children) ? children : []);
      })
      .catch((err) => {
        if (!cancelled) {
          setFamilyChildren([]);
          setMessage(err instanceof Error ? err.message : '圈子孩子成员加载失败');
        }
      })
      .finally(() => {
        if (!cancelled) setChildrenLoading(false);
      });

    return () => {
      cancelled = true;
    };
  }, [selectedGroupId]);

  const handleCreate = async () => {
    const trimmed = newName.trim();
    if (!trimmed) {
      setMessage('请输入圈子名称');
      return;
    }

    try {
      setBusy(true);
      setMessage('');
      const created = await createFamilyGroup({
        name: trimmed,
        description: newDescription.trim(),
      });
      await refreshGroups();
      selectGroup(created.id);
      setNewName('');
      setNewDescription('');
      setActiveTab('view');
      setMessage('圈子已新增');
    } catch (err) {
      setMessage(err instanceof Error ? err.message : '新增圈子失败');
    } finally {
      setBusy(false);
    }
  };

  const handleJoin = async () => {
    const inviteCode = joinInviteCode.replace(/\D/g, '');
    if (inviteCode.length !== 8) {
      setMessage('请输入 8 位数字邀请码');
      return;
    }

    try {
      setBusy(true);
      setMessage('');
      const joined = await joinFamilyGroup({ inviteCode });
      await refreshGroups();
      selectGroup(joined.familyGroupId);
      setSearchParams({});
      setJoinInviteCode('');
      setActiveTab('view');
      setMessage(`已加入「${joined.familyGroupName}」，同步名下孩子 ${joined.linkedChildCount} 名`);
    } catch (err) {
      setMessage(err instanceof Error ? err.message : '加入圈子失败');
    } finally {
      setBusy(false);
    }
  };

  const handleCopyInvite = async () => {
    if (!invite?.inviteCode) return;
    try {
      await navigator.clipboard.writeText(invite.inviteCode);
      setMessage('邀请码已复制');
    } catch {
      setMessage(`邀请码：${invite.inviteCode}`);
    }
  };

  const handleRemoveChild = async () => {
    if (!selectedGroupId || !childToRemove) return;
    try {
      setBusy(true);
      await removeFamilyGroupChild(selectedGroupId, childToRemove.id);
      setFamilyChildren((children) => children.filter((child) => child.id !== childToRemove.id));
      setMessage(`已将「${childToRemove.name}」从当前圈子移除`);
      setChildToRemove(null);
    } catch (err) {
      setMessage(err instanceof Error ? err.message : '移除孩子成员失败');
    } finally {
      setBusy(false);
    }
  };

  const openEditFamily = (group: FamilyGroup) => {
    setFamilyToEdit(group);
    setEditName(group.name);
    setEditDescription(group.description || '');
    setMessage('');
  };

  const handleUpdateFamily = async () => {
    if (!familyToEdit) return;
    const trimmed = editName.trim();
    if (!trimmed) {
      setMessage('请输入圈子名称');
      return;
    }

    try {
      setBusy(true);
      setMessage('');
      const updated = await updateFamilyGroup(familyToEdit.id, {
        name: trimmed,
        description: editDescription.trim(),
      });
      await refreshGroups();
      selectGroup(updated.id);
      setMessage(`已更新圈子「${updated.name}」`);
      setFamilyToEdit(null);
      setEditName('');
      setEditDescription('');
    } catch (err) {
      setMessage(err instanceof Error ? err.message : '修改圈子失败');
    } finally {
      setBusy(false);
    }
  };

  const handleDeleteFamily = async () => {
    if (!familyToDelete) return;
    try {
      setBusy(true);
      setMessage('');
      await deleteFamilyGroup(familyToDelete.id);
      setMessage(`已删除圈子「${familyToDelete.name}」，孩子全局信息已保留`);
      setFamilyToDelete(null);
      await refreshGroups();
    } catch (err) {
      setMessage(err instanceof Error ? err.message : '删除圈子失败');
    } finally {
      setBusy(false);
    }
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center py-20">
        <div className="inline-block animate-spin rounded-full h-10 w-10 border-4 border-[#4A90D9] border-t-transparent"></div>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {message && (
        <div className="rounded-lg border border-blue-100 bg-blue-50 px-4 py-3 text-sm text-blue-700">
          {message}
        </div>
      )}

      <div className="flex flex-col gap-3 md:flex-row md:items-center md:justify-between">
        <div>
          <h2 className="text-2xl font-bold text-gray-900">圈子管理</h2>
          <p className="text-sm text-gray-500 mt-1">
            当前圈子：{selectedGroupLabel}{error ? `，${error}` : ''}
          </p>
        </div>
      </div>

      <div className="grid grid-cols-1 gap-3 sm:grid-cols-3 sm:gap-4">
        <StatCard title="圈子" value={groups.length} icon="👥" color="blue" />
        <StatCard title="我管理的" value={ownedCount} icon="👤" color="green" />
        <StatCard title="当前选择" value={selectedGroup?.name || '-'} icon="✅" color="orange" />
      </div>

      <Card className="overflow-hidden p-0">
        <div className="overflow-x-auto border-b border-gray-200 px-3 pt-3 sm:px-5 sm:pt-4">
          <div role="tablist" aria-label="圈子管理功能" className="flex min-w-max gap-1">
            {([
              ['view', '查看圈子'],
              ['create', '新增圈子'],
              ['invite', '邀请他人加入圈子'],
              ['join', '加入其他圈子'],
            ] as Array<[FamilyTab, string]>).map(([tab, label]) => (
              <button key={tab} type="button" role="tab" aria-selected={activeTab === tab} onClick={() => setActiveTab(tab)} className={`border-b-2 px-3 py-2.5 text-sm font-medium ${activeTab === tab ? 'border-[#2878c7] text-[#2369ad]' : 'border-transparent text-gray-500 hover:text-gray-800'}`}>{label}</button>
            ))}
          </div>
        </div>

        <div className="p-4 sm:p-5">
          {activeTab === 'view' && <div className="space-y-5">
            <div className="flex flex-col gap-3 border-b border-gray-100 pb-5 sm:flex-row sm:items-end sm:justify-between">
              <div className="min-w-0 flex-1">
                <label htmlFor="family-view-select" className="mb-1.5 block text-sm font-medium text-gray-700">选择要查看的圈子</label>
                <select id="family-view-select" value={selectedGroupId ?? ''} onChange={(event) => selectGroup(Number(event.target.value))} disabled={groups.length === 0} className="w-full rounded-md border border-gray-300 bg-white px-3 py-2.5 text-sm text-gray-700 focus:border-[#4A90D9] focus:outline-none focus:ring-2 focus:ring-[#4A90D9]/20 sm:max-w-md">
                  {groups.length === 0 && <option value="">暂无圈子</option>}
                  {groups.map((group) => <option key={group.id} value={group.id}>{group.name}（{group.role === 'owner' || group.createdBy === appUserId ? '我创建的' : '我加入的'}）</option>)}
                </select>
              </div>
              {selectedGroup && <div className="text-sm text-gray-500">圈子 ID：{selectedGroup.id} · {canManageSelectedGroup ? '管理员' : '成员'}</div>}
            </div>

            {selectedGroup ? <>
              <section className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
                <div><h3 className="text-lg font-semibold text-gray-900">{selectedGroup.name}</h3><p className="mt-1 text-sm text-gray-500">{selectedGroup.description || '暂无圈子说明'}</p></div>
                {canManageSelectedGroup && <div className="flex gap-2"><button type="button" onClick={() => openEditFamily(selectedGroup)} className="rounded-md border border-gray-300 px-3 py-2 text-sm text-gray-700 hover:bg-gray-50">编辑</button><button type="button" onClick={() => setFamilyToDelete({ id: selectedGroup.id, name: selectedGroup.name })} className="rounded-md border border-red-200 px-3 py-2 text-sm text-red-600 hover:bg-red-50">删除</button></div>}
              </section>

              <section aria-labelledby="family-children-title">
                <div className="mb-3 flex items-center justify-between"><div><h3 id="family-children-title" className="font-semibold text-gray-900">孩子信息</h3><p className="mt-1 text-sm text-gray-500">孩子归属家长关系不会因切换圈子而改变</p></div><span className="text-sm font-medium text-blue-700">{familyChildren.length} 名</span></div>
                {childrenLoading ? <div className="py-8 text-center text-sm text-gray-400">加载孩子信息中...</div> : familyChildren.length === 0 ? <div className="border-t border-gray-100 py-8 text-center text-sm text-gray-400">当前圈子暂无孩子</div> : <div className="divide-y divide-gray-100 border-y border-gray-100">{familyChildren.map((child) => <div key={child.id} className="flex flex-col gap-3 py-4 sm:flex-row sm:items-center sm:justify-between"><div className="min-w-0"><p className="font-medium text-gray-900">{child.name}</p><p className="mt-1 text-sm text-gray-500">归属家长：{child.parentNames || '未关联'}</p></div><div className="flex flex-wrap items-center gap-3 text-sm"><span className="text-blue-700">积分 {child.score ?? 0}</span><span className="text-green-700">现金 {child.cash ?? 0}</span><span className="text-orange-700">物品 {child.items ?? 0}</span>{canManageSelectedGroup && <button type="button" onClick={() => setChildToRemove(child)} className="text-red-600">移除</button>}</div></div>)}</div>}
              </section>

            </> : <div className="py-12 text-center text-sm text-gray-400">暂无圈子，请先新增或加入圈子</div>}
          </div>}

          {activeTab === 'create' && <div className="mx-auto max-w-xl space-y-4"><div><h3 className="text-lg font-semibold text-gray-900">新增圈子</h3><p className="mt-1 text-sm text-gray-500">创建后，你将成为圈子管理员。</p></div><label className="block text-sm font-medium text-gray-700">圈子名称<input value={newName} onChange={(event) => setNewName(event.target.value)} className="mt-1 w-full rounded-md border border-gray-300 px-3 py-2.5 focus:outline-none focus:ring-2 focus:ring-[#4A90D9]" /></label><label className="block text-sm font-medium text-gray-700">圈子说明<textarea value={newDescription} onChange={(event) => setNewDescription(event.target.value)} rows={3} className="mt-1 w-full rounded-md border border-gray-300 px-3 py-2.5 focus:outline-none focus:ring-2 focus:ring-[#4A90D9]" /></label><button type="button" disabled={busy} onClick={handleCreate} className="btn-primary">{busy ? '新增中...' : '新增圈子'}</button></div>}

          {activeTab === 'invite' && <div className="mx-auto max-w-xl space-y-4"><div><h3 className="text-lg font-semibold text-gray-900">邀请他人加入圈子</h3><p className="mt-1 text-sm text-gray-500">先选择你管理的圈子，再分享邀请码或二维码。</p></div><label className="block text-sm font-medium text-gray-700">邀请加入<select value={canManageSelectedGroup ? selectedGroupId ?? '' : ''} onChange={(event) => selectGroup(Number(event.target.value))} className="mt-1 w-full rounded-md border border-gray-300 bg-white px-3 py-2.5"><option value="">请选择圈子</option>{groups.filter((group) => group.role === 'owner' || group.createdBy === appUserId).map((group) => <option key={group.id} value={group.id}>{group.name}</option>)}</select></label>{canManageSelectedGroup && invite ? <div className="space-y-4"><div className="border border-blue-200 bg-blue-50 p-4 text-center"><p className="mb-1 text-xs text-blue-600">8 位圈子邀请码</p><p className="text-3xl font-bold tracking-[0.28em] text-blue-800">{invite.inviteCode}</p></div><div className="flex justify-center border border-gray-200 bg-white p-3"><img src={invite.qrImageUrl} alt="邀请二维码" className="h-40 w-40" /></div><button type="button" onClick={handleCopyInvite} className="w-full rounded-md border border-gray-300 px-4 py-2 text-sm font-medium text-gray-700 hover:bg-gray-50">复制邀请码</button><p className="break-all text-xs text-gray-400">邀请链接：{invite.inviteUrl}</p></div> : <div className="py-8 text-center text-sm text-gray-400">请选择一个你创建的圈子</div>}</div>}

          {activeTab === 'join' && <div className="mx-auto max-w-xl space-y-4"><div><h3 className="text-lg font-semibold text-gray-900">加入其他圈子</h3><p className="mt-1 text-sm text-gray-500">使用圈子管理员提供的 8 位数字邀请码。</p></div><label className="block text-sm font-medium text-gray-700">圈子邀请码<input value={joinInviteCode} onChange={(event) => setJoinInviteCode(event.target.value.replace(/\D/g, '').slice(0, 8))} inputMode="numeric" maxLength={8} placeholder="请输入 8 位数字" className="mt-1 w-full rounded-md border border-gray-300 px-3 py-2.5 tracking-widest focus:outline-none focus:ring-2 focus:ring-[#4A90D9]" /></label><p className="text-xs text-gray-500">加入后会自动把你名下的全部孩子同步到该圈子。</p><button type="button" disabled={busy} onClick={handleJoin} className="btn-primary">{busy ? '加入中...' : '加入圈子'}</button></div>}
        </div>
      </Card>
      <Modal
        isOpen={Boolean(childToRemove)}
        onClose={() => setChildToRemove(null)}
        title="移除孩子成员"
        footer={
          <>
            <button
              type="button"
              onClick={() => setChildToRemove(null)}
              className="rounded-lg border border-gray-300 px-4 py-2 text-sm text-gray-700 hover:bg-gray-50"
            >
              取消
            </button>
            <button
              type="button"
              disabled={busy}
              onClick={handleRemoveChild}
              className="rounded-lg bg-red-600 px-4 py-2 text-sm font-medium text-white hover:bg-red-700 disabled:opacity-60"
            >
              {busy ? '移除中...' : '确认移除'}
            </button>
          </>
        }
      >
        <p className="text-sm text-gray-600">
          确认将「{childToRemove?.name}」从「{selectedGroup?.name}」移除吗？孩子与归属家长的全局关系会保留。
        </p>
      </Modal>
      <Modal
        isOpen={Boolean(familyToEdit)}
        onClose={() => setFamilyToEdit(null)}
        title="修改圈子"
        footer={
          <>
            <button
              type="button"
              onClick={() => setFamilyToEdit(null)}
              className="rounded-lg border border-gray-300 px-4 py-2 text-sm text-gray-700 hover:bg-gray-50"
            >
              取消
            </button>
            <button
              type="button"
              disabled={busy}
              onClick={handleUpdateFamily}
              className="btn-primary"
            >
              {busy ? '保存中...' : '保存'}
            </button>
          </>
        }
      >
        <div className="space-y-3">
          <input
            value={editName}
            onChange={(event) => setEditName(event.target.value)}
            placeholder="圈子名称"
            className="w-full rounded-lg border border-gray-300 px-3 py-2 focus:outline-none focus:ring-2 focus:ring-[#4A90D9]"
          />
          <textarea
            value={editDescription}
            onChange={(event) => setEditDescription(event.target.value)}
            placeholder="说明，可选"
            rows={3}
            className="w-full rounded-lg border border-gray-300 px-3 py-2 focus:outline-none focus:ring-2 focus:ring-[#4A90D9]"
          />
        </div>
      </Modal>
      <Modal
        isOpen={Boolean(familyToDelete)}
        onClose={() => setFamilyToDelete(null)}
        title="删除圈子"
        footer={
          <>
            <button
              type="button"
              onClick={() => setFamilyToDelete(null)}
              className="rounded-lg border border-gray-300 px-4 py-2 text-sm text-gray-700 hover:bg-gray-50"
            >
              取消
            </button>
            <button
              type="button"
              disabled={busy}
              onClick={handleDeleteFamily}
              className="rounded-lg bg-red-600 px-4 py-2 text-sm font-medium text-white hover:bg-red-700 disabled:opacity-60"
            >
              {busy ? '删除中...' : '确认删除'}
            </button>
          </>
        }
      >
        <p className="text-sm text-gray-600">
          确认删除「{familyToDelete?.name}」吗？这只删除圈子关系，孩子、归属家长和积分账户会保留。
        </p>
      </Modal>
    </div>
  );
}
