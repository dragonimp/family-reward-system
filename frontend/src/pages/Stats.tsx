import { Card } from '../components/Card';
import type { Child } from '../types';
import { useState, useEffect, useCallback } from 'react';
import { getChildStats, getCategoryStats } from '../services';
import { useFamilyGroup } from '../contexts/FamilyGroupContext';

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
  const { selectedGroupId } = useFamilyGroup();
  const [children, setChildren] = useState<Child[]>([]);
  const [categoryData, setCategoryData] = useState<Array<{ category: string; total: number }>>([]);
  const [loading, setLoading] = useState(true);

  const loadData = useCallback(async () => {
    try {
      setLoading(true);
      const [statsRes, catRes] = await Promise.all([
        getChildStats({ familyGroupId: selectedGroupId ?? undefined }),
        getCategoryStats({ familyGroupId: selectedGroupId ?? undefined }),
      ]);

      const statsPayload = (statsRes as any).data ?? statsRes;
      const catPayload = (catRes as any).data ?? catRes;
      setChildren(Array.isArray(statsPayload?.children) ? statsPayload.children : []);
      setCategoryData(Array.isArray(catPayload) ? catPayload : []);
    } catch (error) {
      console.error('加载失败:', error);
      setChildren([]);
      setCategoryData([]);
    } finally {
      setLoading(false);
    }
  }, [selectedGroupId]);

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
  const sortedChildren = [...children].sort((a, b) => (b.score ?? 0) - (a.score ?? 0));
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
    value: child.score ?? 0,
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
          {sortedChildren.length === 0 ? (
            <div className="h-24 flex items-center justify-center text-gray-400">暂无数据</div>
          ) : (
            sortedChildren.map((child, idx) => (
                <div key={child.id} className="flex items-center gap-4 p-3 rounded-xl bg-gray-50/50">
                  <span className="text-2xl w-10 text-center">{idx < 3 ? medals[idx] : <span className="text-gray-400 font-bold">{idx + 1}</span>}</span>
                  <div className="w-10 h-10 rounded-full flex items-center justify-center text-white font-bold"
                    style={{ backgroundColor: ['#4A90D9', '#7ED321', '#F5A623', '#E74C3C', '#9B59B6'][idx % 5] }}>
                    {child.name[0]}
                  </div>
                  <div className="flex-1">
                    <p className="font-medium">{child.name}</p>
                    <div className="flex gap-3 text-xs text-gray-500 mt-1">
                      <span>⭐ {child.score ?? 0}</span>
                      <span>💰 ¥{child.cash ?? 0}</span>
                      <span>🎁 {child.items ?? 0}</span>
                    </div>
                  </div>
                </div>
              ))
          )}
        </div>
      </Card>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* 每个孩子累计统计 */}
        <Card className="p-5">
          <h3 className="text-sm font-semibold text-gray-700 mb-4">📊 累计统计</h3>
          {sortedChildren.length === 0 ? (
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
                  {sortedChildren.map((c, i) => (
                    <tr key={c.id} className={`border-b border-gray-100 ${i % 2 === 0 ? '' : 'bg-gray-50/30'}`}>
                      <td className="py-3 px-3 font-medium">{c.name}</td>
                      <td className="py-3 px-3 text-right text-[#4A90D9] font-medium">{c.score ?? 0}</td>
                      <td className="py-3 px-3 text-right text-green-600">¥{(c.cash ?? 0).toFixed(0)}</td>
                      <td className="py-3 px-3 text-right text-orange-600">{c.items ?? 0}</td>
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
          <div className="h-48 flex items-center justify-center text-gray-400">暂无交易次数数据</div>
        </Card>
      </div>
    </div>
  );
}
