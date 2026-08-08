import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { useAuth } from '../contexts/AuthContext';

export default function Identity() {
  const navigate = useNavigate();
  const { user, selectAppRole } = useAuth();
  const [busyRole, setBusyRole] = useState<'parent' | 'child' | null>(null);
  const [error, setError] = useState('');

  const displayName = user?.displayName || user?.username || '用户';

  const chooseRole = async (role: 'parent' | 'child') => {
    try {
      setBusyRole(role);
      setError('');
      await selectAppRole(role);
      if (role === 'child') {
        window.location.href = '/watch';
        return;
      }
      navigate('/dashboard', { replace: true });
    } catch (err) {
      setError(err instanceof Error ? err.message : '身份保存失败');
    } finally {
      setBusyRole(null);
    }
  };

  return (
    <div className="min-h-screen bg-[#F7F9FC] px-4 py-8">
      <div className="mx-auto max-w-3xl">
        <div className="mb-6">
          <h1 className="text-2xl font-bold text-gray-900">选择身份</h1>
          <p className="mt-2 text-sm text-gray-500">{displayName}，请选择这次使用家加分的身份。</p>
        </div>

        {error && (
          <div className="mb-4 rounded-lg border border-red-100 bg-red-50 px-4 py-3 text-sm text-red-700">
            {error}
          </div>
        )}

        <div className="grid grid-cols-1 gap-4 md:grid-cols-2">
          <button
            type="button"
            disabled={busyRole !== null}
            onClick={() => chooseRole('parent')}
            className="rounded-lg border border-gray-200 bg-white p-6 text-left shadow-sm transition-colors hover:border-[#4A90D9] disabled:opacity-60"
          >
            <div className="mb-4 flex h-12 w-12 items-center justify-center rounded-lg bg-[#4A90D9]/10 text-2xl">
              👤
            </div>
            <h2 className="text-lg font-semibold text-gray-900">家长</h2>
            <p className="mt-2 text-sm leading-6 text-gray-500">
              管理家庭组、孩子、积分、规则、统计和系统配置。
            </p>
            <span className="mt-5 inline-flex rounded-lg bg-[#4A90D9] px-4 py-2 text-sm font-medium text-white">
              {busyRole === 'parent' ? '保存中...' : '以家长身份进入'}
            </span>
          </button>

          <button
            type="button"
            disabled={busyRole !== null}
            onClick={() => chooseRole('child')}
            className="rounded-lg border border-gray-200 bg-white p-6 text-left shadow-sm transition-colors hover:border-green-500 disabled:opacity-60"
          >
            <div className="mb-4 flex h-12 w-12 items-center justify-center rounded-lg bg-green-50 text-2xl">
              ⭐
            </div>
            <h2 className="text-lg font-semibold text-gray-900">孩子</h2>
            <p className="mt-2 text-sm leading-6 text-gray-500">
              查看自己的积分，并提交积分领取申请。
            </p>
            <span className="mt-5 inline-flex rounded-lg bg-green-600 px-4 py-2 text-sm font-medium text-white">
              {busyRole === 'child' ? '保存中...' : '进入手表端'}
            </span>
          </button>
        </div>
      </div>
    </div>
  );
}
