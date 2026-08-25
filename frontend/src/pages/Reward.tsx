import { Card } from '../components/Card';
import { Modal } from '../components/Modal';
import type { Child, Rule, WatchRewardRequest } from '../types';
import { useState, useEffect, useCallback, useRef } from 'react';
import { useNavigate } from 'react-router-dom';
import {
  approveRewardRequest,
  createTransaction,
  getChildren,
  getRewardRequests,
  getRules,
} from '../services';
import {
  buildRewardTransactionPayload,
  type RewardTransactionPreview,
  type RewardTransactionType,
} from './rewardTransaction';

export default function Reward() {
  const navigate = useNavigate();
  const [children, setChildren] = useState<Child[]>([]);
  const [rules, setRules] = useState<Rule[]>([]);
  const [pendingRequests, setPendingRequests] = useState<WatchRewardRequest[]>([]);
  const [loading, setLoading] = useState(true);
  const [selectedChild, setSelectedChild] = useState<number | null>(null);
  const [selectedRule, setSelectedRule] = useState<number | null>(null);
  const [positiveRulesOpen, setPositiveRulesOpen] = useState(false);
  const [negativeRulesOpen, setNegativeRulesOpen] = useState(false);
  const [customOperationOpen, setCustomOperationOpen] = useState(false);
  const [customAmount, setCustomAmount] = useState<number>(0);
  const [customType, setCustomType] = useState<RewardTransactionType>('score');
  const [customCategory, setCustomCategory] = useState('');
  const [customDescription, setCustomDescription] = useState('');
  const [voiceText, setVoiceText] = useState('');
  const [voiceListening, setVoiceListening] = useState(false);
  const recognitionRef = useRef<any>(null);
  const [approvingRequestId, setApprovingRequestId] = useState<number | null>(null);
  const [showConfirm, setShowConfirm] = useState(false);
  const [transactionPreview, setTransactionPreview] = useState<RewardTransactionPreview | null>(null);
  const [toast, setToast] = useState<{ show: boolean; message: string; type: 'success' | 'error' }>({ show: false, message: '', type: 'success' });

  const showToast = (message: string, type: 'success' | 'error' = 'success') => {
    setToast({ show: true, message, type });
    setTimeout(() => setToast({ show: false, message: '', type: 'success' }), 3000);
  };

  const loadData = useCallback(async (silent = false) => {
    try {
      if (!silent) setLoading(true);
      const [childrenRes, rulesRes, requestRes] = await Promise.all([
        getChildren({ ownedOnly: true }),
        getRules(),
        getRewardRequests({ status: 'pending', limit: 20 }),
      ]);
      const childList = Array.isArray(childrenRes) ? childrenRes : (childrenRes as any)?.data || [];
      const rulePayload = (rulesRes as any)?.data || rulesRes;
      const baseRules = Array.isArray(rulePayload) ? rulePayload : rulePayload?.rules || [];
      setChildren(childList);
      setRules(baseRules);
      setPendingRequests(Array.isArray(requestRes?.requests) ? requestRes.requests : []);
    } catch (error) {
      console.error('加载失败:', error);
      setChildren([]);
      setRules([]);
      setPendingRequests([]);
      showToast('数据加载失败，暂时无法操作', 'error');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    loadData();
  }, [loadData]);

  useEffect(() => {
    setSelectedChild(null);
    setSelectedRule(null);
    setShowConfirm(false);
    setTransactionPreview(null);
  }, []);

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

  const handleRuleSelect = (ruleId: number) => {
    setSelectedRule(ruleId);
    setPositiveRulesOpen(false);
    setNegativeRulesOpen(false);
    const rule = rules.find((r) => r.id === ruleId);
    if (rule) {
      setCustomAmount(Math.abs(rule.score));
    }
  };

  const applyLocalVoiceFallback = (text: string) => {
    const normalized = text.replace(/\s+/g, '');
    const child = children.find((item) => normalized.includes(item.name));
    if (!child) return;
    const numberMatch = normalized.match(/-?\d+(?:\.\d+)?/);
    if (!numberMatch) return;
    const rawAmount = Number(numberMatch[0]);
    const negative = rawAmount < 0 || /扣|减|罚|扣除|减少|兑换/.test(normalized);
    const amount = Math.abs(rawAmount) * (negative ? -1 : 1);

    setSelectedChild(child.id);
    setSelectedRule(null);
    setCustomType('score');
    setCustomAmount(amount);
    setCustomCategory(negative ? '扣分' : '奖励');
    setCustomDescription(text);
  };

  const startVoiceRecord = () => {
    const SpeechRecognition = (window as any).SpeechRecognition || (window as any).webkitSpeechRecognition;
    if (!SpeechRecognition) {
      showToast('当前浏览器不支持语音识别', 'error');
      return;
    }

    try {
      const rec = new SpeechRecognition();
      recognitionRef.current = rec;
      rec.lang = 'zh-CN';
      rec.interimResults = false;
      rec.maxAlternatives = 1;
      rec.onstart = () => setVoiceListening(true);
      rec.onresult = (event: any) => {
        const text = event.results?.[0]?.[0]?.transcript || '';
        setVoiceText(text);
        if (text) {
          applyLocalVoiceFallback(text);
        }
      };
      rec.onerror = () => {
        showToast('语音识别失败，请重试', 'error');
      };
      rec.onend = () => setVoiceListening(false);
      rec.start();
    } catch (error) {
      console.error(error);
      setVoiceListening(false);
      showToast('语音初始化失败', 'error');
    }
  };

  const handleOpenConfirm = () => {
    if (!selectedChild) {
      showToast('请选择一个孩子', 'error');
      return;
    }
    const child = children.find((c) => c.id === selectedChild);
    if (!child) {
      showToast('所选孩子不存在，请重新选择', 'error');
      return;
    }
    const rule = rules.find((r) => r.id === selectedRule);
    const amount = selectedRule && rule ? rule.score : customAmount;

    setTransactionPreview({
      child,
      rule,
      amount,
      type: selectedRule && rule ? 'score' : customType,
      category: selectedRule && rule ? rule.category : customCategory,
      description: selectedRule && rule ? rule.name : customDescription,
    });
    setShowConfirm(true);
  };

  const handleConfirm = async () => {
    if (!transactionPreview || !selectedChild) return;
    const txData = buildRewardTransactionPayload(transactionPreview);

    try {
      await createTransaction(txData);
      showToast('操作成功！');
      setShowConfirm(false);
      await loadData();
      // Reset form
      setSelectedRule(null);
      setCustomAmount(0);
      setCustomCategory('');
      setCustomDescription('');
    } catch (error) {
      console.error('操作失败:', error);
      showToast('操作失败，请重试', 'error');
    }
  };

  const handleApproveRequest = async (requestId: number) => {
    try {
      setApprovingRequestId(requestId);
      await approveRewardRequest(requestId, {
        reviewNote: '家长端确认领取',
      });
      showToast('申请已确认，积分已入账');
      await loadData(true);
    } catch (error) {
      console.error('确认申请失败:', error);
      showToast(error instanceof Error ? error.message : '确认申请失败', 'error');
    } finally {
      setApprovingRequestId(null);
    }
  };

  const formatRequestTime = (value: string) => {
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) return '';
    return date.toLocaleString('zh-CN', {
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
    });
  };

  const positiveRules = rules.filter((r) => r.enabled && r.type === 'positive');
  const negativeRules = rules.filter((r) => r.enabled && r.type === 'negative');
  const selectedRuleDetails = rules.find((rule) => rule.id === selectedRule);

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
      {/* Toast */}
      {toast.show && (
        <div className={`fixed left-3 right-3 top-3 z-50 rounded-lg px-4 py-3 text-sm text-white shadow-lg transition-all sm:left-auto sm:right-4 sm:top-4 sm:px-6
          ${toast.type === 'success' ? 'bg-green-500' : 'bg-red-500'}`}>
          {toast.message}
        </div>
      )}

      <div>
        <h2 className="text-2xl font-bold text-gray-900">积分操作</h2>
        <p className="text-gray-500 mt-1">只操作当前家长账号名下的孩子，积分在各圈子中同步</p>
      </div>

      <Card className="border-[#4A90D9]/30 p-4 sm:p-5">
        <div className="flex items-start justify-between gap-3">
          <div>
            <h3 className="text-base font-semibold text-gray-800">快速积分操作</h3>
            <p className="mt-1 text-xs text-gray-500">选择孩子和行为规则后即可确认</p>
          </div>
          {selectedRuleDetails && (
            <div className={`shrink-0 rounded-full px-2.5 py-1 text-xs font-semibold ${selectedRuleDetails.score >= 0 ? 'bg-green-50 text-green-700' : 'bg-red-50 text-red-700'}`}>
              {selectedRuleDetails.score > 0 ? '+' : ''}{selectedRuleDetails.score} 分
            </div>
          )}
        </div>

        <section className="mt-5">
          <h4 className="text-sm font-semibold text-gray-700">1. 选择孩子</h4>
          <div className="mt-3 flex flex-wrap gap-2">
            {children.map((child) => (
              <button
                key={child.id}
                type="button"
                aria-pressed={selectedChild === child.id}
                onClick={() => setSelectedChild(child.id)}
                className={`flex items-center gap-2 rounded-xl border px-2.5 py-2 text-left transition duration-150 ease-out active:scale-[0.98]
                  ${selectedChild === child.id
                    ? 'border-[#4A90D9] bg-[#4A90D9]/10 shadow-sm ring-1 ring-[#4A90D9]/20'
                    : 'border-gray-200 bg-white hover:border-[#4A90D9]/50 hover:bg-[#4A90D9]/5'}`}
              >
                <span className={`flex h-8 w-8 items-center justify-center rounded-full text-sm font-bold text-white ${['bg-[#4A90D9]', 'bg-[#7ED321]', 'bg-[#F5A623]', 'bg-[#E74C3C]', 'bg-purple-500'][child.id % 5]}`}>
                  {child.name[0]}
                </span>
                <span>
                  <span className="block text-sm font-medium text-gray-800">{child.name}</span>
                  <span className="block text-xs text-gray-500">⭐{child.score} · 💰{child.cash}</span>
                </span>
              </button>
            ))}
          </div>
        </section>

        <section className="mt-5">
          <h4 className="text-sm font-semibold text-gray-700">2. 选择行为</h4>
          <div className="mt-3 space-y-2">
            <div className="overflow-hidden rounded-lg border border-green-100">
              <button
                type="button"
                aria-expanded={positiveRulesOpen}
                onClick={() => setPositiveRulesOpen((open) => !open)}
                className="flex w-full items-center justify-between bg-green-50/60 px-3 py-2.5 text-left text-sm font-medium text-green-700 transition-colors hover:bg-green-50"
              >
                <span>👍 加分规则 <span className="ml-1 text-xs font-normal text-green-600">{positiveRules.length} 条</span></span>
                <span className="text-xs">{positiveRulesOpen ? '收起' : '查看'}</span>
              </button>
              {positiveRulesOpen && (
                <div className="flex flex-wrap gap-2 border-t border-green-100 bg-white p-3 animate-fade-in">
                  {positiveRules.map((rule) => (
                    <button
                      key={rule.id}
                      type="button"
                      onClick={() => handleRuleSelect(rule.id)}
                      className={`rounded-lg border px-3 py-2 text-sm transition duration-150 ease-out active:scale-[0.98]
                        ${selectedRule === rule.id ? 'border-green-500 bg-green-50 text-green-700' : 'border-gray-200 hover:border-green-300 hover:bg-green-50/50'}`}
                    >
                      {rule.name} (+{rule.score})
                    </button>
                  ))}
                </div>
              )}
            </div>

            <div className="overflow-hidden rounded-lg border border-red-100">
              <button
                type="button"
                aria-expanded={negativeRulesOpen}
                onClick={() => setNegativeRulesOpen((open) => !open)}
                className="flex w-full items-center justify-between bg-red-50/60 px-3 py-2.5 text-left text-sm font-medium text-red-700 transition-colors hover:bg-red-50"
              >
                <span>👎 减分规则 <span className="ml-1 text-xs font-normal text-red-600">{negativeRules.length} 条</span></span>
                <span className="text-xs">{negativeRulesOpen ? '收起' : '查看'}</span>
              </button>
              {negativeRulesOpen && (
                <div className="flex flex-wrap gap-2 border-t border-red-100 bg-white p-3 animate-fade-in">
                  {negativeRules.map((rule) => (
                    <button
                      key={rule.id}
                      type="button"
                      onClick={() => handleRuleSelect(rule.id)}
                      className={`rounded-lg border px-3 py-2 text-sm transition duration-150 ease-out active:scale-[0.98]
                        ${selectedRule === rule.id ? 'border-red-500 bg-red-50 text-red-700' : 'border-gray-200 hover:border-red-300 hover:bg-red-50/50'}`}
                    >
                      {rule.name} ({rule.score})
                    </button>
                  ))}
                </div>
              )}
            </div>
          </div>
          {selectedRuleDetails && (
            <p className="mt-3 rounded-lg bg-gray-50 px-3 py-2 text-sm text-gray-700">
              已选：<span className="font-medium">{selectedRuleDetails.name}</span>，{selectedRuleDetails.score > 0 ? '+' : ''}{selectedRuleDetails.score} 分
            </p>
          )}
        </section>

        <section className="mt-4 overflow-hidden rounded-lg border border-gray-200">
          <button
            type="button"
            aria-expanded={customOperationOpen}
            onClick={() => setCustomOperationOpen((open) => !open)}
            className="flex w-full items-center justify-between bg-gray-50 px-3 py-2.5 text-left text-sm font-medium text-gray-700 transition-colors hover:bg-gray-100"
          >
            <span>自定义操作</span>
            <span className="text-xs text-gray-500">{customOperationOpen ? '收起' : '展开'}</span>
          </button>
          {customOperationOpen && (
            <div className="grid grid-cols-1 gap-4 border-t border-gray-200 bg-white p-3 animate-fade-in sm:grid-cols-2 lg:grid-cols-4">
              <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">操作类型</label>
              <select
                value={customType}
                onChange={(e) => setCustomType(e.target.value as RewardTransactionType)}
                className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-[#4A90D9]"
              >
                <option value="score">积分</option>
                <option value="cash">现金</option>
                <option value="item">物品</option>
              </select>
            </div>
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">数量</label>
              <input
                type="number"
                value={customAmount}
                onChange={(e) => setCustomAmount(parseInt(e.target.value) || 0)}
                className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-[#4A90D9]"
              />
            </div>
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">分类</label>
              <input
                type="text"
                value={customCategory}
                onChange={(e) => setCustomCategory(e.target.value)}
                placeholder="如：学习、生活"
                className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-[#4A90D9]"
              />
            </div>
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">描述</label>
              <input
                type="text"
                value={customDescription}
                onChange={(e) => setCustomDescription(e.target.value)}
                placeholder="操作描述"
                className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-[#4A90D9]"
              />
            </div>
            </div>
          )}
        </section>

        <div className="mt-5 flex justify-end border-t border-gray-100 pt-4">
          <button
            type="button"
            onClick={handleOpenConfirm}
            className="w-full rounded-lg bg-[#4A90D9] px-6 py-3 text-base font-semibold text-white shadow-md transition duration-150 hover:bg-[#3A7BC8] active:scale-[0.99] sm:w-auto"
          >
            ✅ 确认操作
          </button>
        </div>
      </Card>

      <Card className="p-4 sm:p-5">
        <div className="mb-4 flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
          <div>
            <h3 className="text-sm font-semibold text-gray-700">待确认申请</h3>
            <p className="mt-1 text-xs text-gray-500">孩子从手表端提交的积分申请会显示在这里</p>
          </div>
          <span className="rounded-full bg-orange-50 px-3 py-1 text-sm font-medium text-orange-700">{pendingRequests.length} 条</span>
        </div>
        {pendingRequests.length === 0 ? (
          <div className="rounded-lg border border-dashed border-gray-200 py-6 text-center text-sm text-gray-400">暂无待确认申请</div>
        ) : (
          <div className="grid grid-cols-1 gap-3 lg:grid-cols-2">
            {pendingRequests.map((item) => (
              <div key={item.id} className="rounded-lg border border-orange-100 bg-orange-50/50 p-4">
                <div className="flex items-start justify-between gap-3">
                  <div className="min-w-0">
                    <div className="flex flex-wrap items-center gap-2">
                      <span className="font-semibold text-gray-900">{item.childName}</span>
                      <span className="rounded-full bg-white px-2 py-0.5 text-xs font-medium text-orange-700">+{item.points} 分</span>
                    </div>
                    <p className="mt-1 truncate text-sm text-gray-700">{item.title}</p>
                    <p className="mt-1 text-xs text-gray-500">{item.category || '手表申请'}{item.requestedAt ? ` · ${formatRequestTime(item.requestedAt)}` : ''}</p>
                    {item.note && <p className="mt-2 text-xs text-gray-500">{item.note}</p>}
                  </div>
                  <button type="button" disabled={approvingRequestId === item.id} onClick={() => handleApproveRequest(item.id)} className="shrink-0 rounded-lg bg-[#4A90D9] px-3 py-2 text-sm font-medium text-white transition-colors hover:bg-[#3A7BC8] disabled:opacity-60">
                    {approvingRequestId === item.id ? '确认中...' : '确认'}
                  </button>
                </div>
              </div>
            ))}
          </div>
        )}
      </Card>

      <Card className="border-[#4A90D9]/30 p-4 sm:p-5">
        <div className="flex flex-col justify-between gap-3 sm:flex-row sm:items-center">
          <div>
            <h3 className="text-sm font-semibold text-gray-700">语音记录积分</h3>
            <p className="mt-1 text-xs text-gray-500">例如：给某个孩子加5分，因为主动完成任务；或扣10分，因为违反约定。</p>
            {voiceText && <p className="mt-2 text-sm text-[#4A90D9]">浏览器识别：{voiceText}</p>}
          </div>
          <button type="button" onClick={startVoiceRecord} disabled={voiceListening || children.length === 0} className="w-full rounded-lg bg-[#4A90D9] px-4 py-2 text-sm font-medium text-white transition-colors hover:bg-[#3A7BC8] disabled:opacity-60 sm:w-auto">
            {voiceListening ? '正在听...' : '🎤 语音记录'}
          </button>
        </div>
      </Card>

      {/* 确认弹窗 */}
      <Modal
        isOpen={showConfirm}
        onClose={() => setShowConfirm(false)}
        title="确认操作"
        footer={
          <>
            <button onClick={() => setShowConfirm(false)} className="px-4 py-2 text-gray-600 hover:bg-gray-100 rounded-lg">
              取消
            </button>
            <button onClick={handleConfirm} className="btn-primary">
              确认执行
            </button>
          </>
        }
      >
        {transactionPreview && (
          <div className="space-y-3">
            <div className="flex justify-between">
              <span className="text-gray-500">孩子</span>
              <span className="font-medium">{transactionPreview.child.name}</span>
            </div>
            <div className="flex justify-between">
              <span className="text-gray-500">类型</span>
              <span className="font-medium">
                {transactionPreview.type === 'score' ? '⭐ 积分' : transactionPreview.type === 'cash' ? '💰 现金' : '🎁 物品'}
              </span>
            </div>
            <div className="flex justify-between">
              <span className="text-gray-500">数量</span>
              <span className="font-medium text-lg text-[#4A90D9]">
                {transactionPreview.amount > 0 ? '+' : ''}{transactionPreview.amount}
              </span>
            </div>
            <div className="flex justify-between">
              <span className="text-gray-500">分类</span>
              <span className="font-medium">{transactionPreview.category}</span>
            </div>
            <div className="flex justify-between">
              <span className="text-gray-500">描述</span>
              <span className="font-medium">{transactionPreview.description}</span>
            </div>
          </div>
        )}
      </Modal>
    </div>
  );
}
