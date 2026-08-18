import { Card } from '../components/Card';
import type { Child, Transaction } from '../types';
import { useState, useEffect, useCallback } from 'react';
import { useNavigate } from 'react-router-dom';
import { useFamilyGroup } from '../contexts/FamilyGroupContext';
import { getChildren, getTransactions } from '../services';

interface ChildCardProps {
  child: Child;
  index: number;
}

const childColors = [
  { bg: 'from-blue-500 to-blue-600', light: 'bg-blue-50', text: 'text-blue-600', border: 'border-blue-200' },
  { bg: 'from-emerald-500 to-emerald-600', light: 'bg-emerald-50', text: 'text-emerald-600', border: 'border-emerald-200' },
  { bg: 'from-amber-500 to-amber-600', light: 'bg-amber-50', text: 'text-amber-600', border: 'border-amber-200' },
  { bg: 'from-rose-500 to-rose-600', light: 'bg-rose-50', text: 'text-rose-600', border: 'border-rose-200' },
  { bg: 'from-purple-500 to-purple-600', light: 'bg-purple-50', text: 'text-purple-600', border: 'border-purple-200' },
];

const childEmojis = ['👦', '👧', '🧒', '👦', '👧'];

function ChildCard({ child, index }: ChildCardProps) {
  const color = childColors[index % 5];
  
  return (
    <div className={`${color.light} rounded-2xl border ${color.border} p-4 transition-all hover:shadow-lg hover:scale-105`}>
      {/* 头部 */}
      <div className="flex items-center gap-3 mb-3">
        <div className={`w-10 h-10 rounded-full bg-gradient-to-br ${color.bg} flex items-center justify-center text-xl shadow-sm`}>
          {childEmojis[index % 5]}
        </div>
        <div>
          <h4 className="font-bold text-gray-800 text-base">{child.name}</h4>
          <p className="text-xs text-gray-500">ID: {child.id}</p>
        </div>
      </div>
      
      {/* 数据卡片 */}
      <div className="grid grid-cols-3 gap-2">
        <div className="bg-white/70 rounded-xl p-2 text-center">
          <p className="text-xs text-gray-500 mb-0.5">积分</p>
          <p className="text-lg font-bold text-blue-600">{child.score ?? 0}</p>
        </div>
        <div className="bg-white/70 rounded-xl p-2 text-center">
          <p className="text-xs text-gray-500 mb-0.5">现金</p>
          <p className="text-lg font-bold text-emerald-600">¥{child.cash ?? 0}</p>
        </div>
        <div className="bg-white/70 rounded-xl p-2 text-center">
          <p className="text-xs text-gray-500 mb-0.5">物品</p>
          <p className="text-lg font-bold text-amber-600">{child.items ?? 0}</p>
        </div>
      </div>
    </div>
  );
}

function StatWidget({ icon, label, value, color }: { icon: string; label: string; value: string | number; color: string }) {
  return (
    <div className="flex items-center gap-3 bg-white rounded-xl p-3 shadow-sm border border-gray-100">
      <div className="text-2xl">{icon}</div>
      <div>
        <p className="text-xs text-gray-500">{label}</p>
        <p className={`text-lg font-bold ${color}`}>{value}</p>
      </div>
    </div>
  );
}

function QuickAction({ label, icon, onClick, bg, hover }: { label: string; icon: string; onClick: () => void; bg: string; hover: string }) {
  return (
    <button
      onClick={onClick}
      className={`${bg} ${hover} flex flex-col items-center gap-1.5 p-3 rounded-xl transition-all hover:shadow-md active:scale-95`}
    >
      <span className="text-2xl">{icon}</span>
      <span className="text-xs font-medium text-gray-700">{label}</span>
    </button>
  );
}

function TransactionItem({ tx, childColors }: { tx: any; childColors: any[] }) {
  const childColor = childColors[(tx.child_id ?? 0) % 5];
  const isPositive = (tx.direction === '+') || (tx.type === 'points' && tx.direction === '+');
  
  const typeColors: Record<string, string> = {
    points: 'bg-blue-100 text-blue-700',
    cash: 'bg-emerald-100 text-emerald-700',
    items: 'bg-amber-100 text-amber-700',
  };
  
  const typeLabels: Record<string, string> = {
    points: '积分',
    cash: '现金',
    items: '物品',
  };

  return (
    <div className="flex items-center gap-3 py-3 border-b border-gray-50 last:border-0 hover:bg-gray-50/50 px-2 rounded-lg transition-colors">
      <div className={`w-8 h-8 rounded-full ${childColor.light} flex items-center justify-center text-sm font-bold ${childColor.text}`}>
        {tx.child_name || tx.child_id}
      </div>
      
      <div className="flex-1 min-w-0">
        <div className="flex items-center gap-2 mb-0.5">
          <span className="font-medium text-gray-800 text-sm truncate">{tx.description || '无描述'}</span>
          <span className={`text-xs px-1.5 py-0.5 rounded-full font-medium ${typeColors[tx.type] || 'bg-gray-100'}`}>
            {typeLabels[tx.type] || tx.type}
          </span>
          {tx.category && (
            <span className="text-xs text-gray-400 bg-gray-100 px-1.5 py-0.5 rounded-full">
              {tx.category}
            </span>
          )}
        </div>
        <p className="text-xs text-gray-400">{tx.date}</p>
      </div>
      
      <div className="text-right flex-shrink-0">
        {tx.type === 'points' && (
          <span className={`text-sm font-bold ${isPositive ? 'text-emerald-600' : 'text-red-600'}`}>
            {isPositive ? '+' : ''}{tx.points || 0}
          </span>
        )}
        {tx.type === 'cash' && (
          <span className={`text-sm font-bold ${isPositive ? 'text-emerald-600' : 'text-red-600'}`}>
            {isPositive ? '+' : ''}¥{tx.cash_cny || 0}
          </span>
        )}
        {tx.type === 'items' && (
          <span className="text-sm font-bold text-amber-600">
            {isPositive ? '🎁+' : '🎁-'}{tx.items || '1'}
          </span>
        )}
      </div>
    </div>
  );
}

export default function Dashboard() {
  const navigate = useNavigate();
  const { selectedGroupId } = useFamilyGroup();
  const [children, setChildren] = useState<Child[]>([]);
  const [transactions, setTransactions] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string>('');

  const loadData = useCallback(async (silent = false) => {
    try {
      if (!silent) setLoading(true);
      setError('');
      
      const [childrenRes, transactionsRes] = await Promise.all([
        getChildren({ familyGroupId: selectedGroupId ?? undefined }),
        getTransactions({ page: 1, pageSize: 20, familyGroupId: selectedGroupId ?? undefined }),
      ]);

      const ch = Array.isArray(childrenRes) ? childrenRes : childrenRes?.data;
      if (ch) {
        setChildren(ch as Child[]);
      }
      
      // 交易数据 - 兼容后端 {data: {items}} 和直接 {items} 两种形状
      const txData = transactionsRes?.data ?? transactionsRes;
      if (txData?.items) {
        const mapped = txData.items.map((t: any) => ({
          ...t,
          child_name: t.child_name || t.childName || '',
        }));
        setTransactions(mapped);
      }
    } catch (err) {
      console.error('加载数据失败:', err);
      setError('连接服务器失败，暂时无法加载真实数据');
      setChildren([]);
      setTransactions([]);
    } finally {
      setLoading(false);
    }
  }, [selectedGroupId]);

  useEffect(() => {
    loadData();
  }, [loadData]);

  useEffect(() => {
    const interval = window.setInterval(() => {
      loadData(true);
    }, 10000);
    const handleVisibilityChange = () => {
      if (!document.hidden) loadData(true);
    };
    document.addEventListener('visibilitychange', handleVisibilityChange);
    return () => {
      window.clearInterval(interval);
      document.removeEventListener('visibilitychange', handleVisibilityChange);
    };
  }, [loadData]);

  const totalPoints = children.reduce((sum, c) => sum + (c.score || 0), 0);
  const totalCash = children.reduce((sum, c) => sum + (c.cash || 0), 0);
  const totalItems = children.reduce((sum, c) => sum + (c.items || 0), 0);

  if (loading) {
    return (
      <div className="min-h-[400px] flex items-center justify-center">
        <div className="text-center">
          <div className="inline-block animate-spin rounded-full h-12 w-12 border-4 border-[#4A90D9] border-t-transparent mb-4"></div>
          <p className="text-gray-500">加载中...</p>
        </div>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* 页面标题 */}
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-2xl font-bold text-gray-900">🏠 家加分</h2>
          <p className="text-sm text-gray-500 mt-1">记录每个孩子的成长瞬间</p>
        </div>
        <button
          onClick={() => loadData()}
          className="px-4 py-2 bg-[#4A90D9] text-white rounded-lg text-sm font-medium hover:bg-[#3a7bc8] transition-colors shadow-sm"
        >
          🔄 刷新
        </button>
      </div>

      {error && (
        <div className="bg-amber-50 border border-amber-200 text-amber-700 px-4 py-3 rounded-xl text-sm">
          ⚠️ {error}
        </div>
      )}

      {/* 孩子卡片 */}
      <div>
        <h3 className="text-lg font-bold text-gray-800 mb-3">👶 孩子们的状态</h3>
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-5 gap-4">
          {children.map((child, index) => (
            <ChildCard key={child.id} child={child} index={index} />
          ))}
        </div>
      </div>

      {/* 综合统计 */}
      <div>
        <h3 className="text-lg font-bold text-gray-800 mb-3">📊 圈子统计</h3>
        <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
          <StatWidget icon="⭐" label="总积分" value={totalPoints} color="text-blue-600" />
          <StatWidget icon="💰" label="总现金" value={`¥${totalCash}`} color="text-emerald-600" />
          <StatWidget icon="🎁" label="总物品" value={totalItems} color="text-amber-600" />
          <StatWidget icon="👨‍👩‍👧‍👦" label="孩子数" value={children.length} color="text-purple-600" />
        </div>
      </div>

      {/* 快捷操作 */}
      <div>
        <h3 className="text-lg font-bold text-gray-800 mb-3">⚡ 快捷操作</h3>
        <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-3">
          <QuickAction
            label="加分" icon="➕"
            onClick={() => navigate('/reward?type=points&direction=+')}
            bg="bg-emerald-50 hover:bg-emerald-100" hover="hover:bg-emerald-100"
          />
          <QuickAction
            label="减分" icon="➖"
            onClick={() => navigate('/reward?type=points&direction=-')}
            bg="bg-red-50 hover:bg-red-100" hover="hover:bg-red-100"
          />
          <QuickAction
            label="加现金" icon="💵"
            onClick={() => navigate('/reward?type=cash&direction=+')}
            bg="bg-blue-50 hover:bg-blue-100" hover="hover:bg-blue-100"
          />
          <QuickAction
            label="减现金" icon="💸"
            onClick={() => navigate('/reward?type=cash&direction=-')}
            bg="bg-orange-50 hover:bg-orange-100" hover="hover:bg-orange-100"
          />
          <QuickAction
            label="管理孩子" icon="👨‍👩‍👧‍👦"
            onClick={() => navigate('/children')}
            bg="bg-purple-50 hover:bg-purple-100" hover="hover:bg-purple-100"
          />
          <QuickAction
            label="查看规则" icon="📋"
            onClick={() => navigate('/rules')}
            bg="bg-gray-50 hover:bg-gray-100" hover="hover:bg-gray-100"
          />
        </div>
      </div>

      {/* 最新交易 */}
      <Card className="p-5">
        <div className="mb-4">
          <h3 className="text-lg font-bold text-gray-800">📜 最近动态</h3>
        </div>
        
        {transactions.length === 0 ? (
          <div className="text-center py-12 text-gray-400">
            <p className="text-4xl mb-2">📝</p>
            <p>暂无交易记录</p>
            <p className="text-xs mt-1">添加奖励后这里会显示</p>
          </div>
        ) : (
          <div className="divide-y divide-gray-100">
            {transactions.map((tx) => (
              <TransactionItem key={tx.id} tx={tx} childColors={childColors} />
            ))}
          </div>
        )}
      </Card>
    </div>
  );
}
