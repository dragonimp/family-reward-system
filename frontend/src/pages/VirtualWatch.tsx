import { useEffect, useMemo, useState } from 'react';
import { getChildren } from '../services';
import type { Child } from '../types';

export default function VirtualWatchPage() {
  const [children, setChildren] = useState<Child[]>([]);
  const [selectedChildId, setSelectedChildId] = useState<number | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  useEffect(() => {
    getChildren({ ownedOnly: true })
      .then((result) => {
        const ownedChildren = result as unknown as Child[];
        setChildren(ownedChildren);
        setSelectedChildId((current) => current ?? ownedChildren[0]?.id ?? null);
      })
      .catch((reason) => setError(reason instanceof Error ? reason.message : '孩子信息加载失败'))
      .finally(() => setLoading(false));
  }, []);

  const selectedChild = useMemo(
    () => children.find((child) => child.id === selectedChildId) ?? null,
    [children, selectedChildId],
  );

  if (loading) {
    return <div className="flex min-h-[320px] items-center justify-center text-sm text-gray-500">正在加载虚拟手表...</div>;
  }

  if (error) {
    return <div className="flex min-h-[320px] items-center justify-center text-sm text-red-600">{error}</div>;
  }

  if (!selectedChild) {
    return <div className="flex min-h-[320px] items-center justify-center text-sm text-gray-500">请先在孩子管理中添加孩子</div>;
  }

  return (
    <section className="mx-auto flex min-h-full w-full max-w-2xl flex-col gap-3">
      <div className="flex items-center justify-between gap-3">
        <div className="min-w-0">
          <h2 className="text-lg font-semibold text-gray-900">虚拟手表</h2>
          <p className="truncate text-xs text-gray-500">{selectedChild.name}的手表界面</p>
        </div>
        <label className="shrink-0">
          <span className="sr-only">选择孩子</span>
          <select
            aria-label="选择孩子"
            value={selectedChild.id}
            onChange={(event) => setSelectedChildId(Number(event.target.value))}
            className="h-10 max-w-[150px] rounded-md border border-gray-300 bg-white px-3 text-sm text-gray-700"
          >
            {children.map((child) => (
              <option key={child.id} value={child.id}>{child.name}</option>
            ))}
          </select>
        </label>
      </div>

      <div className="flex min-h-[320px] flex-1 items-center justify-center overflow-hidden rounded-md border border-gray-200 bg-[#dce8e2]">
        <iframe
          key={selectedChild.id}
          title={`${selectedChild.name}的虚拟手表`}
          src={`/watch?previewChildId=${encodeURIComponent(selectedChild.id)}`}
          className="h-[min(62dvh,520px)] min-h-[320px] w-full border-0"
        />
      </div>
    </section>
  );
}
