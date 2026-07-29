import { Card } from '../components/Card';
import { Modal } from '../components/Modal';
import type { Child, Rule, Transaction } from '../types';
import { useState, useEffect, useCallback, useRef } from 'react';
import { useNavigate } from 'react-router-dom';
import { getChildren, getRules, createTransaction, parseRewardVoice } from '../services';

type TransactionType = 'score' | 'cash' | 'item';

export default function Reward() {
  const navigate = useNavigate();
  const [children, setChildren] = useState<Child[]>([]);
  const [rules, setRules] = useState<Rule[]>([]);
  const [loading, setLoading] = useState(true);
  const [selectedChild, setSelectedChild] = useState<number | null>(null);
  const [selectedRule, setSelectedRule] = useState<number | null>(null);
  const [customAmount, setCustomAmount] = useState<number>(0);
  const [customType, setCustomType] = useState<TransactionType>('score');
  const [customCategory, setCustomCategory] = useState('');
  const [customDescription, setCustomDescription] = useState('');
  const [voiceText, setVoiceText] = useState('');
  const [voiceListening, setVoiceListening] = useState(false);
  const [voiceParsing, setVoiceParsing] = useState(false);
  const recognitionRef = useRef<any>(null);
  const [showConfirm, setShowConfirm] = useState(false);
  const [transactionPreview, setTransactionPreview] = useState<any>(null);
  const [toast, setToast] = useState<{ show: boolean; message: string; type: 'success' | 'error' }>({ show: false, message: '', type: 'success' });

  const showToast = (message: string, type: 'success' | 'error' = 'success') => {
    setToast({ show: true, message, type });
    setTimeout(() => setToast({ show: false, message: '', type: 'success' }), 3000);
  };

  const loadData = useCallback(async (silent = false) => {
    try {
      if (!silent) setLoading(true);
      const [childrenRes, rulesRes] = await Promise.all([getChildren(), getRules()]);
      const childList = Array.isArray(childrenRes) ? childrenRes : (childrenRes as any)?.data || [];
      const rulePayload = (rulesRes as any)?.data || rulesRes;
      const baseRules = Array.isArray(rulePayload) ? rulePayload : rulePayload?.rules || [];
      const redlineRules = (rulePayload?.redlines || []).map((r: any) => ({
        id: r.id,
        name: r.rule,
        description: r.description,
        category: '红线',
        type: 'negative' as const,
        isRedLine: true,
        score: -Math.abs(r.penalty_points || 0),
        enabled: true,
        createdAt: '',
        updatedAt: '',
      }));
      setChildren(childList);
      setRules([...baseRules, ...redlineRules]);
    } catch (error) {
      console.error('加载失败:', error);
      setChildren([]);
      setRules([]);
      showToast('数据加载失败，暂时无法操作', 'error');
    } finally {
      setLoading(false);
    }
  }, []);

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

  const handleRuleSelect = (ruleId: number) => {
    setSelectedRule(ruleId);
    const rule = rules.find((r) => r.id === ruleId);
    if (rule) {
      setCustomAmount(Math.abs(rule.score));
    }
  };

  const applyVoiceCommand = async (text: string) => {
    try {
      setVoiceParsing(true);
      const result = await parseRewardVoice({ text });
      if (!result.ok || !result.command) {
        showToast(result.error || '智能体解析失败', 'error');
        return;
      }

      const command = result.command;
      const child = children.find((item) => item.id === command.childId)
        || children.find((item) => item.name === command.childName);
      if (!child) {
        showToast('智能体没有匹配到孩子，请重新说一遍', 'error');
        return;
      }

      const amount = Number(command.amount || 0);
      if (!amount) {
        showToast('智能体没有识别到积分数量，请重新说一遍', 'error');
        return;
      }

      setSelectedChild(child.id);
      setSelectedRule(null);
      setCustomType(command.type || 'score');
      setCustomAmount(amount);
      setCustomCategory(command.category || (amount < 0 ? '扣分' : '奖励'));
      setCustomDescription(command.description || text);
      showToast(`智能体已识别：${child.name} ${amount > 0 ? '+' : ''}${amount}${command.type === 'cash' ? '元' : command.type === 'item' ? '个物品' : '分'}`);
    } catch (error) {
      console.error(error);
      showToast((error as Error).message || '智能体解析失败', 'error');
    } finally {
      setVoiceParsing(false);
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
          applyVoiceCommand(text);
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
    const { child, rule, amount, type, category, description } = transactionPreview;

    const txData: any = {
      child_id: child.id,
      child_name: child.name,
      category: category || '其他',
      description: description || (rule?.name || '自定义操作'),
    };

    // 根据类型设置不同字段
    if (type === 'score') {
      txData.type = 'points';
      txData.direction = amount >= 0 ? '+' : '-';
      txData.points = Math.abs(amount);
    } else if (type === 'cash') {
      txData.type = 'cash';
      txData.direction = amount >= 0 ? '+' : '-';
      txData.cash_cny = Math.abs(amount);
    } else if (type === 'item') {
      txData.type = 'items';
      txData.direction = amount >= 0 ? '+' : '-';
      txData.items = description || (rule?.name || '物品');
    }

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

  const positiveRules = rules.filter((r) => r.enabled && r.type === 'positive');
  const negativeRules = rules.filter((r) => r.enabled && r.type === 'negative');

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
        <div className={`fixed top-4 right-4 z-50 px-6 py-3 rounded-lg shadow-lg text-white transition-all
          ${toast.type === 'success' ? 'bg-green-500' : 'bg-red-500'}`}>
          {toast.message}
        </div>
      )}

      <div>
        <h2 className="text-2xl font-bold text-gray-900">积分操作</h2>
        <p className="text-gray-500 mt-1">为孩子添加或扣减积分、现金或物品</p>
      </div>

      <Card className="p-5 border-[#4A90D9]/30">
        <div className="flex flex-col sm:flex-row sm:items-center gap-3 justify-between">
          <div>
            <h3 className="text-sm font-semibold text-gray-700">语音记录积分</h3>
            <p className="text-xs text-gray-500 mt-1">
              例如：给某个孩子加5分，因为主动完成任务；或扣10分，因为违反约定。
            </p>
            {voiceText && <p className="text-sm text-[#4A90D9] mt-2">浏览器识别：{voiceText}</p>}
            {voiceParsing && <p className="text-xs text-gray-500 mt-1">正在调用智能体纠错孩子姓名和积分...</p>}
          </div>
          <button
            type="button"
            onClick={startVoiceRecord}
            disabled={voiceListening || voiceParsing || children.length === 0}
            className="px-4 py-2 bg-[#4A90D9] text-white rounded-lg text-sm font-medium disabled:opacity-60"
          >
            {voiceListening ? '正在听...' : voiceParsing ? '智能体解析中...' : '🎤 语音记录'}
          </button>
        </div>
      </Card>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* 选择孩子 */}
        <Card className="p-5">
          <h3 className="text-sm font-semibold text-gray-700 mb-4">1. 选择孩子</h3>
          <div className="grid grid-cols-2 sm:grid-cols-3 gap-3">
            {children.map((child) => (
              <button
                key={child.id}
                onClick={() => setSelectedChild(child.id)}
                className={`p-4 rounded-xl border-2 text-center transition-all
                  ${selectedChild === child.id
                    ? 'border-[#4A90D9] bg-[#4A90D9]/5'
                    : 'border-gray-200 hover:border-gray-300'}`}
              >
                <div className={`w-12 h-12 rounded-full flex items-center justify-center text-white font-bold text-lg mx-auto mb-2
                  ${['bg-[#4A90D9]', 'bg-[#7ED321]', 'bg-[#F5A623]', 'bg-[#E74C3C]', 'bg-purple-500'][child.id % 5]}`}>
                  {child.name[0]}
                </div>
                <p className="font-medium">{child.name}</p>
                <p className="text-xs text-gray-500 mt-1">⭐{child.score} 💰{child.cash}</p>
              </button>
            ))}
          </div>
        </Card>

        {/* 选择规则 */}
        <Card className="p-5">
          <h3 className="text-sm font-semibold text-gray-700 mb-4">2. 选择规则</h3>

          {/* 正向规则 */}
          <div className="mb-4">
            <p className="text-xs font-medium text-green-600 mb-2">👍 正向行为</p>
            <div className="flex flex-wrap gap-2">
              {positiveRules.map((rule) => (
                <button
                  key={rule.id}
                  onClick={() => handleRuleSelect(rule.id)}
                  className={`px-3 py-2 rounded-lg text-sm border transition-all
                    ${selectedRule === rule.id
                      ? 'border-green-500 bg-green-50 text-green-700'
                      : 'border-gray-200 hover:border-green-300'}`}
                >
                  {rule.name} (+{rule.score})
                </button>
              ))}
            </div>
          </div>

          {/* 负向规则 */}
          <div>
            <p className="text-xs font-medium text-red-600 mb-2">👎 负向行为</p>
            <div className="flex flex-wrap gap-2">
              {negativeRules.map((rule) => (
                <button
                  key={rule.id}
                  onClick={() => handleRuleSelect(rule.id)}
                  className={`px-3 py-2 rounded-lg text-sm border transition-all
                    ${selectedRule === rule.id
                      ? 'border-red-500 bg-red-50 text-red-700'
                      : 'border-gray-200 hover:border-red-300'}`}
                >
                  {rule.name} ({rule.score})
                </button>
              ))}
            </div>
          </div>
        </Card>

        {/* 自定义操作 */}
        <Card className="p-5 lg:col-span-2">
          <h3 className="text-sm font-semibold text-gray-700 mb-4">3. 自定义操作</h3>
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">操作类型</label>
              <select
                value={customType}
                onChange={(e) => setCustomType(e.target.value as TransactionType)}
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
        </Card>
      </div>

      {/* 确认按钮 */}
      <div className="flex justify-center">
        <button
          onClick={handleOpenConfirm}
          className="px-8 py-3 bg-[#4A90D9] text-white rounded-xl text-lg font-semibold hover:bg-[#3A7BC8] transition-colors shadow-lg"
        >
          ✅ 确认操作
        </button>
      </div>

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
