import { Link, useLocation } from 'react-router-dom';
import { useEffect, useRef, useState, type ReactNode } from 'react';
import { useAuth } from '../contexts/AuthContext';
import UserMenu from './UserMenu';
import PublicFeedbackWidget from './PublicFeedbackWidget';
import MobileAssistantBar from './MobileAssistantBar';

const navItems = [
  { path: '/dashboard', label: '仪表盘', icon: '📊' },
  { path: '/reward', label: '积分操作', icon: '⭐' },
  { path: '/transactions', label: '交易记录', icon: '📝' },
  { path: '/stats', label: '统计报表', icon: '📈' },
];

const manageItems = [
  { path: '/family-groups', label: '家庭管理', icon: '🏠' },
  { path: '/children', label: '孩子管理', icon: '👶' },
  { path: '/rules', label: '规则管理', icon: '📋' },
  { path: '/settings', label: '系统设置', icon: '⚙️' },
];

const mobileNavItems = [...navItems, ...manageItems];

interface LayoutProps {
  children: ReactNode;
}

export default function Layout({ children }: LayoutProps) {
  const location = useLocation();
  const { logout, user, userId } = useAuth();
  const [mobileOpen, setMobileOpen] = useState(false);
  const [manageOpen, setManageOpen] = useState(false);
  const manageMenuRef = useRef<HTMLDivElement>(null);
  const assistantOpen = location.pathname.startsWith('/assistant');

  useEffect(() => {
    const handleDocumentPointerDown = (event: PointerEvent) => {
      if (!manageMenuRef.current?.contains(event.target as Node)) {
        setManageOpen(false);
      }
    };

    document.addEventListener('pointerdown', handleDocumentPointerDown);
    return () => document.removeEventListener('pointerdown', handleDocumentPointerDown);
  }, []);

  const handleLogout = () => {
    setMobileOpen(false);
    logout();
  };

  return (
    <div className="h-screen flex flex-col bg-[#F7F9FC] overflow-hidden">
      <header className="bg-white shadow-sm border-b border-gray-200 sticky top-0 z-50 flex-shrink-0">
        <div className="max-w-full mx-auto px-3 sm:px-4">
          <div className="flex items-center justify-between h-14 sm:h-16">
            <div className="flex min-w-0 items-center gap-2">
              <span className="text-xl sm:text-2xl">🏠</span>
              <h1 className="text-base sm:text-lg md:text-xl font-bold text-[#4A90D9] truncate">家加分</h1>
            </div>
            {/* 桌面端导航 */}
            <nav className="hidden lg:flex items-center gap-1">
              {navItems.map((item) => (
                <Link
                  key={item.path}
                  to={item.path}
                  className={`flex items-center gap-1 px-3 py-2 rounded-lg text-sm font-medium transition-colors whitespace-nowrap
                    ${location.pathname === item.path
                      ? 'bg-[#4A90D9]/10 text-[#4A90D9]'
                      : 'text-gray-600 hover:bg-gray-100'}`}
                >
                  <span className="text-base">{item.icon}</span>
                  <span>{item.label}</span>
                </Link>
              ))}
              <div ref={manageMenuRef} className="relative">
                <button
                  type="button"
                  onClick={() => setManageOpen((open) => !open)}
                  className={`flex items-center gap-1 px-3 py-2 rounded-lg text-sm font-medium transition-colors whitespace-nowrap
                    ${manageItems.some((item) => location.pathname === item.path)
                      ? 'bg-[#4A90D9]/10 text-[#4A90D9]'
                      : 'text-gray-600 hover:bg-gray-100'}`}
                >
                  <span className="text-base">🧭</span>
                  <span>管理</span>
                </button>
                {manageOpen && (
                  <div className="absolute right-0 mt-2 w-40 rounded-lg border border-gray-200 bg-white p-1 shadow-lg">
                    {manageItems.map((item) => (
                      <Link
                        key={item.path}
                        to={item.path}
                        onClick={() => setManageOpen(false)}
                        className={`flex items-center gap-2 rounded-md px-3 py-2 text-sm ${
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
            {/* 平板端横向滚动导航 */}
            <nav className="hidden sm:flex lg:hidden flex-1 mx-3 overflow-x-auto scrollbar-hide">
              <div className="flex items-center gap-1 min-w-max">
                {navItems.map((item) => (
                  <Link
                    key={item.path}
                    to={item.path}
                    className={`flex items-center gap-1 px-2 sm:px-3 py-2 rounded-lg text-xs sm:text-sm font-medium transition-colors whitespace-nowrap
                      ${location.pathname === item.path
                        ? 'bg-[#4A90D9]/10 text-[#4A90D9]'
                        : 'text-gray-600 hover:bg-gray-100'}`}
                  >
                    <span className="text-sm sm:text-base">{item.icon}</span>
                    <span>{item.label}</span>
                  </Link>
                ))}
                <Link
                  to="/family-groups"
                  className={`flex items-center gap-1 px-2 sm:px-3 py-2 rounded-lg text-xs sm:text-sm font-medium transition-colors whitespace-nowrap
                    ${manageItems.some((item) => location.pathname === item.path)
                      ? 'bg-[#4A90D9]/10 text-[#4A90D9]'
                      : 'text-gray-600 hover:bg-gray-100'}`}
                >
                  <span className="text-sm sm:text-base">🧭</span>
                  <span>管理</span>
                </Link>
              </div>
            </nav>
            <div className="ml-auto min-w-0">
              <UserMenu user={user} userId={userId} onLogout={handleLogout} />
            </div>
            {/* 移动端汉堡菜单 */}
            <button
              className="lg:hidden shrink-0 p-2 rounded-lg hover:bg-gray-100 text-xl"
              onClick={() => setMobileOpen(!mobileOpen)}
              aria-label="菜单"
            >
              {mobileOpen ? '✕' : '☰'}
            </button>
          </div>
        </div>
        {/* 移动端下拉菜单 */}
          {mobileOpen && (
          <div className="lg:hidden border-t border-gray-200 bg-white">
            <div className="flex flex-col gap-1 p-2">
              {mobileNavItems.map((item) => (
                <Link
                  key={item.path}
                  to={item.path}
                  className={`flex items-center gap-3 px-3 py-3 rounded-lg text-sm font-medium transition-colors
                    ${location.pathname === item.path
                      ? 'bg-[#4A90D9]/10 text-[#4A90D9]'
                      : 'text-gray-600 hover:bg-gray-50'}`}
                  onClick={() => setMobileOpen(false)}
                >
                  <span className="text-xl">{item.icon}</span>
                  <span>{item.label}</span>
                </Link>
              ))}
            </div>
          </div>
        )}
      </header>
      {/* 主内容区 - 自适应高度 */}
      <main className={assistantOpen
        ? 'flex-1 min-h-0 overflow-hidden'
        : 'flex-1 overflow-y-auto overflow-x-hidden px-3 py-4 pb-20 sm:px-4 sm:py-6 sm:pb-6'}>
        <div className={assistantOpen ? 'h-full min-h-0 max-w-full' : 'max-w-full mx-auto'}>
          {children}
        </div>
      </main>
      {!assistantOpen && <MobileAssistantBar />}
      <PublicFeedbackWidget />
    </div>
  );
}
