import { Card } from '../components/Card';
import { Modal } from '../components/Modal';
import type { Rule } from '../types';
import { useState, useEffect, useCallback } from 'react';
import { getRules, createRule, updateRule, deleteRule } from '../services';

interface RuleForm {
  name: string;
  description: string;
  category: string;
  type: 'positive' | 'negative';
  isRedLine: boolean;
  score: number;
  enabled: boolean;
}

export default function Rules() {
  const [rules, setRules] = useState<Rule[]>([]);
  const [loading, setLoading] = useState(true);
  const [showModal, setShowModal] = useState(false);
  const [editingRule, setEditingRule] = useState<Rule | null>(null);
  const [showDeleteConfirm, setShowDeleteConfirm] = useState(false);
  const [ruleToDelete, setRuleToDelete] = useState<number | null>(null);
  const [filterCategory, setFilterCategory] = useState('');
  const [filterType, setFilterType] = useState('');
  const [toast, setToast] = useState<{ show: boolean; message: string; type: 'success' | 'error' }>({ show: false, message: '', type: 'success' });

  const [formData, setFormData] = useState<RuleForm>({
    name: '', description: '', category: '', type: 'positive', isRedLine: false, score: 0, enabled: true,
  });

  const showToast = (message: string, type: 'success' | 'error' = 'success') => {
    setToast({ show: true, message, type });
    setTimeout(() => setToast({ show: false, message: '', type: 'success' }), 3000);
  };

  const loadRules = useCallback(async () => {
    try {
      setLoading(true);
      const res = await getRules() as any;
      const data = Array.isArray(res) ? res : res?.rules || [];
      const redlines = (res && !Array.isArray(res)) ? res?.redlines || [] : [];
      // 合并规则和红线为统一的 rules 列表用于展示
      const merged = [...data];
      for (const r of redlines) {
        merged.push({
          id: r.id,
          name: r.rule,
          description: r.description,
          category: '红线',
          type: 'negative' as const,
          isRedLine: true,
          score: -r.penalty_points,
          enabled: true,
          createdAt: '',
          updatedAt: '',
        });
      }
      setRules(merged);
    } catch (error) {
      console.error('加载失败:', error);
      setRules([]);
      showToast('规则加载失败', 'error');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    loadRules();
  }, [loadRules]);

  const openCreateModal = () => {
    setEditingRule(null);
    setFormData({ name: '', description: '', category: '', type: 'positive', isRedLine: false, score: 0, enabled: true });
    setShowModal(true);
  };

  const openEditModal = (rule: Rule) => {
    setEditingRule(rule);
    setFormData({ name: rule.name, description: rule.description, category: rule.category, type: rule.type, isRedLine: rule.isRedLine, score: rule.score, enabled: rule.enabled });
    setShowModal(true);
  };

  const handleSave = async () => {
    if (!formData.name.trim()) {
      showToast('请输入规则名称', 'error');
      return;
    }
    try {
      const data = { ...formData, createdAt: new Date().toISOString(), updatedAt: new Date().toISOString() };
      if (editingRule) {
        await updateRule(editingRule.id, { name: formData.name, category: formData.category, points: formData.score, cash_cny: 0, description: formData.description });
        showToast('更新成功');
      } else {
        await createRule({ name: formData.name, category: formData.category, points: formData.score, cash_cny: 0, description: formData.description });
        showToast('创建成功');
      }
      setShowModal(false);
      loadRules();
    } catch (error) {
      console.error('保存失败:', error);
      showToast(editingRule ? '更新失败' : '创建失败', 'error');
    }
  };

  const confirmDelete = (id: number) => {
    setRuleToDelete(id);
    setShowDeleteConfirm(true);
  };

  const handleDelete = async () => {
    if (ruleToDelete) {
      try {
        await deleteRule(ruleToDelete);
        showToast('删除成功');
        setShowDeleteConfirm(false);
        loadRules();
      } catch (error) {
        console.error('删除失败:', error);
        showToast('删除失败', 'error');
      }
    }
  };

  const filteredRules = rules.filter((r) => {
    if (filterCategory && r.category !== filterCategory) return false;
    if (filterType && r.type !== filterType) return false;
    return true;
  });

  const categories = Array.from(new Set(rules.map((r) => r.category)));
  const positiveRules = rules.filter((r) => r.type === 'positive');
  const negativeRules = rules.filter((r) => r.type === 'negative');
  const redLineRules = rules.filter((r) => r.isRedLine);

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
    <div className="space-y-4 sm:space-y-6">
      {/* Toast */}
      {toast.show && (
        <div className={`fixed left-3 right-3 top-3 z-50 rounded-lg px-4 py-3 text-sm text-white shadow-lg transition-all sm:left-auto sm:right-4 sm:top-4 sm:px-6
          ${toast.type === 'success' ? 'bg-green-500' : 'bg-red-500'}`}>
          {toast.message}
        </div>
      )}

      <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <h2 className="text-xl font-bold text-gray-900 sm:text-2xl">规则管理</h2>
          <p className="text-gray-500 mt-1">管理积分规则和红线规则</p>
        </div>
        <button onClick={openCreateModal} className="btn-primary flex w-full items-center justify-center gap-2 sm:w-auto">
          <span>➕</span> 新增规则
        </button>
      </div>

      {/* 筛选 */}
      <Card className="p-4">
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:flex">
          <select
            value={filterCategory}
            onChange={(e) => setFilterCategory(e.target.value)}
            className="w-full px-3 py-2 border border-gray-300 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-[#4A90D9] sm:w-auto"
          >
            <option value="">全部分类</option>
            {categories.map((cat) => (
              <option key={cat} value={cat}>{cat}</option>
            ))}
          </select>
          <select
            value={filterType}
            onChange={(e) => setFilterType(e.target.value)}
            className="w-full px-3 py-2 border border-gray-300 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-[#4A90D9] sm:w-auto"
          >
            <option value="">全部类型</option>
            <option value="positive">正向行为</option>
            <option value="negative">负向行为</option>
          </select>
        </div>
      </Card>

      {/* 红线规则 */}
      {redLineRules.length > 0 && (
        <Card className="border-red-200 p-4 sm:p-5">
          <h3 className="text-sm font-semibold text-red-600 mb-4 flex items-center gap-2">
            <span>🚨</span> 红线规则（不可违反）
          </h3>
          <div className="space-y-3">
            {redLineRules.map((rule) => (
              <div key={rule.id} className="flex flex-col gap-3 rounded-lg border border-red-200 bg-red-50 p-3 sm:flex-row sm:items-center sm:justify-between">
                <div className="min-w-0">
                  <span className="font-medium text-red-700">{rule.name}</span>
                  <span className="mt-1 block text-sm text-red-500 sm:ml-3 sm:mt-0 sm:inline">{rule.description}</span>
                </div>
                <div className="flex items-center gap-2">
                  <span className="text-sm font-bold text-red-600">{rule.score} 分</span>
                  <button onClick={() => openEditModal(rule)} className="text-[#4A90D9] text-sm hover:underline">编辑</button>
                  <button onClick={() => confirmDelete(rule.id)} className="text-[#E74C3C] text-sm hover:underline">删除</button>
                </div>
              </div>
            ))}
          </div>
        </Card>
      )}

      {/* 正向规则 */}
      <Card className="p-4 sm:p-5">
        <h3 className="text-sm font-semibold text-green-600 mb-4 flex items-center gap-2">
          <span>👍</span> 正向行为规则 ({positiveRules.length})
        </h3>
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3">
          {filteredRules.filter((r) => r.type === 'positive').map((rule) => (
            <div key={rule.id} className={`p-4 rounded-xl border transition-all ${rule.enabled ? 'border-green-200 bg-green-50/30' : 'border-gray-200 bg-gray-50 opacity-60'}`}>
              <div className="flex items-start justify-between mb-2">
                <span className="font-medium">{rule.name}</span>
                <span className="text-sm font-bold text-green-600">+{rule.score}</span>
              </div>
              <p className="text-sm text-gray-500 mb-2">{rule.description}</p>
              <div className="flex items-center justify-between">
                <span className="text-xs px-2 py-0.5 bg-gray-100 rounded">{rule.category}</span>
                <div className="flex items-center gap-2">
                  <span className={`text-xs px-2 py-0.5 rounded ${rule.enabled ? 'bg-green-100 text-green-700' : 'bg-gray-200 text-gray-500'}`}>
                    {rule.enabled ? '启用' : '禁用'}
                  </span>
                  <button onClick={() => openEditModal(rule)} className="text-xs text-[#4A90D9] hover:underline">编辑</button>
                  <button onClick={() => confirmDelete(rule.id)} className="text-xs text-[#E74C3C] hover:underline">删除</button>
                </div>
              </div>
            </div>
          ))}
        </div>
      </Card>

      {/* 负向规则 */}
      {negativeRules.length > 0 && (
        <Card className="p-4 sm:p-5">
          <h3 className="text-sm font-semibold text-red-600 mb-4 flex items-center gap-2">
            <span>👎</span> 负向行为规则 ({negativeRules.length})
          </h3>
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3">
            {filteredRules.filter((r) => r.type === 'negative' && !r.isRedLine).map((rule) => (
              <div key={rule.id} className={`p-4 rounded-xl border transition-all ${rule.enabled ? 'border-red-200 bg-red-50/30' : 'border-gray-200 bg-gray-50 opacity-60'}`}>
                <div className="flex items-start justify-between mb-2">
                  <span className="font-medium">{rule.name}</span>
                  <span className="text-sm font-bold text-red-600">{rule.score}</span>
                </div>
                <p className="text-sm text-gray-500 mb-2">{rule.description}</p>
                <div className="flex items-center justify-between">
                  <span className="text-xs px-2 py-0.5 bg-gray-100 rounded">{rule.category}</span>
                  <div className="flex items-center gap-2">
                    <span className={`text-xs px-2 py-0.5 rounded ${rule.enabled ? 'bg-red-100 text-red-700' : 'bg-gray-200 text-gray-500'}`}>
                      {rule.enabled ? '启用' : '禁用'}
                    </span>
                    <button onClick={() => openEditModal(rule)} className="text-xs text-[#4A90D9] hover:underline">编辑</button>
                    <button onClick={() => confirmDelete(rule.id)} className="text-xs text-[#E74C3C] hover:underline">删除</button>
                  </div>
                </div>
              </div>
            ))}
          </div>
        </Card>
      )}

      {/* 新增/编辑模态框 */}
      <Modal
        isOpen={showModal}
        onClose={() => setShowModal(false)}
        title={editingRule ? '编辑规则' : '新增规则'}
        footer={
          <>
            <button onClick={() => setShowModal(false)} className="px-4 py-2 text-gray-600 hover:bg-gray-100 rounded-lg">取消</button>
            <button onClick={handleSave} className="btn-primary">{editingRule ? '保存修改' : '确认创建'}</button>
          </>
        }
      >
        <div className="space-y-4">
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">规则名称 *</label>
            <input type="text" value={formData.name} onChange={(e) => setFormData({ ...formData, name: e.target.value })} placeholder="如：按时完成约定任务" className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-[#4A90D9]" />
          </div>
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">描述</label>
            <input type="text" value={formData.description} onChange={(e) => setFormData({ ...formData, description: e.target.value })} placeholder="规则描述" className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-[#4A90D9]" />
          </div>
          <div className="grid grid-cols-2 gap-4">
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">分类</label>
              <input type="text" value={formData.category} onChange={(e) => setFormData({ ...formData, category: e.target.value })} placeholder="如：学习、生活" className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-[#4A90D9]" />
            </div>
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">积分值 *</label>
              <input type="number" value={formData.score} onChange={(e) => setFormData({ ...formData, score: parseInt(e.target.value) || 0 })} className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-[#4A90D9]" />
            </div>
          </div>
          <div className="grid grid-cols-2 gap-4">
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">类型</label>
              <select value={formData.type} onChange={(e) => setFormData({ ...formData, type: e.target.value as 'positive' | 'negative' })} className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-[#4A90D9]">
                <option value="positive">正向行为</option>
                <option value="negative">负向行为</option>
              </select>
            </div>
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">状态</label>
              <select value={formData.enabled ? '1' : '0'} onChange={(e) => setFormData({ ...formData, enabled: e.target.value === '1' })} className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-[#4A90D9]">
                <option value="1">启用</option>
                <option value="0">禁用</option>
              </select>
            </div>
          </div>
          <div className="flex items-center gap-2">
            <input type="checkbox" id="redLine" checked={formData.isRedLine} onChange={(e) => setFormData({ ...formData, isRedLine: e.target.checked })} className="rounded" />
            <label htmlFor="redLine" className="text-sm text-gray-700">⚠️ 红线规则（不可违反）</label>
          </div>
        </div>
      </Modal>

      {/* 删除确认 */}
      <Modal
        isOpen={showDeleteConfirm}
        onClose={() => setShowDeleteConfirm(false)}
        title="确认删除"
        footer={
          <>
            <button onClick={() => setShowDeleteConfirm(false)} className="px-4 py-2 text-gray-600 hover:bg-gray-100 rounded-lg">取消</button>
            <button onClick={handleDelete} className="btn-danger">确认删除</button>
          </>
        }
      >
        <p className="text-gray-600">确定要删除这个规则吗？此操作不可撤销。</p>
      </Modal>
    </div>
  );
}
