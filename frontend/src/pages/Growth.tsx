import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { Card } from '../components/Card';
import { getGrowthReports, getWarmMoments } from '../services';
import type { GrowthReport, WarmMoment } from '../types';

const periodLabels = { daily: '每日', weekly: '每周', monthly: '每月' } as const;
type Period = keyof typeof periodLabels;

function ReportCard({ report }: { report: GrowthReport }) {
  return (
    <Card className="p-5 border border-emerald-100">
      <div className="flex items-center justify-between gap-3 mb-4">
        <h3 className="font-bold text-gray-900">{report.audience === 'parent' ? '💛 家长报告' : `🌱 ${report.subjectName}的报告`}</h3>
        <span className="text-xs text-gray-400">{report.periodStart} 至 {report.periodEnd}</span>
      </div>
      <div className="space-y-3 text-sm leading-6">
        <p className="rounded-xl bg-amber-50 p-3 text-amber-900">{report.praise}</p>
        <p className="rounded-xl bg-blue-50 p-3 text-blue-900">{report.nextStep}</p>
        <p className="rounded-xl bg-emerald-50 p-3 text-emerald-900">{report.changeSummary}</p>
      </div>
      <div className="mt-3 flex flex-wrap items-center gap-2 text-xs text-gray-400"><span>依据 {report.sourceCount} 条具体记录生成：</span>{report.sourceRefs.map((item) => <Link className="text-emerald-700 hover:underline" key={`${item.type}-${item.id}`} to={item.type === 'warmMoment' ? `/growth#warm-moment-${item.id}` : `/transactions?recordId=${item.id}`}>记录 #{item.id}</Link>)}{report.sourceRefs.length === 0 && <span>暂无来源记录</span>}</div>
    </Card>
  );
}

export default function Growth() {
  const [period, setPeriod] = useState<Period>('daily');
  const [childReports, setChildReports] = useState<GrowthReport[]>([]);
  const [parentReports, setParentReports] = useState<GrowthReport[]>([]);
  const [moments, setMoments] = useState<WarmMoment[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let active = true;
    setLoading(true);
    Promise.all([
      getGrowthReports({ audience: 'child', period }),
      getGrowthReports({ audience: 'parent', period }),
      getWarmMoments({ limit: 40 }),
    ]).then(([children, parents, warm]) => {
      if (!active) return;
      setChildReports(children.reports || []);
      setParentReports(parents.reports || []);
      setMoments(warm.moments || []);
    }).catch(() => {
      if (!active) return;
      setChildReports([]); setParentReports([]); setMoments([]);
    }).finally(() => active && setLoading(false));
    return () => { active = false; };
  }, [period]);

  return (
    <div className="space-y-6">
      <div className="flex flex-col sm:flex-row sm:items-end sm:justify-between gap-3">
        <div>
          <h2 className="text-2xl font-bold text-gray-900">💛 共同成长</h2>
          <p className="mt-1 text-sm text-gray-500">看见孩子的努力，也看见爸爸妈妈的闪光时刻</p>
        </div>
        <div className="inline-flex rounded-xl bg-white border border-gray-200 p-1">
          {(Object.keys(periodLabels) as Period[]).map((item) => (
            <button key={item} onClick={() => setPeriod(item)} className={`px-4 py-2 rounded-lg text-sm font-medium ${period === item ? 'bg-emerald-600 text-white' : 'text-gray-600 hover:bg-gray-50'}`}>{periodLabels[item]}</button>
          ))}
        </div>
      </div>

      {loading ? <div className="py-16 text-center text-gray-400">正在整理成长记录...</div> : (
        <>
          <section className="grid grid-cols-1 xl:grid-cols-2 gap-5">
            {[...parentReports, ...childReports].map((report) => <ReportCard key={`${report.audience}-${report.id}`} report={report} />)}
          </section>
          <Card className="p-5">
            <h3 className="font-bold text-gray-900 mb-1">孩子眼中的家长暖心时刻</h3>
            <p className="text-sm text-gray-500 mb-4">这里只保留孩子说出的具体感受，不评分、不排名。</p>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
              {moments.map((moment) => (
                <article id={`warm-moment-${moment.id}`} key={moment.id} className="rounded-2xl bg-rose-50 border border-rose-100 p-4">
                  <p className="text-gray-800 leading-6">“{moment.content}”</p>
                  <p className="mt-2 text-xs text-gray-500">{moment.childName} 记录了 {moment.parentDisplayName} · {new Date(moment.createdAt).toLocaleString('zh-CN')}</p>
                </article>
              ))}
              {moments.length === 0 && <p className="col-span-full py-10 text-center text-gray-400">手表记录后，暖心内容会出现在这里</p>}
            </div>
          </Card>
        </>
      )}
    </div>
  );
}
