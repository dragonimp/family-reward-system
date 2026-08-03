import { useEffect, useMemo, useState } from 'react';
import { useSearchParams } from 'react-router-dom';
import { Card, StatCard } from '../components/Card';
import { createFamilyGroup, getFamilyGroupInvite, joinFamilyGroup } from '../services';
import { useAuth } from '../contexts/AuthContext';
import { useFamilyGroup } from '../contexts/FamilyGroupContext';
import type { FamilyGroupInvite } from '../types';

export default function FamilyGroups() {
  const { userId } = useAuth();
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
  const [joinGroupId, setJoinGroupId] = useState(searchParams.get('joinFamilyGroupId') || '');
  const [invite, setInvite] = useState<FamilyGroupInvite | null>(null);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState('');

  const selectedGroupLabel = selectedGroup
    ? `${selectedGroup.name} #${selectedGroup.id}`
    : '未选择';

  const ownedCount = useMemo(
    () => groups.filter((group) => group.role === 'owner' || group.createdBy === userId).length,
    [groups, userId],
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
        userId: userId || undefined,
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
    const id = Number.parseInt(joinGroupId, 10);
    if (!Number.isFinite(id) || id <= 0) {
      setMessage('请输入有效的家庭组 ID');
      return;
    }

    try {
      setBusy(true);
      setMessage('');
      await joinFamilyGroup({ familyGroupId: id, userId: userId || undefined, role: 'member' });
      await refreshGroups();
      selectGroup(id);
      setSearchParams({});
      setMessage('已加入家庭组');
    } catch (err) {
      setMessage(err instanceof Error ? err.message : '加入家庭组失败');
    } finally {
      setBusy(false);
    }
  };

  const handleCopyInvite = async () => {
    if (!invite?.inviteUrl) return;
    try {
      await navigator.clipboard.writeText(invite.inviteUrl);
      setMessage('邀请链接已复制');
    } catch {
      setMessage(invite.inviteUrl);
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
          <h2 className="text-2xl font-bold text-gray-900">家庭组管理</h2>
          <p className="text-sm text-gray-500 mt-1">
            当前家庭组：{selectedGroupLabel}{error ? `，${error}` : ''}
          </p>
        </div>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
        <StatCard title="家庭组" value={groups.length} icon="🏠" color="blue" />
        <StatCard title="我管理的" value={ownedCount} icon="👤" color="green" />
        <StatCard title="当前选择" value={selectedGroup?.name || '-'} icon="✅" color="orange" />
      </div>

      <div className="grid grid-cols-1 xl:grid-cols-3 gap-6">
        <Card className="xl:col-span-2 p-5">
          <div className="flex items-center justify-between mb-4">
            <h3 className="text-lg font-semibold text-gray-900">家庭组列表</h3>
          </div>
          <div className="space-y-3">
            {groups.map((group) => (
              <button
                key={group.id}
                type="button"
                onClick={() => selectGroup(group.id)}
                className={`w-full text-left rounded-lg border px-4 py-3 transition-colors ${
                  selectedGroupId === group.id
                    ? 'border-[#4A90D9] bg-[#4A90D9]/5'
                    : 'border-gray-200 hover:bg-gray-50'
                }`}
              >
                <div className="flex items-center justify-between gap-3">
                  <div>
                    <p className="font-semibold text-gray-900">{group.name}</p>
                    <p className="text-sm text-gray-500">ID：{group.id} · 角色：{group.role || 'member'}</p>
                  </div>
                  <span className="text-sm text-[#4A90D9]">{selectedGroupId === group.id ? '当前' : '选择'}</span>
                </div>
                {group.description && <p className="text-sm text-gray-500 mt-2">{group.description}</p>}
              </button>
            ))}
            {groups.length === 0 && (
              <div className="text-center py-10 text-gray-400">暂无家庭组</div>
            )}
          </div>
        </Card>

        <div className="space-y-6">
          <Card className="p-5">
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

          <Card className="p-5">
            <h3 className="text-lg font-semibold text-gray-900 mb-4">加入家庭组</h3>
            <div className="space-y-3">
              <input
                value={joinGroupId}
                onChange={(event) => setJoinGroupId(event.target.value)}
                inputMode="numeric"
                placeholder="输入家庭组 ID"
                className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-[#4A90D9]"
              />
              <button disabled={busy} onClick={handleJoin} className="btn-primary w-full">
                加入家庭组
              </button>
            </div>
          </Card>

          <Card className="p-5">
            <h3 className="text-lg font-semibold text-gray-900 mb-4">邀请</h3>
            {invite ? (
              <div className="space-y-3">
                <div className="rounded-lg border border-gray-200 bg-gray-50 p-3 break-all text-sm text-gray-700">
                  {invite.inviteUrl}
                </div>
                <div className="flex justify-center rounded-lg border border-gray-200 bg-white p-3">
                  <img src={invite.qrImageUrl} alt="邀请二维码" className="h-40 w-40" />
                </div>
                <button
                  onClick={handleCopyInvite}
                  className="w-full rounded-lg border border-gray-300 px-4 py-2 text-sm font-medium text-gray-700 hover:bg-gray-50"
                >
                  复制邀请链接
                </button>
              </div>
            ) : (
              <div className="text-sm text-gray-400">请选择一个家庭组</div>
            )}
          </Card>
        </div>
      </div>
    </div>
  );
}
