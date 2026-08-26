import { useEffect, useState } from 'react';
import { createSubscriptionCheckout, createSubscriptionOrder, getSubscription, type CheckoutSession, type FamilySubscription } from '../services';

export default function MySubscriptionPage() {
  const [subscription, setSubscription] = useState<FamilySubscription | null>(null);
  const [checkout, setCheckout] = useState<CheckoutSession | null>(null);
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(true);

  const load = async () => {
    setLoading(true); setError('');
    try { setSubscription(await getSubscription()); } catch (err: any) { setError(err.message || '无法读取订阅信息'); } finally { setLoading(false); }
  };
  useEffect(() => { void load(); }, []);
  const startCheckout = async () => {
    setError('');
    try { setCheckout(await createSubscriptionCheckout()); } catch (err: any) { setError(err.message || '暂时无法创建购买订单'); }
  };
  const pay = async (channel: 'wechatpay' | 'alipay') => {
    if (!checkout) return;
    setError('');
    try {
      const order = await createSubscriptionOrder(checkout.id, channel);
      if (order.paymentUrl) window.location.assign(order.paymentUrl);
      else setError('支付订单已创建，请刷新订阅状态。');
    } catch (err: any) { setError(err.message || '创建支付订单失败'); }
  };
  const current = subscription?.subscription;
  return <div className="mx-auto max-w-2xl space-y-5">
    <div><h2 className="text-2xl font-bold text-gray-800">我的订阅</h2><p className="mt-1 text-sm text-gray-500">家加分普通功能永久免费；VIP家庭+ 仅增加动态表盘。</p></div>
    {error && <div className="rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-700">{error}</div>}
    {loading ? <div className="rounded-xl bg-white p-6 text-gray-500">正在读取订阅信息…</div> : <>
      <section className="rounded-xl border border-gray-200 bg-white p-5 shadow-sm"><div className="flex items-start justify-between gap-4"><div><h3 className="text-lg font-semibold">普通用户</h3><p className="mt-2 text-sm text-gray-600">免费 · 家庭、积分、规则、手表等全部基础功能</p></div><b className="text-[#4A90D9]">已包含</b></div></section>
      <section className="rounded-xl border border-amber-200 bg-amber-50 p-5 shadow-sm"><div className="flex items-start justify-between gap-4"><div><h3 className="text-lg font-semibold">VIP家庭+</h3><p className="mt-2 text-sm text-gray-600">¥9.9/月 · 额外解锁动态表盘</p>{current && <p className="mt-2 text-sm text-emerald-700">当前已生效，至 {new Date(current.expiresAt).toLocaleString('zh-CN')}。</p>}</div><b className={subscription?.vipWatchFaces ? 'text-emerald-700' : 'text-gray-600'}>{subscription?.vipWatchFaces ? '已开通' : '未开通'}</b></div>
        {!subscription?.vipWatchFaces && !checkout && <button type="button" onClick={() => void startCheckout()} className="mt-4 rounded-lg bg-[#4A90D9] px-4 py-2 text-sm font-medium text-white">开通 VIP家庭+</button>}
        {checkout && <div className="mt-4 rounded-lg border border-amber-200 bg-white p-4"><p className="text-sm text-gray-700">应付 ¥{(checkout.amountCents / 100).toFixed(2)}，请选择支付方式：</p><div className="mt-3 flex gap-3"><button type="button" onClick={() => void pay('wechatpay')} className="rounded bg-emerald-600 px-3 py-2 text-sm text-white">微信支付</button><button type="button" onClick={() => void pay('alipay')} className="rounded bg-blue-600 px-3 py-2 text-sm text-white">支付宝</button></div></div>}
      </section>
      <button type="button" onClick={() => void load()} className="text-sm text-[#4A90D9]">刷新订阅状态</button>
    </>}
  </div>;
}
