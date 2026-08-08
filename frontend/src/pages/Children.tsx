import { Card, StatCard } from '../components/Card';
import { Modal } from '../components/Modal';
import type { Child, Transaction, WatchDeviceBinding } from '../types';
import { useState, useEffect, useCallback } from 'react';
import { useNavigate } from 'react-router-dom';
import {
  getChildren,
  createChild,
  updateChild,
  deleteChild,
  getTransactions,
  createTransaction,
  generateChildAuthCode,
  getChildWatchDevices,
  revokeChildWatchDevice,
  generateWatchDeviceUnbindCode,
} from '../services';
import { useAuth } from '../contexts/AuthContext';
import { useFamilyGroup } from '../contexts/FamilyGroupContext';

interface ChildForm {
  name: string;
  score: number;
  cash: number;
  items: number;
}

export default function Children() {
  const navigate = useNavigate();
  const { userId } = useAuth();
  const { selectedGroupId, selectedGroup, loading: familyGroupsLoading, error: familyGroupsError } = useFamilyGroup();
  const [children, setChildren] = useState<Child[]>([]);
  const [loading, setLoading] = useState(true);
  const [showModal, setShowModal] = useState(false);
  const [editingChild, setEditingChild] = useState<Child | null>(null);
  const [formData, setFormData] = useState<ChildForm>({ name: '', score: 0, cash: 0, items: 0 });
  const [showDeleteConfirm, setShowDeleteConfirm] = useState(false);
  const [childToDelete, setChildToDelete] = useState<number | null>(null);
  const [deviceChild, setDeviceChild] = useState<Child | null>(null);
  const [authCode, setAuthCode] = useState<{ code: string; expiresAt: string } | null>(null);
  const [devices, setDevices] = useState<WatchDeviceBinding[]>([]);
  const [unbindCode, setUnbindCode] = useState<{ code: string; deviceId: number; expiresAt: string } | null>(null);
  const [deviceLoading, setDeviceLoading] = useState(false);
  const [toast, setToast] = useState<{ show: boolean; message: string; type: 'success' | 'error' }>({ show: false, message: '', type: 'success' });

  const showToast = (message: string, type: 'success' | 'error' = 'success') => {
    setToast({ show: true, message, type });
    setTimeout(() => setToast({ show: false, message: '', type: 'success' }), 3000);
  };

  const loadChildren = useCallback(async (silent = false) => {
    if (!selectedGroupId) {
      setChildren([]);
      setLoading(false);
      return;
    }
    try {
      if (!silent) setLoading(true);
      const res = await getChildren({ familyGroupId: selectedGroupId, userId: userId || undefined });
      setChildren(Array.isArray(res) ? res : res?.data || []);
    } catch (error) {
      console.error('加载失败:', error);
      setChildren([]);
      showToast('孩子列表加载失败', 'error');
    } finally {
      setLoading(false);
    }
  }, [selectedGroupId, userId]);

  useEffect(() => {
    loadChildren();
  }, [loadChildren]);

  useEffect(() => {
    const interval = window.setInterval(() => {
      loadChildren(true);
    }, 10000);
    const handleVisibilityChange = () => {
      if (!document.hidden) loadChildren(true);
    };
    document.addEventListener('visibilitychange', handleVisibilityChange);
    return () => {
      window.clearInterval(interval);
      document.removeEventListener('visibilitychange', handleVisibilityChange);
    };
  }, [loadChildren]);

  const openCreateModal = () => {
    setEditingChild(null);
    setFormData({ name: '', score: 0, cash: 0, items: 0 });
    setShowModal(true);
  };

  const openEditModal = (child: Child) => {
    setEditingChild(child);
    setFormData({ name: child.name, score: child.score ?? 0, cash: child.cash ?? 0, items: child.items ?? 0 });
    setShowModal(true);
  };

  const handleSave = async () => {
    if (!formData.name.trim()) {
      showToast('请输入孩子姓名', 'error');
      return;
    }
    try {
      if (editingChild) {
        await updateChild(editingChild.id, { ...formData, familyGroupId: selectedGroupId ?? undefined, id: editingChild.id, createdAt: editingChild.createdAt, updatedAt: new Date().toISOString() });
        showToast('更新成功');
      } else {
        await createChild({
          ...formData,
          familyGroupId: selectedGroupId ?? undefined,
          userId: userId || undefined,
          createdAt: new Date().toISOString(),
          updatedAt: new Date().toISOString(),
        } as any);
        showToast('创建成功');
      }
      setShowModal(false);
      loadChildren();
    } catch (error) {
      console.error('保存失败:', error);
      showToast(editingChild ? '更新失败' : '创建失败', 'error');
    }
  };

  const confirmDelete = (id: number) => {
    setChildToDelete(id);
    setShowDeleteConfirm(true);
  };

  const handleDelete = async () => {
    if (childToDelete) {
      try {
        await deleteChild(childToDelete, { familyGroupId: selectedGroupId ?? undefined });
        showToast('删除成功');
        setShowDeleteConfirm(false);
        loadChildren();
      } catch (error) {
        console.error('删除失败:', error);
        showToast('删除失败', 'error');
      }
    }
  };

  const openDeviceModal = async (child: Child) => {
    setDeviceChild(child);
    setAuthCode(null);
    setUnbindCode(null);
    setDevices([]);
    setDeviceLoading(true);
    try {
      const result = await getChildWatchDevices(child.id, { familyGroupId: selectedGroupId ?? undefined });
      setDevices(result.devices || []);
    } catch (error) {
      console.error('设备加载失败:', error);
      showToast('设备列表加载失败', 'error');
    } finally {
      setDeviceLoading(false);
    }
  };

  const handleGenerateAuthCode = async () => {
    if (!deviceChild) return;
    setDeviceLoading(true);
    try {
      const result = await generateChildAuthCode(deviceChild.id, {
        familyGroupId: selectedGroupId ?? undefined,
        expiresInMinutes: 24 * 60,
      });
      setAuthCode({ code: result.code, expiresAt: result.expiresAt });
      showToast('认证码已生成');
    } catch (error) {
      console.error('认证码生成失败:', error);
      showToast('认证码生成失败', 'error');
    } finally {
      setDeviceLoading(false);
    }
  };

  const handleRevokeDevice = async (deviceId: number) => {
    if (!deviceChild) return;
    setDeviceLoading(true);
    try {
      await revokeChildWatchDevice(deviceChild.id, deviceId, { familyGroupId: selectedGroupId ?? undefined });
      const result = await getChildWatchDevices(deviceChild.id, { familyGroupId: selectedGroupId ?? undefined });
      setDevices(result.devices || []);
      showToast('设备已解绑');
    } catch (error) {
      console.error('设备解绑失败:', error);
      showToast('设备解绑失败', 'error');
    } finally {
      setDeviceLoading(false);
    }
  };

  const handleGenerateUnbindCode = async (deviceId: number) => {
    if (!deviceChild) return;
    setDeviceLoading(true);
    try {
      const result = await generateWatchDeviceUnbindCode(deviceChild.id, deviceId, {
        familyGroupId: selectedGroupId ?? undefined,
        expiresInMinutes: 10,
      });
      setUnbindCode({ code: result.code, deviceId: result.deviceId, expiresAt: result.expiresAt });
      showToast('解绑认证码已生成');
    } catch (error) {
      console.error('解绑认证码生成失败:', error);
      showToast('解绑认证码生成失败', 'error');
    } finally {
      setDeviceLoading(false);
    }
  };

  if (loading || familyGroupsLoading) {
    return (
      <div className="flex items-center justify-center py-20">
        <div className="text-center">
          <div className="inline-block animate-spin rounded-full h-10 w-10 border-4 border-[#4A90D9] border-t-transparent"></div>
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

      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-2xl font-bold text-gray-900">孩子管理</h2>
          <p className="text-sm text-gray-500 mt-1">
            当前家庭组：{selectedGroup?.name || '未选择'}
            {familyGroupsError ? `，${familyGroupsError}` : ''}
          </p>
        </div>
        <button onClick={openCreateModal} className="btn-primary flex items-center gap-2">
          <span>➕</span> 新增孩子
        </button>
      </div>

      {/* 表格 */}
      <Card>
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-gray-200 bg-gray-50/50">
                <th className="text-left py-4 px-4 text-gray-500 font-medium">姓名</th>
                <th className="text-center py-4 px-4 text-gray-500 font-medium">当前积分</th>
                <th className="text-center py-4 px-4 text-gray-500 font-medium">现金余额</th>
                <th className="text-center py-4 px-4 text-gray-500 font-medium">物品数</th>
                <th className="text-center py-4 px-4 text-gray-500 font-medium">操作</th>
              </tr>
            </thead>
            <tbody>
              {children.map((child, i) => (
                <tr key={child.id} className={`border-b border-gray-100 hover:bg-gray-50/50 ${i % 2 === 0 ? '' : 'bg-gray-50/30'}`}>
                  <td className="py-4 px-4">
                    <div className="flex items-center gap-3">
                      <div className={`w-10 h-10 rounded-full flex items-center justify-center text-white font-bold text-sm
                        ${['bg-[#4A90D9]', 'bg-[#7ED321]', 'bg-[#F5A623]', 'bg-[#E74C3C]', 'bg-purple-500'][i % 5]}`}>
                        {child.name[0]}
                      </div>
                      <span className="font-medium">{child.name}</span>
                    </div>
                  </td>
                  <td className="py-4 px-4 text-center">
                    <span className="inline-flex items-center gap-1 px-3 py-1 rounded-full text-sm font-medium bg-blue-100 text-blue-700">
                      ⭐ {child.score}
                    </span>
                  </td>
                  <td className="py-4 px-4 text-center">
                    <span className="inline-flex items-center gap-1 px-3 py-1 rounded-full text-sm font-medium bg-green-100 text-green-700">
                      💰 ¥{child.cash}
                    </span>
                  </td>
                  <td className="py-4 px-4 text-center">
                    <span className="inline-flex items-center gap-1 px-3 py-1 rounded-full text-sm font-medium bg-orange-100 text-orange-700">
                      🎁 {child.items}
                    </span>
                  </td>
                  <td className="py-4 px-4 text-center">
                    <div className="flex items-center justify-center gap-2">
                      <button onClick={() => openEditModal(child)} className="text-[#4A90D9] hover:text-[#3A7BC8] text-sm font-medium">
                        编辑
                      </button>
                      <button onClick={() => openDeviceModal(child)} className="text-[#16A085] hover:text-[#0E7D67] text-sm font-medium">
                        手表
                      </button>
                      <button onClick={() => confirmDelete(child.id)} className="text-[#E74C3C] hover:text-red-700 text-sm font-medium">
                        删除
                      </button>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
          {children.length === 0 && (
            <div className="text-center py-12 text-gray-400">
              <p className="text-4xl mb-3">👶</p>
              <p>暂无孩子数据</p>
            </div>
          )}
        </div>
      </Card>

      {/* 新增/编辑模态框 */}
      <Modal
        isOpen={showModal}
        onClose={() => setShowModal(false)}
        title={editingChild ? '编辑孩子' : '新增孩子'}
        footer={
          <>
            <button onClick={() => setShowModal(false)} className="px-4 py-2 text-gray-600 hover:bg-gray-100 rounded-lg transition-colors">
              取消
            </button>
            <button onClick={handleSave} className="btn-primary">
              {editingChild ? '保存修改' : '确认创建'}
            </button>
          </>
        }
      >
        <div className="space-y-4">
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">姓名 *</label>
            <input
              type="text"
              value={formData.name}
              onChange={(e) => setFormData({ ...formData, name: e.target.value })}
              placeholder="请输入孩子姓名"
              className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-[#4A90D9] focus:border-transparent"
            />
          </div>
          <div className="grid grid-cols-3 gap-4">
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">初始积分</label>
              <input
                type="number"
                value={formData.score}
                onChange={(e) => setFormData({ ...formData, score: parseFloat(e.target.value) || 0 })}
                className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-[#4A90D9] focus:border-transparent"
              />
            </div>
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">初始现金</label>
              <input
                type="number"
                value={formData.cash}
                onChange={(e) => setFormData({ ...formData, cash: parseInt(e.target.value) || 0 })}
                className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-[#4A90D9] focus:border-transparent"
              />
            </div>
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">初始物品</label>
              <input
                type="number"
                value={formData.items}
                onChange={(e) => setFormData({ ...formData, items: parseInt(e.target.value) || 0 })}
                className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-[#4A90D9] focus:border-transparent"
              />
            </div>
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
            <button onClick={() => setShowDeleteConfirm(false)} className="px-4 py-2 text-gray-600 hover:bg-gray-100 rounded-lg">
              取消
            </button>
            <button onClick={handleDelete} className="btn-danger">
              确认删除
            </button>
          </>
        }
      >
        <p className="text-gray-600">确定要删除这个孩子吗？此操作不可撤销。</p>
      </Modal>

      <Modal
        isOpen={!!deviceChild}
        onClose={() => setDeviceChild(null)}
        title={deviceChild ? `${deviceChild.name}的手表绑定` : '手表绑定'}
        footer={
          <>
            <button onClick={() => setDeviceChild(null)} className="px-4 py-2 text-gray-600 hover:bg-gray-100 rounded-lg">
              关闭
            </button>
            <button onClick={handleGenerateAuthCode} disabled={deviceLoading} className="btn-primary">
              生成认证码
            </button>
          </>
        }
      >
        <div className="space-y-4">
          {authCode && (
            <div className="rounded-lg border border-green-200 bg-green-50 p-4 text-center">
              <div className="text-sm text-green-700">儿童认证码</div>
              <div className="mt-2 text-3xl font-black tracking-[0.25em] text-green-900">{authCode.code}</div>
              <div className="mt-2 text-xs text-green-700">
                有效期至 {new Date(authCode.expiresAt).toLocaleString('zh-CN', { hour12: false })}，使用后立即失效
              </div>
            </div>
          )}

          {unbindCode && (
            <div className="rounded-lg border border-amber-200 bg-amber-50 p-4 text-center">
              <div className="text-sm text-amber-700">设备 #{unbindCode.deviceId} 解绑认证码</div>
              <div className="mt-2 text-3xl font-black tracking-[0.25em] text-amber-900">{unbindCode.code}</div>
              <div className="mt-2 text-xs text-amber-700">
                请在对应手表端输入；有效期至 {new Date(unbindCode.expiresAt).toLocaleString('zh-CN', { hour12: false })}，使用后立即失效
              </div>
            </div>
          )}

          <div>
            <div className="mb-2 text-sm font-medium text-gray-700">已绑定设备</div>
            {deviceLoading ? (
              <div className="py-6 text-center text-gray-400">加载中...</div>
            ) : devices.length === 0 ? (
              <div className="rounded-lg border border-gray-200 py-6 text-center text-sm text-gray-400">暂无绑定设备</div>
            ) : (
              <div className="space-y-2">
                {devices.map((device) => (
                  <div key={device.id} className="flex items-center justify-between gap-3 rounded-lg border border-gray-200 p-3">
                    <div className="min-w-0">
                      <div className="truncate text-sm font-medium text-gray-900">{device.deviceName || '手表设备'}</div>
                      <div className="mt-1 text-xs text-gray-500">
                        最近使用 {new Date(device.lastSeenAt).toLocaleString('zh-CN', { hour12: false })}
                        {device.revokedAt ? ' · 已解绑' : ''}
                      </div>
                    </div>
                    {!device.revokedAt && (
                      <div className="flex shrink-0 flex-col items-end gap-1">
                        <button onClick={() => handleGenerateUnbindCode(device.id)} className="text-sm font-medium text-amber-700 hover:text-amber-900">
                          生成解绑码
                        </button>
                        <button onClick={() => handleRevokeDevice(device.id)} className="text-xs font-medium text-[#E74C3C] hover:text-red-700">
                          家长直接解绑
                        </button>
                      </div>
                    )}
                  </div>
                ))}
              </div>
            )}
          </div>
        </div>
      </Modal>
    </div>
  );
}
