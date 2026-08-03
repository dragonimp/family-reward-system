import { Card } from '../components/Card';
import type { Transaction, Child } from '../types';
import { useState, useEffect, useCallback } from 'react';
import { getTransactions, getChildren } from '../services';
import { useFamilyGroup } from '../contexts/FamilyGroupContext';

type TransactionType = 'score' | 'cash' | 'item';

const typeLabels: Record<string, string> = {
  score: '积分',
  cash: '现金',
  item: '物品',
};

const typeColors: Record<string, string> = {
  score: 'bg-blue-100 text-blue-700',
  cash: 'bg-green-100 text-green-700',
  item: 'bg-orange-100 text-orange-700',
};

export default function Transactions() {
  const { selectedGroupId } = useFamilyGroup();
  const [transactions, setTransactions] = useState<Transaction[]>([]);
  const [children, setChildren] = useState<Child[]>([]);
  const [loading, setLoading] = useState(true);
  const [page, setPage] = useState(1);
  const [pageSize] = useState(10);
  const [total, setTotal] = useState(0);

  // 筛选条件
  const [filterChild, setFilterChild] = useState<string>('');
  const [filterType, setFilterType] = useState<string>('');
  const [filterCategory, setFilterCategory] = useState<string>('');
  const [filterStartDate, setFilterStartDate] = useState('');
  const [filterEndDate, setFilterEndDate] = useState('');
  const [filterSearch, setFilterSearch] = useState('');

  const loadData = useCallback(async () => {
    try {
      setLoading(true);
      const params: any = { page, pageSize, familyGroupId: selectedGroupId ?? undefined };
      if (filterChild) params.childId = parseInt(filterChild);
      if (filterType) params.type = filterType;
      if (filterCategory) params.category = filterCategory;
      if (filterStartDate) params.startDate = filterStartDate;
      if (filterEndDate) params.endDate = filterEndDate;
      if (filterSearch) params.search = filterSearch;

      const [txRes, childRes] = await Promise.all([
        getTransactions(params),
        getChildren({ familyGroupId: selectedGroupId ?? undefined }),
      ]);

      const txData = (txRes as any).data ?? txRes;
      setTransactions(txData?.items || []);
      setTotal(txData?.total || 0);
      setChildren(Array.isArray(childRes) ? childRes : (childRes as any).data || []);
    } catch (error) {
      console.error('加载失败:', error);
      setTransactions([]);
      setTotal(0);
      setChildren([]);
    } finally {
      setLoading(false);
    }
  }, [page, pageSize, filterChild, filterType, filterCategory, filterStartDate, filterEndDate, filterSearch, selectedGroupId]);

  useEffect(() => {
    loadData();
  }, [loadData]);

  useEffect(() => {
    setPage(1);
    setFilterChild('');
  }, [selectedGroupId]);

  const categories = Array.from(new Set(transactions.map((t) => t.category)));
  const totalPages = Math.ceil(total / pageSize);

  const exportCSV = () => {
    const headers = ['ID', '孩子', '类型', '分类', '金额', '描述', '时间'];
    const rows = transactions.map((t) => [
      t.id,
      t.childName,
      typeLabels[t.type] || t.type,
      t.category,
      t.amount,
      `"${t.description}"`,
      new Date(t.createdAt || '').toLocaleString('zh-CN'),
    ]);
    const csv = [headers.join(','), ...rows.map((r) => r.join(','))].join('\n');
    const blob = new Blob(['\uFEFF' + csv], { type: 'text/csv;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `交易记录_${new Date().toLocaleDateString('zh-CN')}.csv`;
    a.click();
    URL.revokeObjectURL(url);
  };

  const resetFilters = () => {
    setFilterChild('');
    setFilterType('');
    setFilterCategory('');
    setFilterStartDate('');
    setFilterEndDate('');
    setFilterSearch('');
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center py-20">
        <div className="text-center">
          <div className="inline-block animate-spin rounded-full h-10 w-10 border-4 border-[#4A90D9] border-t-transparent" />
          <p className="mt-4 text-gray-500">加载中...</p>
        </div>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-2xl font-bold text-gray-900">交易记录</h2>
          <p className="text-gray-500 mt-1">查看所有积分、现金和物品变更记录</p>
        </div>
        <button onClick={exportCSV} className="btn-primary flex items-center gap-2">
          <span>📥</span> 导出 CSV
        </button>
      </div>

      {/* 筛选栏 */}
      <Card className="p-4">
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-3">
          <div>
            <label className="block text-xs font-medium text-gray-500 mb-1">孩子</label>
            <select
              value={filterChild}
              onChange={(e) => { setFilterChild(e.target.value); setPage(1); }}
              className="w-full px-3 py-2 border border-gray-300 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-[#4A90D9]"
            >
              <option value="">全部</option>
              {children.map((c) => (
                <option key={c.id} value={c.id}>{c.name}</option>
              ))}
            </select>
          </div>
          <div>
            <label className="block text-xs font-medium text-gray-500 mb-1">类型</label>
            <select
              value={filterType}
              onChange={(e) => { setFilterType(e.target.value); setPage(1); }}
              className="w-full px-3 py-2 border border-gray-300 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-[#4A90D9]"
            >
              <option value="">全部</option>
              <option value="score">积分</option>
              <option value="cash">现金</option>
              <option value="item">物品</option>
            </select>
          </div>
          <div>
            <label className="block text-xs font-medium text-gray-500 mb-1">分类</label>
            <select
              value={filterCategory}
              onChange={(e) => { setFilterCategory(e.target.value); setPage(1); }}
              className="w-full px-3 py-2 border border-gray-300 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-[#4A90D9]"
            >
              <option value="">全部</option>
              {categories.map((cat) => (
                <option key={cat} value={cat}>{cat}</option>
              ))}
            </select>
          </div>
          <div>
            <label className="block text-xs font-medium text-gray-500 mb-1">搜索描述</label>
            <input
              type="text"
              value={filterSearch}
              onChange={(e) => { setFilterSearch(e.target.value); setPage(1); }}
              placeholder="搜索描述..."
              className="w-full px-3 py-2 border border-gray-300 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-[#4A90D9]"
            />
          </div>
          <div>
            <label className="block text-xs font-medium text-gray-500 mb-1">开始日期</label>
            <input
              type="date"
              value={filterStartDate}
              onChange={(e) => { setFilterStartDate(e.target.value); setPage(1); }}
              className="w-full px-3 py-2 border border-gray-300 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-[#4A90D9]"
            />
          </div>
          <div>
            <label className="block text-xs font-medium text-gray-500 mb-1">结束日期</label>
            <input
              type="date"
              value={filterEndDate}
              onChange={(e) => { setFilterEndDate(e.target.value); setPage(1); }}
              className="w-full px-3 py-2 border border-gray-300 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-[#4A90D9]"
            />
          </div>
          <div className="flex items-end">
            <button
              onClick={() => { resetFilters(); setPage(1); }}
              className="w-full px-3 py-2 text-sm text-gray-600 border border-gray-300 rounded-lg hover:bg-gray-50 transition-colors"
            >
              重置筛选
            </button>
          </div>
        </div>
      </Card>

      {/* 交易列表 */}
      <Card>
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-gray-200 bg-gray-50/50">
                <th className="text-left py-4 px-4 text-gray-500 font-medium">#</th>
                <th className="text-left py-4 px-4 text-gray-500 font-medium">孩子</th>
                <th className="text-left py-4 px-4 text-gray-500 font-medium">类型</th>
                <th className="text-left py-4 px-4 text-gray-500 font-medium">分类</th>
                <th className="text-right py-4 px-4 text-gray-500 font-medium">金额</th>
                <th className="text-left py-4 px-4 text-gray-500 font-medium">描述</th>
                <th className="text-right py-4 px-4 text-gray-500 font-medium">时间</th>
              </tr>
            </thead>
            <tbody>
              {transactions.map((tx, idx) => (
                <tr key={tx.id} className={`border-b border-gray-100 hover:bg-gray-50/50 ${idx % 2 === 0 ? '' : 'bg-gray-50/30'}`}>
                  <td className="py-4 px-4 text-gray-400">{(page - 1) * pageSize + idx + 1}</td>
                  <td className="py-4 px-4 font-medium">{tx.childName}</td>
                  <td className="py-4 px-4">
                    <span className={`inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium ${typeColors[tx.type] || 'bg-gray-100 text-gray-700'}`}>
                      {typeLabels[tx.type] || tx.type}
                    </span>
                  </td>
                  <td className="py-4 px-4">{tx.category}</td>
                  <td className={`py-4 px-4 text-right font-medium ${(tx.amount ?? 0) > 0 ? 'text-green-600' : 'text-red-600'}`}>
                    {(tx.amount ?? 0) > 0 ? '+' : ''}{tx.amount ?? 0}
                  </td>
                  <td className="py-4 px-4 text-gray-500 max-w-xs truncate">{tx.description || ''}</td>
                  <td className="py-4 px-4 text-right text-gray-400 whitespace-nowrap text-xs">
                    {new Date(tx.createdAt || '').toLocaleDateString('zh-CN')}
                    <br />
                    {new Date(tx.createdAt || '').toLocaleTimeString('zh-CN', { hour: '2-digit', minute: '2-digit' })}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
          {transactions.length === 0 && (
            <div className="text-center py-12 text-gray-400">
              <p className="text-4xl mb-3">📝</p>
              <p>暂无交易记录</p>
            </div>
          )}
        </div>

        {/* 分页 */}
        {totalPages > 1 && (
          <div className="flex items-center justify-between px-4 py-4 border-t border-gray-200">
            <p className="text-sm text-gray-500">共 {total} 条记录</p>
            <div className="flex items-center gap-2">
              <button
                onClick={() => setPage(Math.max(1, page - 1))}
                disabled={page === 1}
                className="px-3 py-1.5 text-sm border border-gray-300 rounded-lg disabled:opacity-50 hover:bg-gray-50"
              >
                上一页
              </button>
              {Array.from({ length: Math.min(5, totalPages) }, (_, i) => {
                let p: number;
                if (totalPages <= 5) {
                  p = i + 1;
                } else if (page <= 3) {
                  p = i + 1;
                } else if (page >= totalPages - 2) {
                  p = totalPages - 4 + i;
                } else {
                  p = page - 2 + i;
                }
                return (
                  <button
                    key={p}
                    onClick={() => setPage(p)}
                    className={`w-8 h-8 text-sm rounded-lg ${page === p ? 'bg-[#4A90D9] text-white' : 'border border-gray-300 hover:bg-gray-50'}`}
                  >
                    {p}
                  </button>
                );
              })}
              <button
                onClick={() => setPage(Math.min(totalPages, page + 1))}
                disabled={page === totalPages}
                className="px-3 py-1.5 text-sm border border-gray-300 rounded-lg disabled:opacity-50 hover:bg-gray-50"
              >
                下一页
              </button>
            </div>
          </div>
        )}
      </Card>
    </div>
  );
}
