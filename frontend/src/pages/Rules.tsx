import { useCallback, useEffect, useMemo, useState } from 'react';
import { Card } from '../components/Card';
import { Modal } from '../components/Modal';
import { createRule, deleteRule, getRules, saveRuleTemplate, updateRule } from '../services';
import type { Rule } from '../types';

interface RuleForm {
  name: string;
  description: string;
  category: string;
  score: number;
  kind: 'reward' | 'redline';
}

interface RulePayload {
  publicRules: Rule[];
  personalRules: Rule[];
  templateRuleIds: number[];
  hasTemplate: boolean;
}

const emptyForm: RuleForm = { name: '', description: '', category: '', score: 1, kind: 'reward' };

export default function Rules() {
  const [payload, setPayload] = useState<RulePayload>({ publicRules: [], personalRules: [], templateRuleIds: [], hasTemplate: false });
  const [selectedIds, setSelectedIds] = useState<number[]>([]);
  const [loading, setLoading] = useState(true);
  const [savingTemplate, setSavingTemplate] = useState(false);
  const [showModal, setShowModal] = useState(false);
  const [editingRule, setEditingRule] = useState<Rule | null>(null);
  const [formData, setFormData] = useState<RuleForm>(emptyForm);
  const [deleteId, setDeleteId] = useState<number | null>(null);
  const [toast, setToast] = useState<{ message: string; type: 'success' | 'error' } | null>(null);

  const notify = (message: string, type: 'success' | 'error' = 'success') => {
    setToast({ message, type });
    window.setTimeout(() => setToast(null), 3000);
  };

  const loadRules = useCallback(async () => {
    try {
      setLoading(true);
      const result = await getRules() as unknown as RulePayload;
      const publicRules = result.publicRules || [];
      const next = {
        publicRules,
        personalRules: result.personalRules || [],
        templateRuleIds: result.templateRuleIds || [],
        hasTemplate: Boolean(result.hasTemplate),
      };
      setPayload(next);
      setSelectedIds(next.hasTemplate ? next.templateRuleIds : publicRules.map((rule) => rule.id));
    } catch (error) {
      console.error('规则加载失败:', error);
      notify('规则加载失败', 'error');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { void loadRules(); }, [loadRules]);

  const allRules = useMemo(() => {
    const available = [...payload.publicRules, ...payload.personalRules];
    const byId = new Map(available.map((rule) => [rule.id, rule]));
    const selected = selectedIds.map((id) => byId.get(id)).filter((rule): rule is Rule => Boolean(rule));
    const unselected = available.filter((rule) => !selectedIds.includes(rule.id));
    return [...selected, ...unselected];
  }, [payload, selectedIds]);
  const selectedSet = useMemo(() => new Set(selectedIds), [selectedIds]);
  const templateChanged = useMemo(() => {
    const stored = payload.hasTemplate ? payload.templateRuleIds : payload.publicRules.map((rule) => rule.id);
    return stored.length !== selectedIds.length || stored.some((id, index) => id !== selectedIds[index]);
  }, [payload, selectedIds]);

  const toggleRule = (ruleId: number) => {
    setSelectedIds((current) => current.includes(ruleId)
      ? current.filter((id) => id !== ruleId)
      : [...current, ruleId]);
  };

  const moveRule = (ruleId: number, offset: -1 | 1) => {
    setSelectedIds((current) => {
      const index = current.indexOf(ruleId);
      const target = index + offset;
      if (index < 0 || target < 0 || target >= current.length) return current;
      const next = [...current];
      [next[index], next[target]] = [next[target], next[index]];
      return next;
    });
  };

  const handleSaveTemplate = async () => {
    try {
      setSavingTemplate(true);
      await saveRuleTemplate(selectedIds);
      notify('个人规则模板已保存');
      await loadRules();
    } catch (error) {
      notify(error instanceof Error ? error.message : '模板保存失败', 'error');
    } finally {
      setSavingTemplate(false);
    }
  };

  const openCreate = () => {
    setEditingRule(null);
    setFormData(emptyForm);
    setShowModal(true);
  };

  const openEdit = (rule: Rule) => {
    setEditingRule(rule);
    setFormData({
      name: rule.name,
      description: rule.description,
      category: rule.category,
      score: Math.abs(rule.score) || 1,
      kind: rule.score < 0 ? 'redline' : 'reward',
    });
    setShowModal(true);
  };

  const handleSaveRule = async () => {
    if (!formData.name.trim()) return notify('请输入规则名称', 'error');
    if (formData.score <= 0) return notify('积分值必须大于 0', 'error');
    try {
      const data = {
        name: formData.name.trim(),
        category: formData.category.trim(),
        points: formData.kind === 'redline' ? -Math.abs(formData.score) : Math.abs(formData.score),
        ruleType: formData.kind,
        cash_cny: 0,
        description: formData.description.trim(),
      };
      if (editingRule) await updateRule(editingRule.id, data);
      else await createRule(data);
      setShowModal(false);
      notify(editingRule ? '个人规则已更新' : '个人规则已创建并加入模板');
      await loadRules();
    } catch (error) {
      notify(error instanceof Error ? error.message : '规则保存失败', 'error');
    }
  };

  const handleDelete = async () => {
    if (deleteId === null) return;
    try {
      await deleteRule(deleteId);
      setDeleteId(null);
      notify('个人规则已删除');
      await loadRules();
    } catch (error) {
      notify(error instanceof Error ? error.message : '删除失败', 'error');
    }
  };

  if (loading) {
    return <div className="flex justify-center py-20"><div className="h-10 w-10 animate-spin rounded-full border-4 border-[#4A90D9] border-t-transparent" /></div>;
  }

  return (
    <div className="space-y-5">
      {toast && <div className={`fixed right-4 top-4 z-50 rounded-md px-5 py-3 text-white shadow-lg ${toast.type === 'success' ? 'bg-green-600' : 'bg-red-600'}`}>{toast.message}</div>}

      <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <h2 className="text-2xl font-bold text-gray-900">我的规则模板</h2>
          <p className="mt-1 text-sm text-gray-500">孩子手表按下方顺序显示前 8 条正向规则</p>
        </div>
        <button type="button" onClick={openCreate} className="btn-primary self-start">新增个人规则</button>
      </div>

      <div className={`border-l-4 px-4 py-3 text-sm ${payload.hasTemplate ? 'border-green-500 bg-green-50 text-green-800' : 'border-blue-500 bg-blue-50 text-blue-800'}`}>
        {payload.hasTemplate ? `个人模板已启用，共选择 ${selectedIds.length} 条规则。` : '尚未创建个人模板，当前自动复用全部公共规则。保存选择或新增规则后将启用个人模板。'}
      </div>

      <Card className="p-5">
        <div className="mb-4 flex items-center justify-between gap-3">
          <div>
            <h3 className="font-semibold text-gray-900">模板规则</h3>
            <p className="mt-1 text-xs text-gray-500">从现有公共或个人的奖励、红线规则中选入模板；手表只显示排序前 8 条奖励规则</p>
          </div>
          <button type="button" onClick={() => void handleSaveTemplate()} disabled={!templateChanged || savingTemplate} className="btn-primary shrink-0 whitespace-nowrap disabled:cursor-not-allowed disabled:opacity-50">
            {savingTemplate ? '保存中...' : '保存模板'}
          </button>
        </div>
        <div className="grid grid-cols-1 gap-3 md:grid-cols-2 xl:grid-cols-3">
          {allRules.map((rule) => {
            const personal = !rule.isPublic;
            const selectedIndex = selectedIds.indexOf(rule.id);
            const redline = rule.score < 0;
            return (
              <div key={rule.id} className={`border p-4 ${selectedSet.has(rule.id) ? 'border-green-400 bg-green-50/60' : 'border-gray-200 bg-white'}`}>
                <div className="flex items-start gap-3">
                  <input type="checkbox" checked={selectedSet.has(rule.id)} onChange={() => toggleRule(rule.id)} className="mt-1 h-4 w-4 accent-green-600" aria-label={`选择${rule.name}`} />
                  <div className="min-w-0 flex-1">
                    <div className="flex items-start justify-between gap-2">
                      <span className="font-medium text-gray-900">{rule.name}</span>
                      <span className={`shrink-0 text-sm font-bold ${rule.score >= 0 ? 'text-green-700' : 'text-red-600'}`}>{rule.score >= 0 ? '+' : ''}{rule.score}</span>
                    </div>
                    <p className="mt-1 min-h-5 text-sm text-gray-500">{rule.description || '无描述'}</p>
                    <div className="mt-3 flex flex-wrap items-center justify-between gap-2">
                      <div className="flex flex-wrap gap-2 text-xs"><span className="bg-gray-100 px-2 py-1 text-gray-600">{rule.category || '未分类'}</span><span className={redline ? 'bg-red-100 px-2 py-1 text-red-700' : 'bg-green-100 px-2 py-1 text-green-700'}>{redline ? '红线' : '奖励'}</span><span className={personal ? 'bg-blue-100 px-2 py-1 text-blue-700' : 'bg-gray-100 px-2 py-1 text-gray-600'}>{personal ? '个人' : '公共'}</span></div>
                      <div className="flex items-center gap-1 text-xs">
                        {selectedIndex >= 0 && <><button type="button" title="上移" aria-label={`上移${rule.name}`} disabled={selectedIndex === 0} onClick={() => moveRule(rule.id, -1)} className="h-8 w-8 border border-gray-200 text-base text-gray-700 disabled:opacity-30">↑</button><button type="button" title="下移" aria-label={`下移${rule.name}`} disabled={selectedIndex === selectedIds.length - 1} onClick={() => moveRule(rule.id, 1)} className="h-8 w-8 border border-gray-200 text-base text-gray-700 disabled:opacity-30">↓</button></>}
                        {personal && <><button type="button" onClick={() => openEdit(rule)} className="px-2 text-blue-700">编辑</button><button type="button" onClick={() => setDeleteId(rule.id)} className="px-2 text-red-600">删除</button></>}
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            );
          })}
        </div>
      </Card>

      <Modal isOpen={showModal} onClose={() => setShowModal(false)} title={editingRule ? '编辑个人规则' : '新增个人规则'} footer={<><button type="button" onClick={() => setShowModal(false)} className="px-4 py-2 text-gray-600">取消</button><button type="button" onClick={() => void handleSaveRule()} className="btn-primary">保存</button></>}>
        <div className="space-y-4">
          <label className="block text-sm font-medium text-gray-700">规则名称<input value={formData.name} onChange={(event) => setFormData({ ...formData, name: event.target.value })} className="mt-1 w-full rounded-md border border-gray-300 px-3 py-2" /></label>
          <label className="block text-sm font-medium text-gray-700">描述<input value={formData.description} onChange={(event) => setFormData({ ...formData, description: event.target.value })} className="mt-1 w-full rounded-md border border-gray-300 px-3 py-2" /></label>
          <fieldset><legend className="mb-2 text-sm font-medium text-gray-700">规则类型</legend><div className="grid grid-cols-2 gap-2"><button type="button" onClick={() => setFormData({ ...formData, kind: 'reward' })} className={`border px-3 py-2 text-sm font-medium ${formData.kind === 'reward' ? 'border-green-600 bg-green-50 text-green-700' : 'border-gray-300 text-gray-600'}`}>奖励规则</button><button type="button" onClick={() => setFormData({ ...formData, kind: 'redline' })} className={`border px-3 py-2 text-sm font-medium ${formData.kind === 'redline' ? 'border-red-600 bg-red-50 text-red-700' : 'border-gray-300 text-gray-600'}`}>红线规则</button></div></fieldset>
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2"><label className="block text-sm font-medium text-gray-700">分类<input value={formData.category} onChange={(event) => setFormData({ ...formData, category: event.target.value })} className="mt-1 w-full rounded-md border border-gray-300 px-3 py-2" /></label><label className="block text-sm font-medium text-gray-700">积分值<input type="number" min="1" value={formData.score} onChange={(event) => setFormData({ ...formData, score: Number(event.target.value) })} className="mt-1 w-full rounded-md border border-gray-300 px-3 py-2" /><span className="mt-1 block text-xs font-normal text-gray-500">{formData.kind === 'redline' ? '保存后自动按减分处理' : '保存后按加分处理'}</span></label></div>
        </div>
      </Modal>

      <Modal isOpen={deleteId !== null} onClose={() => setDeleteId(null)} title="删除个人规则" footer={<><button type="button" onClick={() => setDeleteId(null)} className="px-4 py-2 text-gray-600">取消</button><button type="button" onClick={() => void handleDelete()} className="btn-danger">删除</button></>}><p className="text-gray-600">删除后，该规则会同时从个人模板中移除。</p></Modal>
    </div>
  );
}
