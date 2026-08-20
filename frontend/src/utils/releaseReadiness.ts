export type ReleaseMaterialState = 'prepared' | 'missing' | 'credential_configured' | 'verified';

export type ReleaseMaterial = {
  id: string;
  group: '账号与主体' | '合规材料' | '构建与签名' | '真机与素材' | '审核与送审';
  name: string;
  requirement: string;
  defaultState: ReleaseMaterialState;
  sensitive?: boolean;
};

export const xiaotiancaiReleaseMaterials: ReleaseMaterial[] = [
  { id: 'developer_access', group: '账号与主体', name: '小天才开发者账号/商务准入', requirement: '账号具备目标应用和机型的发布权限', defaultState: 'missing', sensitive: true },
  { id: 'publisher_identity', group: '账号与主体', name: '发布主体信息', requirement: '核对“图灵软件”主体与营业执照、软著、协议完全一致', defaultState: 'missing' },
  { id: 'business_license', group: '账号与主体', name: '营业执照', requirement: '真实有效的主体证照扫描件', defaultState: 'missing', sensitive: true },
  { id: 'legal_representative_id', group: '账号与主体', name: '法定代表人证件', requirement: '按平台要求提供并限制可见范围', defaultState: 'missing', sensitive: true },
  { id: 'contact', group: '账号与主体', name: '联系人与客服信息', requirement: '姓名、手机、邮箱及必要的客服电话；从凭证管理安全引用', defaultState: 'missing', sensitive: true },
  { id: 'software_copyright', group: '合规材料', name: '软件著作权/版权证明', requirement: '权利人与发布主体、应用名称保持一致', defaultState: 'missing', sensitive: true },
  { id: 'disclaimer', group: '合规材料', name: '首次提交免责函', requirement: '法务确认并按平台要求盖章或签字', defaultState: 'missing', sensitive: true },
  { id: 'privacy_policy', group: '合规材料', name: '隐私政策 HTTPS 地址', requirement: '最终版可公开访问，含儿童信息和监护人同意说明', defaultState: 'missing' },
  { id: 'user_agreement', group: '合规材料', name: '用户协议 HTTPS 地址', requirement: '最终版可公开访问且主体信息准确', defaultState: 'missing' },
  { id: 'filing', group: '合规材料', name: '应用备案/核准信息', requirement: '按提交当天平台要求提供备案材料', defaultState: 'missing', sensitive: true },
  { id: 'data_compliance', group: '合规材料', name: '儿童数据合规问卷', requirement: '确认监护人同意、最小化收集和数据安全答案', defaultState: 'missing' },
  { id: 'android_project', group: '构建与签名', name: 'Android 工程与发布配置', requirement: '包名 net.impx.happylife.watch，版本 1.0.0 (100)', defaultState: 'prepared' },
  { id: 'signing_credential', group: '构建与签名', name: '发布签名凭证', requirement: 'keystore、别名和密码仅从凭证管理运行时引用', defaultState: 'missing', sensitive: true },
  { id: 'signed_apk', group: '构建与签名', name: '正式签名 APK', requirement: '记录 SHA-256、签名证书指纹和构建时间', defaultState: 'missing', sensitive: true },
  { id: 'app_credentials', group: '构建与签名', name: '平台 appId/appSecret', requirement: '仅在平台要求接入账号 SDK 或开放接口时需要；不得在此页录入原文', defaultState: 'missing', sensitive: true },
  { id: 'app_icon', group: '真机与素材', name: '应用图标', requirement: '148 × 148 PNG，直角，按平台规则校验', defaultState: 'missing' },
  { id: 'intro_images', group: '真机与素材', name: '应用介绍图', requirement: '320 × 360 PNG，共 3–5 张', defaultState: 'missing' },
  { id: 'target_devices', group: '真机与素材', name: '目标机型矩阵', requirement: '记录小天才型号、系统版本和屏幕尺寸', defaultState: 'missing' },
  { id: 'device_test', group: '真机与素材', name: '真机测试结果', requirement: '完成绑定、积分查询/申请、解绑、小屏适配和隐私回归', defaultState: 'missing' },
  { id: 'listing_copy', group: '审核与送审', name: '应用资料与审核说明', requirement: '应用简介、更新说明、审核/客服使用说明已准备', defaultState: 'prepared' },
  { id: 'test_account', group: '审核与送审', name: '审核家长测试账号', requirement: '从凭证管理安全引用；审核结束后撤销', defaultState: 'missing', sensitive: true },
  { id: 'child_auth_code', group: '审核与送审', name: '一次性儿童认证码', requirement: '送审时人工生成/输入，不持久化，不写入普通配置', defaultState: 'missing', sensitive: true },
  { id: 'performance_report', group: '审核与送审', name: '服务器性能说明/报告', requirement: '首次提交按平台要求提供真实性能数据', defaultState: 'missing' },
  { id: 'release_email', group: '审核与送审', name: '版本验收邮件包', requirement: '邮件模板已准备；发送前核对附件并归档 Message-ID', defaultState: 'prepared' },
];

export type ReleaseReadiness = {
  total: number;
  ready: number;
  missing: number;
  credentialConfigured: number;
  percent: number;
};

export function calculateReleaseReadiness(
  materials: ReleaseMaterial[],
  states: Partial<Record<string, ReleaseMaterialState>>,
): ReleaseReadiness {
  const resolved = materials.map((material) => states[material.id] ?? material.defaultState);
  const ready = resolved.filter((state) => state === 'prepared' || state === 'verified').length;
  const credentialConfigured = resolved.filter((state) => state === 'credential_configured').length;
  const missing = resolved.length - ready;

  return {
    total: resolved.length,
    ready,
    missing,
    credentialConfigured,
    percent: resolved.length === 0 ? 100 : Math.round((ready / resolved.length) * 100),
  };
}
