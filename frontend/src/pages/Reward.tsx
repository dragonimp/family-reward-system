import { Card } from '../components/Card';
import { Modal } from '../components/Modal';
import type { Child, Rule, Transaction } from '../types';
import { useState, useEffect, useCallback } from 'react';
import { useNavigate } from 'react-router-dom';
import { getChildren, getRules, createTransaction } from '../services';
import { CHILDREN_DATA } from '../constants/children';

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
  const [showConfirm, setShowConfirm] = useState(false);
  const [transactionPreview, setTransactionPreview] = useState<any>(null);
  const [toast, setToast] = useState<{ show: boolean; message: string; type: 'success' | 'error' }>({ show: false, message: '', type: 'success' });

  const showToast = (message: string, type: 'success' | 'error' = 'success') => {
    setToast({ show: true, message, type });
    setTimeout(() => setToast({ show: false, message: '', type: 'success' }), 3000);
  };

  const loadData = useCallback(async () => {
    try {
      setLoading(true);
      const [childrenRes, rulesRes] = await Promise.all([getChildren(), getRules()]);
      setChildren((childrenRes as any).data || []);
      setRules((rulesRes as any).data || []);
    } catch (error) {
      console.error('加载失败:', error);
      setChildren(CHILDREN_DATA as Child[]);
      setRules([
        { id: 1, name: '考试满分', description: '任何科目考试满分', category: '学习', type: 'positive', isRedLine: false, score: 10, enabled: true } as Rule,
        { id: 2, name: '整理房间', description: '主动整理自己的房间', category: '生活', type: 'positive', isRedLine: false, score: 5, enabled: true } as Rule,
        { id: 3, name: '迟到', description: '上学迟到', category: '纪律', type: 'negative', isRedLine: false, score: -5, enabled: true } as Rule,
      ] as Rule[]);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    loadData();
  }, [loadData]);

  const handleRuleSelect = (ruleId: number) => {
    setSelectedRule(ruleId);
    const rule = rules.find((r) => r.id === ruleId);
    if (rule) {
      setSelectedChild(rule.id);
      setCustomAmount(Math.abs(rule.score));
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
