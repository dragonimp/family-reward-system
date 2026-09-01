import { useCallback, useEffect, useState } from 'react';
import { Card } from '../components/Card';
import { useFamilyGroup } from '../contexts/FamilyGroupContext';
import { getGrowthStats } from '../services';
import type { ChildGrowthStats } from '../types';

function Trend({ items }: { items: ChildGrowthStats['trend'] }) {
  const max = Math.max(1, ...items.map((item) => item.records));
  return <div className="flex items-end gap-2 h-32 mt-4" aria-label="本周记录趋势">
    {items.map((item) => <div key={item.date} className="flex-1 h-full flex flex-col justify-end items-center gap-1">
      <span className="text-xs font-medium text-emerald-700">{item.records}</span>
      <div className="w-full max-w-10 rounded-t-lg bg-gradient-to-t from-emerald-500 to-teal-300" style={{ height: `${Math.max(5, item.records / max * 82)}px` }} />
      <span className="text-[11px] text-gray-400">{item.date}</span>
    </div>)}
  </div>;
}

export default function Stats() {
  const { selectedGroupId } = useFamilyGroup();
  const [children, setChildren] = useState<ChildGrowthStats[]>([]);
  const [loading, setLoading] = useState(true);
  const load = useCallback(async () => {
    setLoading(true);
    try {
      const payload = await getGrowthStats({ familyGroupId: selectedGroupId ?? undefined });
      setChildren(payload.children || []);
    } catch { setChildren([]); } finally { setLoading(false); }
  }, [selectedGroupId]);
  useEffect(() => { load(); }, [load]);

  return <div className="space-y-6">
    <div><h2 className="text-2xl font-bold text-gray-900">🌱 和过去的自己比</h2><p className="text-gray-500 mt-1">关注本周做到的事、连续记录和自己的变化，不进行孩子之间的横向排名。</p></div>
    {loading ? <div className="py-20 text-center text-gray-400">正在整理成长趋势...</div> : children.map((child) => <Card key={child.childId} className="p-5">
      <div className="flex items-center justify-between gap-3">
        <h3 className="text-lg font-bold text-gray-900">{child.childName}</h3>
        <span className={`rounded-full px-3 py-1 text-xs font-medium ${child.change >= 0 ? 'bg-emerald-50 text-emerald-700' : 'bg-blue-50 text-blue-700'}`}>比上周{child.change >= 0 ? `多 ${child.change}` : `少 ${Math.abs(child.change)}`} 条记录</span>
      </div>
      <div className="grid grid-cols-2 md:grid-cols-4 gap-3 mt-4">
        <div className="rounded-xl bg-emerald-50 p-3"><p className="text-xs text-gray-500">本周做到的事</p><p className="text-2xl font-bold text-emerald-700">{child.currentWeekRecords}</p></div>
        <div className="rounded-xl bg-gray-50 p-3"><p className="text-xs text-gray-500">上周记录</p><p className="text-2xl font-bold text-gray-700">{child.previousWeekRecords}</p></div>
        <div className="rounded-xl bg-amber-50 p-3"><p className="text-xs text-gray-500">本周活跃</p><p className="text-2xl font-bold text-amber-700">{child.activeDays} 天</p></div>
        <div className="rounded-xl bg-blue-50 p-3"><p className="text-xs text-gray-500">连续记录</p><p className="text-2xl font-bold text-blue-700">{child.streakDays} 天</p></div>
      </div>
      <Trend items={child.trend} />
    </Card>)}
    {!loading && children.length === 0 && <Card className="p-12 text-center text-gray-400">有了记录后，这里会展示与自己过去相比的变化</Card>}
  </div>;
}
