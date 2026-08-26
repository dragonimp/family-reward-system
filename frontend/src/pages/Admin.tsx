import { useEffect, useState } from 'react';
import { bootstrapAdminCatalog, getAdminPlans, getAdminUsers, setAdminPlanFeature, setAdminUserStatus, type AdminPlanPayload, type AdminUser } from '../services';

export default function AdminPage() {
  const [users, setUsers] = useState<AdminUser[]>([]);
  const [plans, setPlans] = useState<AdminPlanPayload | null>(null);
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(true);

  const load = async () => {
    setLoading(true); setError('');
    try {
      const [userPayload, planPayload] = await Promise.all([getAdminUsers(), getAdminPlans()]);
      setUsers(userPayload.users); setPlans(planPayload);
    } catch (err: any) {
      setError(err?.response?.data?.error || err?.response?.data?.message || '无法读取应用后台数据');
    } finally { setLoading(false); }
  };
  useEffect(() => { void load(); }, []);

  const updateUser = async (user: AdminUser) => {
    const status = user.status === 'active' ? 'disabled' : 'active';
    const reason = status === 'disabled' ? window.prompt('停用原因（可选）', '') ?? '' : '';
    try { await setAdminUserStatus(user.unifiedUserId, { status, reason }); await load(); }
    catch (err: any) { setError(err?.response?.data?.error || '更新用户状态失败'); }
  };
  const toggleVipFace = async () => {
    const feature = plans?.features.find((item) => item.planCode === 'vip-home-plus' && item.featureCode === 'vip_watch_faces');
    try { await setAdminPlanFeature('vip-home-plus', 'vip_watch_faces', !(feature?.enabled ?? false)); await load(); }
    catch (err: any) { setError(err?.response?.data?.error || '更新套餐权益失败'); }
  };
  const bootstrapCatalog = async () => {
    try { await bootstrapAdminCatalog(); await load(); }
    catch (err: any) { setError(err?.response?.data?.error || '初始化支付中心商品失败'); }
  };

  if (loading) return <div className="p-6 text-gray-500">正在加载应用后台…</div>;
  return <div className="mx-auto max-w-6xl space-y-6">
    <div><h2 className="text-2xl font-bold text-gray-800">家加分应用后台</h2><p className="mt-1 text-sm text-gray-500">管理应用用户、套餐及唯一的 VIP 扩展权益。</p></div>
    {error && <div className="rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-700">{error}</div>}
    <section className="rounded-xl bg-white p-5 shadow-sm">
      <div className="flex items-center justify-between"><h3 className="text-lg font-semibold">套餐配置</h3><button type="button" onClick={() => void bootstrapCatalog()} className="text-sm text-[#4A90D9]">初始化/同步支付商品</button></div>
      <p className="mt-1 text-sm text-gray-500">普通套餐免费，包含家加分全部基础功能；VIP家庭+ 仅额外提供动态表盘。</p>
      <div className="mt-4 grid gap-3 md:grid-cols-2">
        <div className="rounded-lg border p-4"><b>普通用户</b><p className="mt-2 text-sm text-gray-600">免费 · 所有基础功能</p></div>
        <div className="rounded-lg border border-amber-200 bg-amber-50 p-4"><b>VIP家庭+</b><p className="mt-2 text-sm text-gray-600">¥9.9/月 · 仅增加动态表盘</p>
          <button type="button" onClick={toggleVipFace} className="mt-3 rounded bg-[#4A90D9] px-3 py-2 text-sm text-white">
            {plans?.features.some((item) => item.planCode === 'vip-home-plus' && item.featureCode === 'vip_watch_faces' && item.enabled) ? '已启用动态表盘，点击关闭' : '启用动态表盘'}
          </button>
        </div>
      </div>
    </section>
    <section className="rounded-xl bg-white p-5 shadow-sm"><div className="flex items-center justify-between"><h3 className="text-lg font-semibold">应用用户</h3><button type="button" onClick={() => void load()} className="text-sm text-[#4A90D9]">刷新</button></div>
      <div className="mt-4 overflow-x-auto"><table className="min-w-full text-left text-sm"><thead className="border-b text-gray-500"><tr><th className="p-2">用户</th><th className="p-2">身份</th><th className="p-2">孩子/设备</th><th className="p-2">套餐</th><th className="p-2">状态</th><th className="p-2">操作</th></tr></thead><tbody>
        {users.map((user) => <tr key={`${user.unifiedUserId}-${user.channel}`} className="border-b"><td className="p-2">{user.username}</td><td className="p-2">{user.role}</td><td className="p-2">{user.childCount} / {user.activeDeviceCount}</td><td className="p-2">{user.subscriptionPlanCode || '普通用户'}</td><td className="p-2">{user.hasAppProfile ? (user.status === 'active' ? '正常' : '已停用') : '尚未进入应用'}</td><td className="p-2">{user.hasAppProfile ? <button type="button" onClick={() => void updateUser(user)} className="text-[#4A90D9]">{user.status === 'active' ? '停用' : '恢复'}</button> : <span className="text-gray-400">—</span>}</td></tr>)}
      </tbody></table></div>
    </section>
  </div>;
}
