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
          setMessage(err instanceof Error ? err.message : '家庭孩子成员加载失败');
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
      setMessage('请输入家庭名称');
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
      setMessage('家庭已新增');
    } catch (err) {
      setMessage(err instanceof Error ? err.message : '新增家庭失败');
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
      setMessage(`已加入「${joined.familyGroupName}」，同步名下孩子 ${joined.linkedChildCount} 名`);
    } catch (err) {
      setMessage(err instanceof Error ? err.message : '加入家庭组失败');
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
      setMessage(`已将「${childToRemove.name}」从当前家庭移除`);
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
      setMessage('请输入家庭名称');
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
      setMessage(`已更新家庭「${updated.name}」`);
      setFamilyToEdit(null);
      setEditName('');
      setEditDescription('');
    } catch (err) {
      setMessage(err instanceof Error ? err.message : '修改家庭失败');
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
      setMessage(`已删除家庭「${familyToDelete.name}」，孩子全局信息已保留`);
      setFamilyToDelete(null);
      await refreshGroups();
    } catch (err) {
      setMessage(err instanceof Error ? err.message : '删除家庭失败');
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
          <h2 className="text-2xl font-bold text-gray-900">家庭管理</h2>
          <p className="text-sm text-gray-500 mt-1">
            当前家庭组：{selectedGroupLabel}{error ? `，${error}` : ''}
          </p>
        </div>
      </div>

      <div className="grid grid-cols-1 gap-3 sm:grid-cols-3 sm:gap-4">
        <StatCard title="家庭组" value={groups.length} icon="🏠" color="blue" />
        <StatCard title="我管理的" value={ownedCount} icon="👤" color="green" />
        <StatCard title="当前选择" value={selectedGroup?.name || '-'} icon="✅" color="orange" />
      </div>

      <Card className="p-4 sm:p-5">
        <div className="mb-4 flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
          <div>
            <h3 className="text-lg font-semibold text-gray-900">孩子成员</h3>
            <p className="mt-1 text-sm text-gray-500">查看当前家庭中的孩子信息及其归属家长</p>
          </div>
          <span className="rounded-full bg-blue-50 px-3 py-1 text-sm font-medium text-blue-700">
            {familyChildren.length} 名
          </span>
        </div>
        {childrenLoading ? (
          <div className="py-8 text-center text-sm text-gray-400">加载孩子成员中...</div>
        ) : familyChildren.length === 0 ? (
          <div className="py-8 text-center text-sm text-gray-400">当前家庭暂无孩子成员</div>
        ) : (
          <div className="grid grid-cols-1 gap-3 lg:grid-cols-2">
            {familyChildren.map((child) => (
              <div key={child.id} className="rounded-lg border border-gray-200 p-4">
                <div className="flex items-start justify-between gap-3">
                  <div className="min-w-0">
                    <p className="truncate font-semibold text-gray-900">{child.name}</p>
                    <p className="mt-1 text-sm text-gray-500">
                      归属家长：{child.parentNames || '未关联'}
                    </p>
                  </div>
                  {canManageSelectedGroup && (
                    <button
                      type="button"
                      onClick={() => setChildToRemove(child)}
                      className="shrink-0 rounded-md px-2.5 py-1.5 text-sm text-red-600 hover:bg-red-50"
                    >
                      移除
                    </button>
                  )}
                </div>
                <div className="mt-3 grid grid-cols-1 gap-2 text-sm sm:grid-cols-3 sm:text-center">
                  <div className="rounded-md bg-blue-50 px-2 py-2 text-blue-700">积分 {child.score ?? 0}</div>
                  <div className="rounded-md bg-green-50 px-2 py-2 text-green-700">现金 {child.cash ?? 0}</div>
                  <div className="rounded-md bg-orange-50 px-2 py-2 text-orange-700">物品 {child.items ?? 0}</div>
                </div>
              </div>
            ))}
          </div>
        )}
      </Card>

      <div className="grid grid-cols-1 xl:grid-cols-3 gap-6">
        <Card className="xl:col-span-2 p-4 sm:p-5">
          <div className="flex items-center justify-between mb-4">
            <h3 className="text-lg font-semibold text-gray-900">家庭组列表</h3>
          </div>
          <div className="space-y-3">
            {groups.map((group) => (
              <div
                key={group.id}
                className={`rounded-lg border px-4 py-3 transition-colors ${
                  selectedGroupId === group.id
                    ? 'border-[#4A90D9] bg-[#4A90D9]/5'
                    : 'border-gray-200 hover:bg-gray-50'
                }`}
              >
                <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
                  <div className="min-w-0">
                    <p className="font-semibold text-gray-900">{group.name}</p>
                    <p className="text-sm text-gray-500">ID：{group.id} · 角色：{group.role || 'member'}</p>
                  </div>
                  <div className="flex items-center gap-2 self-start sm:self-center">
                    {(group.role === 'owner' || group.createdBy === appUserId) && (
                      <>
                        <button
                          type="button"
                          onClick={() => openEditFamily(group)}
                          className="rounded-md px-2.5 py-1.5 text-sm text-gray-600 hover:bg-gray-100"
                        >
                          改名
                        </button>
                        <button
                          type="button"
                          onClick={() => setFamilyToDelete({ id: group.id, name: group.name })}
                          className="rounded-md px-2.5 py-1.5 text-sm text-red-600 hover:bg-red-50"
                        >
                          删除
                        </button>
                      </>
                    )}
                    <button
                      type="button"
                      onClick={() => selectGroup(group.id)}
                      className="rounded-md px-2.5 py-1.5 text-sm text-[#4A90D9] hover:bg-[#4A90D9]/10"
                    >
                      {selectedGroupId === group.id ? '当前' : '选择'}
                    </button>
                  </div>
                </div>
                {group.description && <p className="text-sm text-gray-500 mt-2">{group.description}</p>}
              </div>
            ))}
            {groups.length === 0 && (
              <div className="text-center py-10 text-gray-400">暂无家庭组</div>
            )}
          </div>
        </Card>

        <div className="space-y-6">
          <Card className="p-4 sm:p-5">
            <h3 className="text-lg font-semibold text-gray-900 mb-4">新增家庭</h3>
            <div className="space-y-3">
              <input
                value={newName}
                onChange={(event) => setNewName(event.target.value)}
                placeholder="家庭名称"
                className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-[#4A90D9]"
              />
              <textarea
                value={newDescription}
                onChange={(event) => setNewDescription(event.target.value)}
                placeholder="说明，可选"
                rows={3}
                className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-[#4A90D9]"
              />
              <button disabled={busy} onClick={handleCreate} className="btn-primary w-full">
                新增家庭
              </button>
            </div>
          </Card>

          <Card className="p-4 sm:p-5">
            <h3 className="text-lg font-semibold text-gray-900 mb-4">加入家庭组</h3>
            <div className="space-y-3">
              <input
                value={joinInviteCode}
                onChange={(event) => setJoinInviteCode(event.target.value.replace(/\D/g, '').slice(0, 8))}
                inputMode="numeric"
                maxLength={8}
                placeholder="输入 8 位数字邀请码"
                className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-[#4A90D9]"
              />
              <p className="text-xs text-gray-500">加入后会自动把你名下的全部孩子同步到该家庭组。</p>
              <button disabled={busy} onClick={handleJoin} className="btn-primary w-full">
                加入家庭组
              </button>
            </div>
          </Card>

          <Card className="p-4 sm:p-5">
            <h3 className="text-lg font-semibold text-gray-900 mb-4">邀请</h3>
            {selectedGroup && (selectedGroup.role === 'owner' || selectedGroup.createdBy === appUserId) && invite ? (
              <div className="space-y-3">
                <div className="rounded-lg border border-blue-200 bg-blue-50 p-4 text-center">
                  <p className="text-xs text-blue-600 mb-1">8 位家庭邀请码</p>
                  <p className="text-3xl font-bold tracking-[0.28em] text-blue-800">{invite.inviteCode}</p>
                </div>
                <div className="flex justify-center rounded-lg border border-gray-200 bg-white p-3">
                  <img src={invite.qrImageUrl} alt="邀请二维码" className="h-40 w-40" />
                </div>
                <button
                  onClick={handleCopyInvite}
                  className="w-full rounded-lg border border-gray-300 px-4 py-2 text-sm font-medium text-gray-700 hover:bg-gray-50"
                >
                  复制邀请码
                </button>
                <p className="break-all text-xs text-gray-400">邀请链接：{invite.inviteUrl}</p>
              </div>
            ) : (
              <div className="text-sm text-gray-400">
                {selectedGroup ? '只有家庭组管理员可以生成邀请码' : '请选择一个家庭组'}
              </div>
            )}
          </Card>
        </div>
      </div>
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
        title="修改家庭"
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
            placeholder="家庭名称"
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
        title="删除家庭"
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
          确认删除「{familyToDelete?.name}」吗？这只删除家庭关系，孩子、归属家长和积分账户会保留。
        </p>
      </Modal>
    </div>
  );
}
