import { useMemo, useState } from 'react';
import {
  calculateReleaseReadiness,
  xiaotiancaiReleaseMaterials,
  type ReleaseMaterialState,
} from '../utils/releaseReadiness';

const storageKey = 'family-reward:xiaotiancai-release-readiness:v1';

const stateLabels: Record<ReleaseMaterialState, string> = {
  missing: '待补齐',
  credential_configured: '凭证管理已配置',
  prepared: '草案/工程已准备',
  verified: '真实材料已核验',
};

const stateStyles: Record<ReleaseMaterialState, string> = {
  missing: 'border-amber-200 bg-amber-50 text-amber-800',
  credential_configured: 'border-blue-200 bg-blue-50 text-blue-800',
  prepared: 'border-slate-200 bg-slate-50 text-slate-700',
  verified: 'border-emerald-200 bg-emerald-50 text-emerald-800',
};

function readSavedStates(): Record<string, ReleaseMaterialState> {
  try {
    const raw = window.localStorage.getItem(storageKey);
    return raw ? JSON.parse(raw) : {};
  } catch {
    return {};
  }
}

export default function WatchReleasePage() {
  const [states, setStates] = useState<Record<string, ReleaseMaterialState>>(readSavedStates);
  const readiness = useMemo(
    () => calculateReleaseReadiness(xiaotiancaiReleaseMaterials, states),
    [states],
  );
  const groups = Array.from(new Set(xiaotiancaiReleaseMaterials.map((material) => material.group)));

  const updateState = (id: string, state: ReleaseMaterialState) => {
    const next = { ...states, [id]: state };
    setStates(next);
    window.localStorage.setItem(storageKey, JSON.stringify(next));
  };

  return (
    <div className="space-y-5 pb-8">
      <header className="rounded-xl bg-gradient-to-r from-[#315C9B] to-[#4A90D9] p-5 text-white shadow-sm sm:p-6">
        <p className="text-sm text-blue-100">小天才应用市场 · REQ-053</p>
        <div className="mt-1 flex flex-col justify-between gap-4 sm:flex-row sm:items-end">
          <div>
            <h2 className="text-2xl font-bold">手表端上架准备</h2>
            <p className="mt-2 max-w-3xl text-sm leading-6 text-blue-50">
              家加分手表积分 · net.impx.happylife.watch · 1.0.0 (100)。此页只记录准备状态，
              不接收密码、验证码、证件号码或密钥原文。
            </p>
          </div>
          <div className="shrink-0 rounded-lg bg-white/15 px-4 py-3 text-right">
            <div className="text-3xl font-bold">{readiness.percent}%</div>
            <div className="text-xs text-blue-100">{readiness.ready}/{readiness.total} 项已核验或已准备</div>
          </div>
        </div>
      </header>

      <section className="grid grid-cols-1 gap-3 sm:grid-cols-3">
        <div className="rounded-lg border border-emerald-200 bg-emerald-50 p-4">
          <div className="text-2xl font-bold text-emerald-700">{readiness.ready}</div>
          <div className="text-sm text-emerald-800">已准备/已核验</div>
        </div>
        <div className="rounded-lg border border-amber-200 bg-amber-50 p-4">
          <div className="text-2xl font-bold text-amber-700">{readiness.missing}</div>
          <div className="text-sm text-amber-800">仍未完成（含仅配置凭证）</div>
        </div>
        <div className="rounded-lg border border-blue-200 bg-blue-50 p-4">
          <div className="text-2xl font-bold text-blue-700">{readiness.credentialConfigured}</div>
          <div className="text-sm text-blue-800">已在凭证管理配置，待验证</div>
        </div>
      </section>

      <aside className="rounded-lg border border-red-200 bg-red-50 p-4 text-sm leading-6 text-red-900">
        <strong>凭证安全边界：</strong>账号、联系人手机号/邮箱、签名密码、appSecret 和审核测试账号请到
        “用户中心 → 个人信息管理 → 凭证管理”维护。短信验证码和一次性儿童认证码只允许送审时人工输入，
        不会保存到本页或浏览器。本页“凭证管理已配置”不等于材料已验证。
      </aside>

      {groups.map((group) => (
        <section key={group} className="overflow-hidden rounded-xl border border-gray-200 bg-white shadow-sm">
          <div className="border-b border-gray-200 bg-gray-50 px-4 py-3 sm:px-5">
            <h3 className="font-semibold text-gray-900">{group}</h3>
          </div>
          <div className="divide-y divide-gray-100">
            {xiaotiancaiReleaseMaterials.filter((material) => material.group === group).map((material) => {
              const state = states[material.id] ?? material.defaultState;
              return (
                <div key={material.id} className="grid gap-3 p-4 sm:grid-cols-[minmax(0,1fr)_220px] sm:items-center sm:p-5">
                  <div className="min-w-0">
                    <div className="flex flex-wrap items-center gap-2">
                      <h4 className="font-medium text-gray-900">{material.name}</h4>
                      {material.sensitive && (
                        <span className="rounded-full bg-red-50 px-2 py-0.5 text-xs text-red-700">敏感材料</span>
                      )}
                    </div>
                    <p className="mt-1 text-sm leading-5 text-gray-500">{material.requirement}</p>
                  </div>
                  <label className="block">
                    <span className="sr-only">{material.name}状态</span>
                    <select
                      aria-label={`${material.name}状态`}
                      value={state}
                      onChange={(event) => updateState(material.id, event.target.value as ReleaseMaterialState)}
                      className={`w-full rounded-lg border px-3 py-2 text-sm font-medium ${stateStyles[state]}`}
                    >
                      <option value="missing">{stateLabels.missing}</option>
                      {material.sensitive && <option value="credential_configured">{stateLabels.credential_configured}</option>}
                      <option value="prepared">{stateLabels.prepared}</option>
                      <option value="verified">{stateLabels.verified}</option>
                    </select>
                  </label>
                </div>
              );
            })}
          </div>
        </section>
      ))}

      <footer className="rounded-lg border border-gray-200 bg-white p-4 text-sm leading-6 text-gray-600">
        <strong className="text-gray-900">完成判定：</strong>只有正式签名 APK、软著/备案、盖章免责函、主体证照、
        目标真机结果、截图和平台受理证据全部使用真实材料并核验后，才可送审或关闭“真实上架”事项。
      </footer>
    </div>
  );
}
