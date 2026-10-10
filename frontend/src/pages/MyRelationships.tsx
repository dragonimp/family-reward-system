import { Link } from 'react-router-dom';
import HouseholdGenealogyLinks from '../components/HouseholdGenealogyLinks';

export default function MyRelationships() {
  return <div className="mx-auto max-w-4xl space-y-5">
    <div><h2 className="text-2xl font-bold text-gray-900">我的关系</h2>
      <p className="mt-1 text-sm text-gray-600">这里管理真实的家庭成员与家族关系。群组是一起记录成长的虚拟小组，不代表亲属关系。</p></div>
    <div className="grid gap-4 sm:grid-cols-2">
      <Link to="/my/family-members" className="rounded-2xl border border-emerald-100 bg-white p-5 shadow-sm hover:border-emerald-400">
        <h3 className="font-semibold text-gray-900">👨‍👩‍👧 家庭成员</h3><p className="mt-2 text-sm text-gray-600">管理本人、家人与家庭角色，并明确关联族谱中的人物。</p>
      </Link>
      <Link to="/genealogy" className="rounded-2xl border border-emerald-100 bg-white p-5 shadow-sm hover:border-emerald-400">
        <h3 className="font-semibold text-gray-900">🌳 家族族谱</h3><p className="mt-2 text-sm text-gray-600">查找家族成员，维护真实亲属关系。</p>
      </Link>
      <Link to="/genealogy?invite=1" className="rounded-2xl border border-emerald-100 bg-white p-5 shadow-sm hover:border-emerald-400 sm:col-span-2">
        <h3 className="font-semibold text-gray-900">✉️ 邀请家人</h3><p className="mt-2 text-sm text-gray-600">在族谱中选择对应人物，生成专属邀请链接。对方确认后会绑定该人物。</p>
      </Link>
    </div>
    <HouseholdGenealogyLinks />
  </div>;
}
