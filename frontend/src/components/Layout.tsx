import { Link, useLocation } from 'react-router-dom';
import { useState, type ReactNode } from 'react';

const navItems = [
  { path: '/dashboard', label: '仪表盘', icon: '📊' },
  { path: '/children', label: '孩子管理', icon: '👶' },
  { path: '/reward', label: '积分操作', icon: '⭐' },
  { path: '/transactions', label: '交易记录', icon: '📝' },
  { path: '/rules', label: '规则管理', icon: '📋' },
  { path: '/stats', label: '统计报表', icon: '📈' },
];

interface LayoutProps {
  children: ReactNode;
}

export default function Layout({ children }: LayoutProps) {
  const location = useLocation();
  const [mobileOpen, setMobileOpen] = useState(false);

  return (
    <div className="h-screen flex flex-col bg-[#F7F9FC] overflow-hidden">
      <header className="bg-white shadow-sm border-b border-gray-200 sticky top-0 z-50 flex-shrink-0">
        <div className="max-w-full mx-auto px-3 sm:px-4">
          <div className="flex items-center justify-between h-14 sm:h-16">
            <div className="flex items-center gap-2">
              <span className="text-xl sm:text-2xl">🏠</span>
              <h1 className="text-base sm:text-lg md:text-xl font-bold text-[#4A90D9] truncate">家庭奖励系统</h1>
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
            </nav>
            {/* 平板端横向滚动导航 */}
            <nav className="hidden lg:hidden flex-1 mx-3 overflow-x-auto scrollbar-hide">
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
              </div>
            </nav>
            {/* 移动端汉堡菜单 */}
            <button
              className="lg:hidden p-2 rounded-lg hover:bg-gray-100 text-xl"
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
              {navItems.map((item) => (
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
      <main className="flex-1 overflow-y-auto overflow-x-hidden px-3 sm:px-4 py-4 sm:py-6">
        <div className="max-w-full mx-auto">
          {children}
        </div>
      </main>
      {/* 移动端底部导航 */}
      <nav className="lg:hidden bg-white border-t border-gray-200 flex-shrink-0">
        <div className="flex items-center justify-around py-1">
          {navItems.slice(0, 5).map((item) => (
            <Link
              key={item.path}
              to={item.path}
              className={`flex flex-col items-center gap-0.5 px-2 py-1.5 rounded-lg text-xs transition-colors
                ${location.pathname === item.path
                  ? 'text-[#4A90D9] bg-[#4A90D9]/10'
                  : 'text-gray-500'}`}
            >
              <span className="text-base">{item.icon}</span>
              <span className="truncate max-w-[40px]">{item.label}</span>
            </Link>
          ))}
          {/* 查看更多 */}
          <button
            className="flex flex-col items-center gap-0.5 px-2 py-1.5 rounded-lg text-xs text-gray-400"
            onClick={() => setMobileOpen(!mobileOpen)}
          >
            <span className="text-base">⋯</span>
            <span>更多</span>
          </button>
        </div>
      </nav>
    </div>
  );
}
