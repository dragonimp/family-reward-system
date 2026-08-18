import { Card } from '../components/Card';
import { Modal } from '../components/Modal';
import type { Child, ChildFriend, ChildFriendNotification, HouseholdMember, HouseholdRole, WatchDeviceBinding } from '../types';
import { useState, useEffect, useCallback } from 'react';
import {
  getChildren,
  createChild,
  updateChild,
  deleteChild,
  createHouseholdMember,
  deleteHouseholdMember,
  generateChildAuthCode,
  getChildFriendNotifications,
  getChildFriends,
  getChildWatchDevices,
  getHouseholdMembers,
  markChildFriendNotificationRead,
  revokeChildWatchDevice,
  updateHouseholdMember,
  generateWatchDeviceUnbindCode,
} from '../services';

interface ChildForm {
  name: string;
  score: number;
  cash: number;
  items: number;
}

interface HouseholdMemberForm {
  displayName: string;
  role: HouseholdRole;
  note: string;
}

const householdRoleOptions: Array<{ value: HouseholdRole; label: string }> = [
  { value: 'father', label: '爸爸' },
  { value: 'mother', label: '妈妈' },
  { value: 'grandfather', label: '爷爷' },
  { value: 'grandmother', label: '奶奶' },
  { value: 'maternal_grandfather', label: '外公' },
  { value: 'maternal_grandmother', label: '外婆' },
  { value: 'guardian', label: '监护人' },
  { value: 'other', label: '其他' },
];

const householdRoleLabel = (role: HouseholdRole) =>
  householdRoleOptions.find((item) => item.value === role)?.label || '其他';

export default function Children() {
  const [activeSection, setActiveSection] = useState<'children' | 'members'>('children');
  const [children, setChildren] = useState<Child[]>([]);
  const [householdMembers, setHouseholdMembers] = useState<HouseholdMember[]>([]);
  const [membersLoading, setMembersLoading] = useState(true);
  const [showMemberModal, setShowMemberModal] = useState(false);
  const [editingMember, setEditingMember] = useState<HouseholdMember | null>(null);
  const [memberToDelete, setMemberToDelete] = useState<HouseholdMember | null>(null);
  const [memberForm, setMemberForm] = useState<HouseholdMemberForm>({ displayName: '', role: 'guardian', note: '' });
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
  const [friendChild, setFriendChild] = useState<Child | null>(null);
  const [friends, setFriends] = useState<ChildFriend[]>([]);
  const [friendLeaderboard, setFriendLeaderboard] = useState<ChildFriend[]>([]);
  const [friendNotifications, setFriendNotifications] = useState<ChildFriendNotification[]>([]);
  const [friendsLoading, setFriendsLoading] = useState(false);
  const [toast, setToast] = useState<{ show: boolean; message: string; type: 'success' | 'error' }>({ show: false, message: '', type: 'success' });

  const showToast = (message: string, type: 'success' | 'error' = 'success') => {
    setToast({ show: true, message, type });
    setTimeout(() => setToast({ show: false, message: '', type: 'success' }), 3000);
  };

  const loadChildren = useCallback(async (silent = false) => {
    try {
      if (!silent) setLoading(true);
      const res = await getChildren({ ownedOnly: true });
      setChildren(Array.isArray(res) ? res : res?.data || []);
    } catch (error) {
      console.error('加载失败:', error);
      setChildren([]);
      showToast('孩子列表加载失败', 'error');
    } finally {
      setLoading(false);
    }
  }, []);

  const loadFriendNotifications = useCallback(async () => {
    try {
      const result = await getChildFriendNotifications({ unreadOnly: true });
      setFriendNotifications(result.notifications || []);
    } catch (error) {
      console.error('好友通知加载失败:', error);
      setFriendNotifications([]);
    }
  }, []);

  const loadHouseholdMembers = useCallback(async () => {
    try {
      setMembersLoading(true);
      const result = await getHouseholdMembers();
      setHouseholdMembers(Array.isArray(result) ? result : []);
    } catch (error) {
      console.error('家庭成员加载失败:', error);
      setHouseholdMembers([]);
      showToast('家庭成员加载失败', 'error');
    } finally {
      setMembersLoading(false);
    }
  }, []);

  useEffect(() => {
    loadChildren();
    loadFriendNotifications();
    loadHouseholdMembers();
  }, [loadChildren, loadFriendNotifications, loadHouseholdMembers]);

  useEffect(() => {
    const interval = window.setInterval(() => {
      loadChildren(true);
      loadFriendNotifications();
    }, 10000);
    const handleVisibilityChange = () => {
      if (!document.hidden) {
        loadChildren(true);
        loadFriendNotifications();
      }
    };
    document.addEventListener('visibilitychange', handleVisibilityChange);
    return () => {
      window.clearInterval(interval);
      document.removeEventListener('visibilitychange', handleVisibilityChange);
    };
  }, [loadChildren, loadFriendNotifications]);

  const openCreateModal = () => {
    setEditingChild(null);
    setFormData({ name: '', score: 0, cash: 0, items: 0 });
    setShowModal(true);
  };

  const openCreateMemberModal = () => {
    setEditingMember(null);
    setMemberForm({ displayName: '', role: 'guardian', note: '' });
    setShowMemberModal(true);
  };

  const openEditMemberModal = (member: HouseholdMember) => {
    setEditingMember(member);
    setMemberForm({ displayName: member.displayName, role: member.role, note: member.note || '' });
    setShowMemberModal(true);
  };

  const handleSaveMember = async () => {
    if (!memberForm.displayName.trim()) {
      showToast('请输入家庭成员姓名', 'error');
      return;
    }
    try {
      const payload = { ...memberForm, displayName: memberForm.displayName.trim(), note: memberForm.note.trim() };
      if (editingMember) {
        await updateHouseholdMember(editingMember.id, payload);
        showToast(editingMember.isCurrentUser ? '当前用户角色已更新' : '家庭成员已更新');
      } else {
        await createHouseholdMember(payload);
        showToast('家庭成员已新增');
      }
      setShowMemberModal(false);
      await loadHouseholdMembers();
    } catch (error) {
      console.error('家庭成员保存失败:', error);
      showToast('家庭成员保存失败', 'error');
    }
  };

  const handleDeleteMember = async () => {
    if (!memberToDelete) return;
    try {
      await deleteHouseholdMember(memberToDelete.id);
      setMemberToDelete(null);
      showToast('家庭成员已删除');
      await loadHouseholdMembers();
    } catch (error) {
      console.error('家庭成员删除失败:', error);
      showToast('家庭成员删除失败', 'error');
    }
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
        await updateChild(editingChild.id, { ...formData, id: editingChild.id, createdAt: editingChild.createdAt, updatedAt: new Date().toISOString() });
        showToast('更新成功');
      } else {
        await createChild({
          ...formData,
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
        await deleteChild(childToDelete);
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
      const result = await getChildWatchDevices(child.id);
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
      await revokeChildWatchDevice(deviceChild.id, deviceId);
      const result = await getChildWatchDevices(deviceChild.id);
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

  const openFriendsModal = async (child: Child) => {
    setFriendChild(child);
    setFriends([]);
    setFriendLeaderboard([]);
    setFriendsLoading(true);
    try {
      const result = await getChildFriends(child.id);
      setFriends(result.friends || []);
      setFriendLeaderboard(result.leaderboard || []);
    } catch (error) {
      console.error('好友列表加载失败:', error);
      showToast('好友列表加载失败', 'error');
    } finally {
      setFriendsLoading(false);
    }
  };

  const handleReadFriendNotification = async (id: number) => {
    try {
      await markChildFriendNotificationRead(id);
      setFriendNotifications((items) => items.filter((item) => item.id !== id));
    } catch (error) {
      console.error('好友通知标记失败:', error);
      showToast('好友通知处理失败', 'error');
    }
  };

  if (loading) {
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

      <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <h2 className="text-2xl font-bold text-gray-900">家庭管理</h2>
          <p className="text-sm text-gray-500 mt-1">
            管理当前家长账号下固定的孩子和其他家庭成员，不随圈子切换而改变
          </p>
        </div>
        <button
          onClick={activeSection === 'children' ? openCreateModal : openCreateMemberModal}
          className="btn-primary flex items-center gap-2"
        >
          <span>➕</span> {activeSection === 'children' ? '新增孩子' : '新增家庭成员'}
        </button>
      </div>

      <div role="tablist" aria-label="家庭成员类型" className="flex w-fit rounded-lg border border-gray-200 bg-white p-1">
        <button
          type="button"
          role="tab"
          aria-selected={activeSection === 'children'}
          onClick={() => setActiveSection('children')}
          className={`rounded-md px-4 py-2 text-sm font-medium ${activeSection === 'children' ? 'bg-[#4A90D9] text-white' : 'text-gray-600 hover:bg-gray-50'}`}
        >
          孩子成员
        </button>
        <button
          type="button"
          role="tab"
          aria-selected={activeSection === 'members'}
          onClick={() => setActiveSection('members')}
          className={`rounded-md px-4 py-2 text-sm font-medium ${activeSection === 'members' ? 'bg-[#4A90D9] text-white' : 'text-gray-600 hover:bg-gray-50'}`}
        >
          其他家庭成员
        </button>
      </div>

      {activeSection === 'children' && <>
      {friendNotifications.length > 0 && (
        <Card>
          <div className="flex flex-col gap-3">
            <div>
              <h3 className="text-base font-semibold text-gray-900">好友消息</h3>
              <p className="mt-1 text-sm text-gray-500">孩子通过手表添加好友后，家长会在这里收到消息。</p>
            </div>
            <div className="space-y-2">
              {friendNotifications.map((item) => (
                <div key={item.id} className="flex items-center justify-between gap-3 rounded-lg border border-blue-100 bg-blue-50 px-4 py-3">
                  <div className="min-w-0">
                    <div className="truncate text-sm font-medium text-blue-950">{item.message}</div>
                    <div className="mt-1 text-xs text-blue-700">
                      {new Date(item.createdAt).toLocaleString('zh-CN', { hour12: false })}
                    </div>
                  </div>
                  <button
                    onClick={() => handleReadFriendNotification(item.id)}
                    className="shrink-0 text-sm font-medium text-blue-700 hover:text-blue-900"
                  >
                    已读
                  </button>
                </div>
              ))}
            </div>
          </div>
        </Card>
      )}

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
                      <button onClick={() => openFriendsModal(child)} className="text-[#8E44AD] hover:text-[#6C3483] text-sm font-medium">
                        好友
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
      </>}

      {activeSection === 'members' && (
        <Card>
          {membersLoading ? (
            <div className="py-12 text-center text-sm text-gray-400">家庭成员加载中...</div>
          ) : householdMembers.length === 0 ? (
            <div className="py-12 text-center text-sm text-gray-400">暂无家庭成员</div>
          ) : (
            <div className="divide-y divide-gray-100">
              {householdMembers.map((member) => (
                <div key={member.id} className="flex flex-col gap-3 py-4 sm:flex-row sm:items-center sm:justify-between">
                  <div className="min-w-0">
                    <div className="flex flex-wrap items-center gap-2">
                      <span className="font-medium text-gray-900">{member.displayName}</span>
                      <span className="rounded-full bg-blue-100 px-2.5 py-1 text-xs font-medium text-blue-700">
                        {householdRoleLabel(member.role)}
                      </span>
                      {member.isCurrentUser && (
                        <span className="rounded-full bg-green-100 px-2.5 py-1 text-xs font-medium text-green-700">当前用户</span>
                      )}
                    </div>
                    <p className="mt-1 text-sm text-gray-500">{member.note || (member.isCurrentUser ? '可编辑姓名并定义当前用户的家庭角色' : '未填写备注')}</p>
                  </div>
                  <div className="flex shrink-0 items-center gap-3">
                    <button type="button" onClick={() => openEditMemberModal(member)} className="text-sm font-medium text-[#4A90D9] hover:text-[#3A7BC8]">编辑</button>
                    {!member.isCurrentUser && (
                      <button type="button" onClick={() => setMemberToDelete(member)} className="text-sm font-medium text-[#E74C3C] hover:text-red-700">删除</button>
                    )}
                  </div>
                </div>
              ))}
            </div>
          )}
        </Card>
      )}

      <Modal
        isOpen={showMemberModal}
        onClose={() => setShowMemberModal(false)}
        title={editingMember?.isCurrentUser ? '定义当前用户角色' : editingMember ? '编辑家庭成员' : '新增家庭成员'}
        footer={
          <>
            <button type="button" onClick={() => setShowMemberModal(false)} className="rounded-lg px-4 py-2 text-gray-600 hover:bg-gray-100">取消</button>
            <button type="button" onClick={handleSaveMember} className="btn-primary">保存</button>
          </>
        }
      >
        <div className="space-y-4">
          <label className="block text-sm font-medium text-gray-700">
            姓名 *
            <input
              type="text"
              maxLength={50}
              value={memberForm.displayName}
              onChange={(event) => setMemberForm({ ...memberForm, displayName: event.target.value })}
              placeholder="请输入家庭成员姓名"
              className="mt-1 w-full rounded-lg border border-gray-300 px-3 py-2 focus:outline-none focus:ring-2 focus:ring-[#4A90D9]"
            />
          </label>
          <label className="block text-sm font-medium text-gray-700">
            家庭角色 *
            <select
              value={memberForm.role}
              onChange={(event) => setMemberForm({ ...memberForm, role: event.target.value as HouseholdRole })}
              className="mt-1 w-full rounded-lg border border-gray-300 bg-white px-3 py-2 focus:outline-none focus:ring-2 focus:ring-[#4A90D9]"
            >
              {householdRoleOptions.map((option) => <option key={option.value} value={option.value}>{option.label}</option>)}
            </select>
          </label>
          <label className="block text-sm font-medium text-gray-700">
            备注
            <textarea
              rows={3}
              value={memberForm.note}
              onChange={(event) => setMemberForm({ ...memberForm, note: event.target.value })}
              placeholder="可填写称呼或说明"
              className="mt-1 w-full rounded-lg border border-gray-300 px-3 py-2 focus:outline-none focus:ring-2 focus:ring-[#4A90D9]"
            />
          </label>
        </div>
      </Modal>

      <Modal
        isOpen={Boolean(memberToDelete)}
        onClose={() => setMemberToDelete(null)}
        title="删除家庭成员"
        footer={
          <>
            <button type="button" onClick={() => setMemberToDelete(null)} className="rounded-lg px-4 py-2 text-gray-600 hover:bg-gray-100">取消</button>
            <button type="button" onClick={handleDeleteMember} className="btn-danger">确认删除</button>
          </>
        }
      >
        <p className="text-gray-600">确定要删除家庭成员「{memberToDelete?.displayName}」吗？</p>
      </Modal>

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

      <Modal
        isOpen={!!friendChild}
        onClose={() => setFriendChild(null)}
        title={friendChild ? `${friendChild.name}的手表好友` : '手表好友'}
        footer={
          <button onClick={() => setFriendChild(null)} className="btn-primary">
            关闭
          </button>
        }
      >
        <div className="space-y-5">
          <div>
            <div className="mb-2 text-sm font-medium text-gray-700">好友列表</div>
            {friendsLoading ? (
              <div className="py-6 text-center text-gray-400">加载中...</div>
            ) : friends.length === 0 ? (
              <div className="rounded-lg border border-gray-200 py-6 text-center text-sm text-gray-400">
                暂无好友，可在手表端用 8 位好友认证码添加
              </div>
            ) : (
              <div className="space-y-2">
                {friends.map((friend) => (
                  <div key={friend.profileKey} className="grid grid-cols-[1fr_auto] items-center gap-3 rounded-lg border border-gray-200 p-3">
                    <div className="min-w-0">
                      <div className="truncate text-sm font-medium text-gray-900">{friend.name}</div>
                      <div className="mt-1 text-xs text-gray-500">
                        现金 ¥{friend.cash} · 物品 {friend.items}
                      </div>
                    </div>
                    <div className="rounded-full bg-blue-100 px-3 py-1 text-sm font-semibold text-blue-700">
                      {friend.score} 分
                    </div>
                  </div>
                ))}
              </div>
            )}
          </div>

          <div>
            <div className="mb-2 text-sm font-medium text-gray-700">好友积分榜</div>
            {friendLeaderboard.length === 0 ? (
              <div className="rounded-lg border border-gray-200 py-6 text-center text-sm text-gray-400">暂无排行数据</div>
            ) : (
              <div className="divide-y divide-gray-100 rounded-lg border border-gray-200">
                {friendLeaderboard.map((item) => (
                  <div key={item.profileKey} className="grid grid-cols-[36px_1fr_auto] items-center gap-3 px-3 py-2">
                    <div className="text-center text-sm font-black text-gray-500">#{item.rank}</div>
                    <div className="min-w-0">
                      <div className="truncate text-sm font-medium text-gray-900">
                        {item.name}{item.isSelf ? '（自己）' : ''}
                      </div>
                    </div>
                    <div className="font-semibold text-blue-700">{item.score} 分</div>
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
