import { Link, useLocation } from 'react-router-dom';
import { useEffect, useState, type ReactNode } from 'react';
import { useAuth } from '../contexts/AuthContext';
import UserMenu from './UserMenu';

const primaryNavItems = [
  { path: '/dashboard', label: '首页', desktopLabel: '仪表盘', icon: '⌂' },
  { path: '/reward', label: '积分', desktopLabel: '积分操作', icon: '⭐' },
  { path: '/transactions', label: '记录', desktopLabel: '交易记录', icon: '📝' },
  { path: '/stats', label: '统计', desktopLabel: '统计报表', icon: '📈' },
];

const manageItems = [
  { path: '/family-groups', label: '家庭管理', description: '切换与维护家庭', icon: '🏠' },
  { path: '/children', label: '孩子管理', description: '孩子资料与手表', icon: '👶' },
  { path: '/rules', label: '规则管理', description: '加减分规则', icon: '📋' },
  { path: '/settings', label: '系统设置', description: '语音与服务配置', icon: '⚙️' },
];

interface LayoutProps {
  children: ReactNode;
}

export default function Layout({ children }: LayoutProps) {
  const location = useLocation();
  const { logout, user, userId } = useAuth();
  const [moreOpen, setMoreOpen] = useState(false);
  const [manageOpen, setManageOpen] = useState(false);
  const manageActive = manageItems.some((item) => location.pathname === item.path);

  useEffect(() => {
    setMoreOpen(false);
    setManageOpen(false);
  }, [location.pathname]);

  const handleLogout = () => {
    setMoreOpen(false);
    logout();
  };

  return (
    <div className="app-shell flex min-h-0 flex-col overflow-hidden bg-[#F7F9FC]">
      <header className="z-40 flex-shrink-0 border-b border-gray-100 bg-white/95 shadow-sm backdrop-blur">
        <div className="mx-auto max-w-[1440px] px-3 sm:px-5 lg:px-6">
          <div className="flex h-14 items-center justify-between sm:h-16">
            <Link to="/dashboard" className="flex min-w-0 items-center gap-2" aria-label="返回首页">
              <span className="flex h-9 w-9 items-center justify-center rounded-xl bg-[#4A90D9]/10 text-xl">🏠</span>
              <div className="min-w-0">
                <h1 className="truncate text-base font-bold text-[#4A90D9] sm:text-xl">家加分</h1>
                <p className="hidden text-[11px] text-gray-400 sm:block lg:hidden">家庭成长积分</p>
              </div>
            </Link>

            <nav className="hidden items-center gap-1 lg:flex" aria-label="主导航">
              {primaryNavItems.map((item) => (
                <Link
                  key={item.path}
                  to={item.path}
                  className={`flex items-center gap-1.5 whitespace-nowrap rounded-lg px-3 py-2 text-sm font-medium transition-colors ${
                    location.pathname === item.path
                      ? 'bg-[#4A90D9]/10 text-[#4A90D9]'
                      : 'text-gray-600 hover:bg-gray-100'
                  }`}
                >
                  <span>{item.icon}</span>
                  <span>{item.desktopLabel}</span>
                </Link>
              ))}
              <div className="relative">
                <button
                  type="button"
                  onClick={() => setManageOpen((open) => !open)}
                  className={`flex items-center gap-1.5 rounded-lg px-3 py-2 text-sm font-medium transition-colors ${
                    manageActive ? 'bg-[#4A90D9]/10 text-[#4A90D9]' : 'text-gray-600 hover:bg-gray-100'
                  }`}
                  aria-expanded={manageOpen}
                >
                  <span>🧭</span>
                  <span>管理</span>
                  <span className="text-[10px]">⌄</span>
                </button>
                {manageOpen && (
                  <div className="absolute right-0 mt-2 w-48 rounded-xl border border-gray-100 bg-white p-1.5 shadow-xl">
                    {manageItems.map((item) => (
                      <Link
                        key={item.path}
                        to={item.path}
                        className={`flex items-center gap-2 rounded-lg px-3 py-2.5 text-sm ${
                          location.pathname === item.path ? 'bg-[#4A90D9]/10 text-[#4A90D9]' : 'text-gray-600 hover:bg-gray-50'
                        }`}
                      >
                        <span>{item.icon}</span>
                        <span>{item.label}</span>
                      </Link>
                    ))}
                  </div>
                )}
              </div>
            </nav>

            <div className="ml-auto min-w-0 lg:ml-3">
              <UserMenu user={user} userId={userId} onLogout={handleLogout} />
            </div>
          </div>
        </div>
      </header>

      <main className="min-h-0 flex-1 overflow-y-auto overflow-x-hidden px-3 py-4 sm:px-5 sm:py-6 lg:px-6">
        <div className="mx-auto w-full max-w-[1440px]">{children}</div>
      </main>

      <nav className="mobile-safe-bottom z-40 flex-shrink-0 border-t border-gray-100 bg-white/95 backdrop-blur lg:hidden" aria-label="手机端主导航">
        <div className="mx-auto grid max-w-lg grid-cols-5 gap-1 px-2 pt-1.5">
          {primaryNavItems.map((item) => (
            <Link
              key={item.path}
              to={item.path}
              className={`flex min-h-12 min-w-0 flex-col items-center justify-center gap-0.5 rounded-xl px-1 text-[11px] font-medium transition-colors ${
                location.pathname === item.path ? 'bg-[#4A90D9]/10 text-[#4A90D9]' : 'text-gray-500'
              }`}
            >
              <span className="text-lg leading-none">{item.icon}</span>
              <span>{item.label}</span>
            </Link>
          ))}
          <button
            type="button"
            onClick={() => setMoreOpen(true)}
            className={`flex min-h-12 min-w-0 flex-col items-center justify-center gap-0.5 rounded-xl px-1 text-[11px] font-medium transition-colors ${
              manageActive ? 'bg-[#4A90D9]/10 text-[#4A90D9]' : 'text-gray-500'
            }`}
            aria-expanded={moreOpen}
          >
            <span className="text-lg leading-none">☷</span>
            <span>管理</span>
          </button>
        </div>
      </nav>

      {moreOpen && (
        <div className="fixed inset-0 z-50 lg:hidden" role="dialog" aria-modal="true" aria-label="管理功能">
          <button className="absolute inset-0 bg-slate-900/35" onClick={() => setMoreOpen(false)} aria-label="关闭管理菜单" />
          <div className="mobile-safe-sheet absolute inset-x-0 bottom-0 rounded-t-3xl bg-white px-4 pb-4 pt-3 shadow-2xl">
            <div className="mx-auto mb-3 h-1 w-10 rounded-full bg-gray-200" />
            <div className="mb-3 flex items-center justify-between">
              <div>
                <h2 className="font-semibold text-gray-900">家庭管理</h2>
                <p className="mt-0.5 text-xs text-gray-400">选择要处理的内容</p>
              </div>
              <button onClick={() => setMoreOpen(false)} className="flex h-9 w-9 items-center justify-center rounded-full bg-gray-100 text-gray-500" aria-label="关闭">✕</button>
            </div>
            <div className="grid grid-cols-2 gap-2">
              {manageItems.map((item) => (
                <Link key={item.path} to={item.path} className="flex min-w-0 items-center gap-3 rounded-2xl border border-gray-100 bg-gray-50/70 p-3.5 active:bg-gray-100">
                  <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-white text-xl shadow-sm">{item.icon}</span>
                  <span className="min-w-0">
                    <span className="block truncate text-sm font-semibold text-gray-800">{item.label}</span>
                    <span className="mt-0.5 block truncate text-[11px] text-gray-400">{item.description}</span>
                  </span>
                </Link>
              ))}
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
