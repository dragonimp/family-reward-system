import { Link } from 'react-router-dom';
import { useRef } from 'react';
import { getUserCenterUrl } from '../auth';
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
  const { groups, selectedGroupId, selectedGroup, loading, error, selectGroup } = useFamilyGroup();
  const menuRef = useRef<HTMLDetailsElement>(null);

  const closeMenu = () => {
    menuRef.current?.removeAttribute('open');
  };

  return (
    <>
      <details ref={menuRef} className="relative group flex-shrink-0">
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
                <span>切换家庭</span>
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
                    onClick={() => {
                      selectGroup(group.id);
                      closeMenu();
                    }}
                    className={`w-full flex items-center justify-between gap-2 px-2 py-2 rounded-md text-sm text-left transition-colors ${
                      active ? 'bg-[#4A90D9]/10 text-[#4A90D9]' : 'text-gray-700 hover:bg-white'
                    }`}
                  >
                    <span className="truncate">{group.name}</span>
                    {active && <span className="text-xs font-medium">当前</span>}
                  </button>
                );
              })}
            </div>
          </details>
          <div className="my-1 border-t border-gray-100" />
          <Link to="/settings" onClick={closeMenu} className="flex items-center gap-2 px-3 py-2 rounded-md text-sm text-gray-700 hover:bg-gray-50">
            <span>⚙️</span>
            <span>系统设置</span>
          </Link>
          <a href={getUserCenterUrl('info')} onClick={closeMenu} className="flex items-center gap-2 px-3 py-2 rounded-md text-sm text-gray-700 hover:bg-gray-50">
            <span>✎</span>
            <span>修改信息</span>
          </a>
          <a href={getUserCenterUrl('password')} onClick={closeMenu} className="flex items-center gap-2 px-3 py-2 rounded-md text-sm text-gray-700 hover:bg-gray-50">
            <span>🔑</span>
            <span>修改密码</span>
          </a>
          <div className="my-1 border-t border-gray-100" />
          <a
            href="/auth/logout"
            onClick={(event) => {
              closeMenu();
              onLogout();
              event.currentTarget.blur();
            }}
            className="flex items-center gap-2 px-3 py-2 rounded-md text-sm text-red-600 hover:bg-red-50"
          >
            <span>↩</span>
            <span>退出登录</span>
          </a>
        </div>
      </details>
    </>
  );
}
