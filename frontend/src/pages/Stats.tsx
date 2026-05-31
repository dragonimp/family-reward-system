import { Card } from '../components/Card';
import type { ChildStats, Child, TrendData } from '../types';
import { useState, useEffect, useCallback } from 'react';
import { getChildStats, getChild as getChildApi, getCategoryStats } from '../services';
import { CHILDREN_DATA } from '../constants/children';

// Simple SVG donut chart component
function DonutChart({ data }: { data: Array<{ name: string; value: number; color: string }> }) {
  const total = data.reduce((sum, d) => sum + d.value, 0);
  if (total === 0) return <div className="h-64 flex items-center justify-center text-gray-400">暂无数据</div>;

  let cumulative = 0;
  const slices = data
    .filter((d) => d.value > 0)
    .map((d) => {
      const startAngle = (cumulative / total) * 360;
      cumulative += d.value;
      const endAngle = (cumulative / total) * 360;
      const largeArc = endAngle - startAngle > 180 ? 1 : 0;
      const startRad = ((startAngle - 90) * Math.PI) / 180;
      const endRad = ((endAngle - 90) * Math.PI) / 180;
      const r = 60;
      const cx = 80;
      const cy = 80;
      const x1 = cx + r * Math.cos(startRad);
      const y1 = cy + r * Math.sin(startRad);
      const x2 = cx + r * Math.cos(endRad);
      const y2 = cy + r * Math.sin(endRad);
      return {
        ...d,
        path: `M ${cx} ${cy} L ${x1} ${y1} A ${r} ${r} 0 ${largeArc} 1 ${x2} ${y2} Z`,
        percentage: ((d.value / total) * 100).toFixed(1),
      };
    });

  return (
    <div className="flex flex-col lg:flex-row items-center gap-6">
      <svg viewBox="0 0 160 160" className="w-40 h-40 flex-shrink-0">
        {slices.map((s, i) => (
          <path key={i} d={s.path} fill={s.color} stroke="white" strokeWidth="2" />
        ))}
        <circle cx="80" cy="80" r="35" fill="white" />
        <text x="80" y="76" textAnchor="middle" className="text-xs" fill="#9CA3AF">总计</text>
        <text x="80" y="94" textAnchor="middle" className="text-sm font-bold" fill="#1F2937">{total}</text>
      </svg>
      <div className="flex flex-col gap-2">
        {slices.map((s, i) => (
          <div key={i} className="flex items-center gap-2 text-sm">
            <div className="w-3 h-3 rounded-sm" style={{ backgroundColor: s.color }} />
            <span className="flex-1">{s.name}</span>
            <span className="font-medium">{s.value}</span>
            <span className="text-gray-400 w-16 text-right">{s.percentage}%</span>
          </div>
        ))}
      </div>
    </div>
  );
}

// Simple bar chart component
function BarChart({ data }: { data: Array<{ label: string; value: number; color: string }> }) {
  const maxVal = Math.max(...data.map((d) => d.value), 1);

  return (
    <div className="flex items-end gap-3 h-48 px-4">
      {data.map((d, i) => (
        <div key={i} className="flex-1 flex flex-col items-center gap-1">
          <span className="text-xs font-medium text-gray-600">{d.value}</span>
          <div
            className="w-full rounded-t-lg transition-all"
            style={{ height: `${(d.value / maxVal) * 140}px`, backgroundColor: d.color }}
          />
          <span className="text-xs text-gray-500 truncate w-full text-center">{d.label}</span>
        </div>
      ))}
    </div>
  );
}

const categoryColors: Record<string, string> = {
  '学习': '#4A90D9',
  '生活': '#7ED321',
  '纪律': '#E74C3C',
  '奖励': '#F5A623',
  '运动': '#9B59B6',
  '其他': '#95A5A6',
};

export default function Stats() {
  const [childStats, setChildStats] = useState<ChildStats[]>([]);
  const [children, setChildren] = useState<Child[]>([]);
  const [categoryData, setCategoryData] = useState<Array<{ category: string; total: number }>>([]);
  const [loading, setLoading] = useState(true);

  const loadData = useCallback(async () => {
    try {
      setLoading(true);
      const [statsRes, childrenRes, catRes] = await Promise.all([
        getChildStats(),
        getChildStats().then(() => {}),
        getCategoryStats(),
      ]);

      setChildStats((statsRes as any).data || []);
      setCategoryData((catRes as any).data || []);

      try {
        const allChildren = await (await fetch('/api/children')).json();
        setChildren((allChildren as any).data || []);
      } catch {
        setChildren(CHILDREN_DATA as Child[]);
      }
    } catch (error) {
      console.error('加载失败:', error);
      setChildStats([
        { childId: 1, childName: '彦谦', totalScore: 108, totalCash: 230, totalItems: 2, scoreCount: 25, cashCount: 10, itemCount: 5, avgDailyScore: 5 },
        { childId: 2, childName: '玥玥', totalScore: 123, totalCash: 30, totalItems: 1, scoreCount: 20, cashCount: 8, itemCount: 3, avgDailyScore: 4 },
        { childId: 3, childName: '嘟嘟', totalScore: 100, totalCash: 0, totalItems: 0, scoreCount: 15, cashCount: 5, itemCount: 2, avgDailyScore: 3 },
        { childId: 4, childName: '薇薇', totalScore: 100, totalCash: 0, totalItems: 0, scoreCount: 15, cashCount: 5, itemCount: 2, avgDailyScore: 3 },
        { childId: 5, childName: '小宇', totalScore: 100, totalCash: 0, totalItems: 0, scoreCount: 15, cashCount: 5, itemCount: 2, avgDailyScore: 3 },
      ]);
      setCategoryData([
        { category: '学习', total: 280 },
        { category: '生活', total: 150 },
        { category: '纪律', total: -80 },
        { category: '奖励', total: 90 },
      ]);
      setChildren(CHILDREN_DATA as Child[]);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    loadData();
  }, [loadData]);

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

  // 排行榜
  const sortedStats = [...childStats].sort((a, b) => b.totalScore - a.totalScore);
  const medals = ['🥇', '🥈', '🥉'];

  // 分类颜色
  const catChartData = categoryData.map((c) => ({
    name: c.category,
    value: Math.abs(c.total),
    color: categoryColors[c.category] || '#95A5A6',
  }));

  // 月度对比图表
  const monthData = children.map((child, i) => ({
    label: child.name,
    value: childStats.find((s) => s.childId === child.id)?.totalScore ?? (child.score ?? 0),
    color: ['#4A90D9', '#7ED321', '#F5A623', '#E74C3C', '#9B59B6'][i % 5],
  }));

  return (
    <div className="space-y-6">
      <div>
        <h2 className="text-2xl font-bold text-gray-900">统计报表</h2>
        <p className="text-gray-500 mt-1">查看积分统计分析和排行榜</p>
      </div>

      {/* 排行榜 */}
      <Card className="p-5">
        <h3 className="text-sm font-semibold text-gray-700 mb-4 flex items-center gap-2">
          <span>🏆</span> 积分排行榜
        </h3>
        <div className="space-y-3">
          {sortedStats.length === 0 && children.length > 0
            ? children.map((child, idx) => {
                const stats = childStats.find((s) => s.childId === child.id);
                const score = stats?.totalScore ?? child.score;
                return (
                  <div key={child.id} className="flex items-center gap-4 p-3 rounded-xl bg-gray-50/50">
                    <span className="text-2xl w-10 text-center">{idx < 3 ? medals[idx] : <span className="text-gray-400 font-bold">{idx + 1}</span>}</span>
                    <div className="w-10 h-10 rounded-full flex items-center justify-center text-white font-bold"
                      style={{ backgroundColor: ['#4A90D9', '#7ED321', '#F5A623', '#E74C3C', '#9B59B6'][idx % 5] }}>
                      {child.name[0]}
                    </div>
                    <div className="flex-1">
                      <p className="font-medium">{child.name}</p>
                      <p className="text-xs text-gray-500">积分: {score} | 现金: ¥{(stats?.totalCash ?? ((child.score ?? 0) / 5)).toFixed(0)} | 物品: {stats?.totalItems ?? 0}</p>
                    </div>
                  </div>
                );
              })
            : sortedStats.map((stat, idx) => (
                <div key={stat.childId} className="flex items-center gap-4 p-3 rounded-xl bg-gray-50/50">
                  <span className="text-2xl w-10 text-center">{idx < 3 ? medals[idx] : <span className="text-gray-400 font-bold">{idx + 1}</span>}</span>
                  <div className="w-10 h-10 rounded-full flex items-center justify-center text-white font-bold"
                    style={{ backgroundColor: ['#4A90D9', '#7ED321', '#F5A623', '#E74C3C', '#9B59B6'][idx % 5] }}>
                    {stat.childName[0]}
                  </div>
                  <div className="flex-1">
                    <p className="font-medium">{stat.childName}</p>
                    <div className="flex gap-3 text-xs text-gray-500 mt-1">
                      <span>⭐ {stat.totalScore}</span>
                      <span>💰 ¥{stat.totalCash}</span>
                      <span>🎁 {stat.totalItems}</span>
                    </div>
                  </div>
                </div>
              ))
          }
        </div>
      </Card>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* 每个孩子累计统计 */}
        <Card className="p-5">
          <h3 className="text-sm font-semibold text-gray-700 mb-4">📊 累计统计</h3>
          {sortedStats.length === 0 && children.length === 0 ? (
            <div className="h-48 flex items-center justify-center text-gray-400">暂无数据</div>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b border-gray-200">
                    <th className="text-left py-3 px-3 text-gray-500 font-medium">孩子</th>
                    <th className="text-right py-3 px-3 text-gray-500 font-medium">累计积分</th>
                    <th className="text-right py-3 px-3 text-gray-500 font-medium">累计现金</th>
                    <th className="text-right py-3 px-3 text-gray-500 font-medium">累计物品</th>
                    <th className="text-right py-3 px-3 text-gray-500 font-medium">日均积分</th>
                  </tr>
                </thead>
                <tbody>
                  {sortedStats.length > 0 ? sortedStats.map((s, i) => (
                    <tr key={s.childId} className={`border-b border-gray-100 ${i % 2 === 0 ? '' : 'bg-gray-50/30'}`}>
                      <td className="py-3 px-3 font-medium">{s.childName}</td>
                      <td className="py-3 px-3 text-right text-[#4A90D9] font-medium">{s.totalScore}</td>
                      <td className="py-3 px-3 text-right text-green-600">¥{s.totalCash}</td>
                      <td className="py-3 px-3 text-right text-orange-600">{s.totalItems}</td>
                      <td className="py-3 px-3 text-right">{s.avgDailyScore}</td>
                    </tr>
                  )) : children.map((c, i) => (
                    <tr key={c.id} className={`border-b border-gray-100 ${i % 2 === 0 ? '' : 'bg-gray-50/30'}`}>
                      <td className="py-3 px-3 font-medium">{c.name}</td>
                      <td className="py-3 px-3 text-right text-[#4A90D9] font-medium">{c.score}</td>
                      <td className="py-3 px-3 text-right text-green-600">¥{(c.cash ?? 0).toFixed(0)}</td>
                      <td className="py-3 px-3 text-right text-orange-600">-</td>
                      <td className="py-3 px-3 text-right">-</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </Card>

        {/* 各类别积分分布 */}
        <Card className="p-5">
          <h3 className="text-sm font-semibold text-gray-700 mb-4">🍩 各类别积分分布</h3>
          {catChartData.length > 0 ? (
            <DonutChart data={catChartData} />
          ) : (
            <div className="h-64 flex items-center justify-center text-gray-400">暂无分类数据</div>
          )}
        </Card>

        {/* 月度对比柱状图 */}
        <Card className="p-5">
          <h3 className="text-sm font-semibold text-gray-700 mb-4">📊 孩子积分对比</h3>
          {monthData.length > 0 ? (
            <BarChart data={monthData} />
          ) : (
            <div className="h-48 flex items-center justify-center text-gray-400">暂无数据</div>
          )}
        </Card>

        {/* 交易次数统计 */}
        <Card className="p-5">
          <h3 className="text-sm font-semibold text-gray-700 mb-4">📈 交易次数统计</h3>
          {sortedStats.length === 0 ? (
            <div className="h-48 flex items-center justify-center text-gray-400">暂无数据</div>
          ) : (
            <div className="space-y-4">
              {sortedStats.map((s, i) => (
                <div key={s.childId}>
                  <div className="flex items-center justify-between mb-1">
                    <span className="text-sm font-medium">{s.childName}</span>
                    <span className="text-xs text-gray-500">总 {s.scoreCount + s.cashCount + s.itemCount} 次</span>
                  </div>
                  <div className="flex h-3 rounded-full overflow-hidden bg-gray-100">
                    {s.scoreCount > 0 && (
                      <div className="bg-[#4A90D9] transition-all" style={{ width: `${(s.scoreCount / (s.scoreCount + s.cashCount + s.itemCount)) * 100}%` }} />
                    )}
                    {s.cashCount > 0 && (
                      <div className="bg-green-500 transition-all" style={{ width: `${(s.cashCount / (s.scoreCount + s.cashCount + s.itemCount)) * 100}%` }} />
                    )}
                    {s.itemCount > 0 && (
                      <div className="bg-orange-400 transition-all" style={{ width: `${(s.itemCount / (s.scoreCount + s.cashCount + s.itemCount)) * 100}%` }} />
                    )}
                  </div>
                  <div className="flex gap-3 mt-1 text-xs text-gray-500">
                    <span>⭐ {s.scoreCount}</span>
                    <span>💰 {s.cashCount}</span>
                    <span>🎁 {s.itemCount}</span>
                  </div>
                </div>
              ))}
            </div>
          )}
        </Card>
      </div>
    </div>
  );
}
