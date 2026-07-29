import { Link } from 'react-router-dom';
import { useState } from 'react';
import { getUserCenterUrl } from '../auth';
import { Modal } from './Modal';
import { useFamilyGroup } from '../contexts/FamilyGroupContext';
import type { AuthUser } from '../types';

interface UserMenuProps {
  user: AuthUser | null;
  userId: string | null;
  onLogout: () => void;
}

export default function UserMenu({ user, userId, onLogout }: UserMenuProps) {
  const displayName = user?.displayName || user?.username || userId || '用户';
  const avatar = user?.iconEmoji || displayName.slice(0, 1).toUpperCase();
  const { groups, selectedGroupId, selectedGroup, loading, error, selectGroup, createGroup } = useFamilyGroup();
  const [newGroupName, setNewGroupName] = useState('');
  const [creating, setCreating] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [showCreateGroupModal, setShowCreateGroupModal] = useState(false);

  const handleCreateGroup = async () => {
    const name = newGroupName.trim();
    if (!name) {
      setMessage('请输入家庭组名称');
      return;
    }
    try {
      setCreating(true);
      setMessage(null);
      await createGroup(name);
      setNewGroupName('');
      setMessage('家庭组已创建');
      setShowCreateGroupModal(false);
    } catch (err) {
      console.error('家庭组创建失败:', err);
      setMessage(err instanceof Error ? err.message : '家庭组创建失败');
    } finally {
      setCreating(false);
    }
  };

  return (
    <>
      <details className="relative group flex-shrink-0">
        <summary
          className="list-none [&::-webkit-details-marker]:hidden flex items-center gap-2 px-2 py-1.5 rounded-lg text-sm text-gray-600 hover:bg-gray-100 cursor-pointer select-none"
          aria-label="用户菜单"
        >
          <span className="w-7 h-7 rounded-full bg-[#4A90D9]/10 text-[#4A90D9] flex items-center justify-center text-sm font-semibold">
            {avatar}
          </span>
          <span className="hidden md:block max-w-[120px] truncate">{displayName}</span>
          <span className="text-[10px] text-gray-400">▼</span>
        </summary>
        <div className="absolute right-0 mt-2 w-72 rounded-lg border border-gray-200 bg-white p-2 shadow-lg z-[60]">
          <details className="group/family">
            <summary className="list-none [&::-webkit-details-marker]:hidden flex items-center justify-between gap-2 px-3 py-2 rounded-md text-sm text-gray-700 hover:bg-gray-50 cursor-pointer select-none">
              <span className="flex items-center gap-2 min-w-0">
                <span>🏠</span>
                <span>家庭组管理</span>
              </span>
              <span className="flex items-center gap-2 min-w-0 text-xs text-gray-400">
                <span className="max-w-[92px] truncate">{loading ? '加载中' : selectedGroup?.name || '未选择'}</span>
                <span className="group-open/family:rotate-180 transition-transform">⌄</span>
              </span>
            </summary>
            <div className="mt-1 mb-2 rounded-md bg-gray-50 p-1">
              {error && <div className="px-2 py-1.5 text-xs text-red-600">{error}</div>}
              {!loading && groups.length === 0 && (
                <div className="px-2 py-1.5 text-xs text-gray-500">暂无可用家庭组</div>
              )}
              {groups.map((group) => {
                const active = group.id === selectedGroupId;
                return (
                  <button
                    key={group.id}
                    type="button"
                    onClick={() => selectGroup(group.id)}
                    className={`w-full flex items-center justify-between gap-2 px-2 py-2 rounded-md text-sm text-left transition-colors ${
                      active ? 'bg-[#4A90D9]/10 text-[#4A90D9]' : 'text-gray-700 hover:bg-white'
                    }`}
                  >
                    <span className="truncate">{group.name}</span>
                    {active && <span className="text-xs font-medium">当前</span>}
                  </button>
                );
              })}
              <button
                type="button"
                onClick={() => {
                  setMessage(null);
                  setShowCreateGroupModal(true);
                }}
                className="mt-1 w-full flex items-center justify-center gap-2 border-t border-gray-200 px-2 py-2.5 text-sm font-medium text-[#4A90D9] hover:bg-white rounded-md"
              >
                <span>＋</span>
                <span>新增家庭组</span>
              </button>
              {message && <div className="mt-1 px-2 text-xs text-gray-500">{message}</div>}
            </div>
          </details>
          <div className="my-1 border-t border-gray-100" />
          <Link to="/settings" className="flex items-center gap-2 px-3 py-2 rounded-md text-sm text-gray-700 hover:bg-gray-50">
            <span>⚙️</span>
            <span>系统设置</span>
          </Link>
          <a href={getUserCenterUrl('info')} className="flex items-center gap-2 px-3 py-2 rounded-md text-sm text-gray-700 hover:bg-gray-50">
            <span>✎</span>
            <span>修改信息</span>
          </a>
          <a href={getUserCenterUrl('password')} className="flex items-center gap-2 px-3 py-2 rounded-md text-sm text-gray-700 hover:bg-gray-50">
            <span>🔑</span>
            <span>修改密码</span>
          </a>
          <div className="my-1 border-t border-gray-100" />
          <a
            href="/auth/logout"
            onClick={onLogout}
            className="flex items-center gap-2 px-3 py-2 rounded-md text-sm text-red-600 hover:bg-red-50"
          >
            <span>↩</span>
            <span>退出登录</span>
          </a>
        </div>
      </details>
      <Modal
        isOpen={showCreateGroupModal}
        onClose={() => setShowCreateGroupModal(false)}
        title="新增家庭组"
        footer={
          <>
            <button
              type="button"
              onClick={() => setShowCreateGroupModal(false)}
              className="px-4 py-2 rounded-lg border border-gray-300 text-sm text-gray-700 hover:bg-gray-50"
            >
              取消
            </button>
            <button
              type="button"
              onClick={handleCreateGroup}
              disabled={creating}
              className="px-4 py-2 rounded-lg bg-[#4A90D9] text-white text-sm font-medium hover:bg-[#357ABD] disabled:opacity-60"
            >
              {creating ? '新增中' : '确认新增'}
            </button>
          </>
        }
      >
        <label className="block text-sm font-medium text-gray-700 mb-2">家庭组名称</label>
        <input
          value={newGroupName}
          onChange={(event) => setNewGroupName(event.target.value)}
          onKeyDown={(event) => {
            if (event.key === 'Enter') handleCreateGroup();
          }}
          placeholder="例如：WWXYhome"
          className="w-full px-3 py-2 border border-gray-300 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-[#4A90D9] focus:border-transparent"
        />
        {message && <div className="mt-2 text-sm text-gray-500">{message}</div>}
      </Modal>
    </>
  );
}
