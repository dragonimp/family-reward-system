import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

test('TASK-158 declares the controlled production deployment profile', async () => {
  const profile = JSON.parse(await readFile(
    new URL('../.agentfree/deployment-profile.json', import.meta.url),
    'utf8',
  ));

  assert.deepEqual(profile, {
    projectCode: 'family-reward',
    enabled: true,
    workingDirectory: '~/Projects/family-reward-system',
    executable: '/bin/bash',
    arguments: ['scripts/atlas-deploy-server.sh'],
    timeoutMinutes: 30,
    healthChecks: ['https://happylife.ai.impx.net/health'],
  });
});

test('REQ-028 offers an explicit family selector and scoped child view', async () => {
  const page = await readFile(new URL('./src/pages/FamilyGroups.tsx', import.meta.url), 'utf8');
  assert.match(page, /id="family-view-select"/);
  assert.match(page, /onChange=\{\(event\) => selectGroup\(Number\(event\.target\.value\)\)\}/);
  assert.match(page, /getFamilyGroupChildren\(selectedGroupId\)/);
});

test('REQ-030 exposes one watch menu with six icon destinations and voice fallback', async () => {
  const api = await readFile(new URL('../FamilyReward.Api/Program.cs', import.meta.url), 'utf8');
  const views = ['request', 'points-detail', 'friend-add', 'leaderboard', 'settings', 'device'];
  assert.equal((api.match(/id="menu-toggle"/g) || []).length, 1);
  for (const view of views) assert.match(api, new RegExp(`data-view="${view}"`));
  assert.match(api, /window\.SpeechRecognition \|\| window\.webkitSpeechRecognition/);
  assert.match(api, /当前手表不支持语音识别，请使用键盘输入/);
});

test('REQ-031 directly loads the public feedback widget with current user contact details', async () => {
  const [widget, layout, api] = await Promise.all([
    readFile(new URL('./src/components/PublicFeedbackWidget.tsx', import.meta.url), 'utf8'),
    readFile(new URL('./src/components/Layout.tsx', import.meta.url), 'utf8'),
    readFile(new URL('../FamilyReward.Api/Program.cs', import.meta.url), 'utf8'),
  ]);
  assert.match(widget, /https:\/\/auth\.ai\.xmkurt\.com\/feedback-widget\.js/);
  assert.match(widget, /window\.AgentDashFeedback =/);
  assert.match(widget, /email: user\.email \|\| ''/);
  assert.match(widget, /phone: user\.phoneNumber \|\| ''/);
  assert.match(layout, /<PublicFeedbackWidget \/>/);
  assert.match(api, /source_system"] = "family-reward-web"/);
  assert.match(api, /X-Atlas-User-Id/);
  assert.match(api, /\["path"\] = SanitizeFeedbackPath/);
  assert.match(api, /body\.String\("feedback_type", "suggestion"\)/);
  assert.match(api, /body\.String\("submitter_contact"\)/);
  assert.match(api, /body\.String\("source_url"\)/);
  assert.match(api, /feedback-\{Guid\.NewGuid\(\):N\}/);
  assert.match(api, /GetUnifiedContact\(request\)/);
});

test('REQ-032 keeps service configuration usable on narrow screens', async () => {
  const page = await readFile(new URL('./src/pages/Settings.tsx', import.meta.url), 'utf8');
  assert.match(page, />服务配置</);
  assert.match(page, /grid grid-cols-1 sm:grid-cols-2 gap-4/);
  assert.match(page, /AgentFree 网关地址/);
  assert.match(page, /gatewayBaseUrl/);
  assert.doesNotMatch(page, /config\.agent\.apiKey/);
  assert.doesNotMatch(page, /config\.agent\.endpoint/);
});

test('REQ-033 streams mobile family agent responses without waiting for the full turn', async () => {
  const [layout, launcher, assistant, chat, cleanChat, agentApi, api, project, deploy] = await Promise.all([
    readFile(new URL('./src/components/Layout.tsx', import.meta.url), 'utf8'),
    readFile(new URL('./src/components/MobileAssistantBar.tsx', import.meta.url), 'utf8'),
    readFile(new URL('./src/pages/Assistant.tsx', import.meta.url), 'utf8'),
    readFile(new URL('./src/components/agentfree-webapp/AgentFreeWebAppChat.tsx', import.meta.url), 'utf8'),
    readFile(new URL('./src/components/agentfree-webapp/CleanChatView.tsx', import.meta.url), 'utf8'),
    readFile(new URL('./src/components/agentfree-webapp/api.ts', import.meta.url), 'utf8'),
    readFile(new URL('../FamilyReward.Api/Program.cs', import.meta.url), 'utf8'),
    readFile(new URL('../FamilyReward.Api/FamilyReward.Api.csproj', import.meta.url), 'utf8'),
    readFile(new URL('../scripts/deploy-production.sh', import.meta.url), 'utf8'),
  ]);
  assert.match(layout, /<MobileAssistantBar/);
  assert.doesNotMatch(layout, /mobileNavItems\.slice\(0, 6\)/);
  assert.match(launcher, /navigate\('\/assistant'\)/);
  assert.match(assistant, /<AgentFreeWebAppChat/);
  assert.match(assistant, /currentUser=\{user\}/);
  assert.match(assistant, /webAppBotId=\{webAppBotId\}/);
  assert.match(assistant, /getSystemConfig\(\)/);
  assert.match(chat, /@agentfree\/webapp-chat/);
  assert.match(chat, /apiAdapter/);
  assert.match(cleanChat, /export \{ CleanChatView as default \} from '@agentfree\/webapp-chat'/);
  assert.doesNotMatch(cleanChat, /parseAgUiEnvelope/);
  assert.match(agentApi, /\/api\/agentfree\/chat\/stream/);
  assert.match(agentApi, /credentials: 'include'/);
  assert.match(api, /\/api\/agentfree\/sessions/);
  assert.match(api, /\/api\/webapp\/sessions/);
  assert.match(api, /OpenChatStreamAsync/);
  assert.match(api, /gatewayBaseUrl/);
  assert.match(api, /webAppBotId/);
  assert.match(api, /if \(active\) result\.Add\(item\.DeepClone\(\)\)/);
  assert.match(api, /text\/event-stream/);
  assert.match(api, /X-Accel-Buffering/);
  assert.doesNotMatch(api, /\/api\/agent\/invoke\/stream/);
  assert.match(project, /system_config\.json" CopyToPublishDirectory="Never"/);
  assert.match(deploy, /--exclude system_config\.json/);
});

test('REQ-034 adds child-friendly watch navigation, icons, leaderboard and faces', async () => {
  const api = await readFile(new URL('../FamilyReward.Api/Program.cs', import.meta.url), 'utf8');
  assert.match(api, /id="home-menu"/);
  assert.match(api, /setView\('home'\)/);
  assert.match(api, /classList\.toggle\('hidden', view !== 'home'\)/);
  assert.match(api, /const ruleIcons = \['📚', '✏️', '🪥', '🧹', '🏃', '🤝', '⏰', '🌟'\]/);
  assert.match(api, /class="leaderboard-banner"/);
  for (const face of ['dinosaur', 'rainbow', 'space']) assert.match(api, new RegExp(`data-face="${face}"`));
});

test('REQ-036 scopes personal rule templates to a parent across web, watch and MCP', async () => {
  const [api, page] = await Promise.all([
    readFile(new URL('../FamilyReward.Api/Program.cs', import.meta.url), 'utf8'),
    readFile(new URL('./src/pages/Rules.tsx', import.meta.url), 'utf8'),
  ]);
  assert.match(api, /CREATE TABLE IF NOT EXISTS user_rule_templates/);
  assert.match(api, /CREATE TABLE IF NOT EXISTS user_rule_template_items/);
  assert.match(api, /owner_app_user_id/);
  assert.match(api, /GetRules\(connectionString, binding\.Binding!\.ParentAppUserId\)/);
  assert.match(api, /allowed\.Add\("parent_user_id"\)/);
  assert.match(api, /ResolveMcpParentAppUserId/);
  assert.match(page, />我的规则模板</);
  assert.match(page, /saveRuleTemplate\(selectedIds\)/);
});

test('REQ-039 supports redline rules and ordered watch rewards', async () => {
  const [api, page] = await Promise.all([
    readFile(new URL('../FamilyReward.Api/Program.cs', import.meta.url), 'utf8'),
    readFile(new URL('./src/pages/Rules.tsx', import.meta.url), 'utf8'),
  ]);
  assert.match(api, /NormalizeRulePoints/);
  assert.match(api, /\["isRedLine"\] = points < 0/);
  assert.match(api, /source_redline_id INTEGER/);
  assert.match(api, /INSERT INTO rules \(name, category, points, cash_cny, description, source_redline_id\)/);
  assert.match(api, /FROM redlines/);
  assert.match(api, /GetDecimal\(rule, "points"\) > 0/);
  assert.match(api, /\.Take\(8\)/);
  assert.match(page, />红线规则</);
  assert.match(page, /奖励、红线规则中选入模板/);
  assert.doesNotMatch(page, /公共红线规则/);
  assert.match(page, /moveRule\(rule\.id, -1\)/);
  assert.match(page, /moveRule\(rule\.id, 1\)/);
});

test('REQ-045 previews the real watch UI for parent-owned children on mobile', async () => {
  const [app, page, mobileBar, backend] = await Promise.all([
    readFile(new URL('./src/App.tsx', import.meta.url), 'utf8'),
    readFile(new URL('./src/pages/VirtualWatch.tsx', import.meta.url), 'utf8'),
    readFile(new URL('./src/components/MobileAssistantBar.tsx', import.meta.url), 'utf8'),
    readFile(new URL('../FamilyReward.Api/Program.cs', import.meta.url), 'utf8'),
  ]);

  assert.match(app, /path="\/virtual-watch" element=\{<VirtualWatchPage \/>\}/);
  assert.match(mobileBar, /navigate\('\/virtual-watch'\)/);
  assert.match(mobileBar, /打开虚拟手表/);
  assert.match(page, /getChildren\(\{ ownedOnly: true \}\)/);
  assert.match(page, /ownedChildren\[0\]\?\.id/);
  assert.match(page, /children\.map\(\(child\)/);
  assert.match(page, /\/watch\?previewChildId=/);
  assert.match(backend, /MapGet\("\/api\/watch\/preview\/\{childId:int\}"/);
  assert.match(backend, /GetChildren\(connectionString, ownerAppUserId: access\.Profile!\.AppUserId\)/);
  assert.match(backend, /孩子不存在，或不属于当前家长账号/);
  assert.match(backend, /const isPreview = \/\^\\d\+\$\//);
  assert.match(backend, /虚拟手表仅供预览/);
});

test('REQ-048 requires parent scope for public MCP tools', async () => {
  const [api, library] = await Promise.all([
    readFile(new URL('../FamilyReward.Api/Program.cs', import.meta.url), 'utf8'),
    readFile(new URL('../application/mcp/family-reward-mcp-tool-library-split.json', import.meta.url), 'utf8'),
  ]);
  assert.match(api, /缺少必填参数 parent_user_id/);
  assert.match(api, /GetMcpVisibleFamilyChildren/);
  assert.match(api, /IsMcpFamilyAccessible/);
  assert.match(api, /parentAppUserId: ResolveMcpParentAppUserId\(arguments\)/);
  assert.match(api, /当前家长权限不足/);
  assert.match(library, /parent_user_id/);
});

test('REQ-049 removes legacy menus and manual watch request fields', async () => {
  const [layout, dashboard, api] = await Promise.all([
    readFile(new URL('./src/components/Layout.tsx', import.meta.url), 'utf8'),
    readFile(new URL('./src/pages/Dashboard.tsx', import.meta.url), 'utf8'),
    readFile(new URL('../FamilyReward.Api/Program.cs', import.meta.url), 'utf8'),
  ]);
  assert.doesNotMatch(layout, /label: '交易记录'/);
  assert.doesNotMatch(layout, /label: '统计报表'/);
  assert.doesNotMatch(dashboard, /navigate\('\/transactions'\)/);
  assert.doesNotMatch(api, /<input id="points" name="points" inputmode="decimal"/);
  assert.doesNotMatch(api, /<textarea id="note" name="note"/);
  assert.match(api, /<input type="hidden" id="points" name="points">/);
  assert.match(api, /请先选择一项奖励规则/);
});

test('REQ-040 organizes circle management into four tabs', async () => {
  const page = await readFile(new URL('./src/pages/FamilyGroups.tsx', import.meta.url), 'utf8');
  assert.match(page, /role="tablist"/);
  for (const label of ['查看圈子', '新增圈子', '邀请他人加入圈子', '加入其他圈子']) assert.match(page, new RegExp(label));
  assert.match(page, /id="family-view-select"/);
  assert.match(page, /我创建的/);
  assert.match(page, /我加入的/);
  assert.match(page, /孩子归属家长关系不会因切换圈子而改变/);
});

test('REQ-050/051/052 separates circle and household member management', async () => {
  const [layout, familyPage, services, types, api] = await Promise.all([
    readFile(new URL('./src/components/Layout.tsx', import.meta.url), 'utf8'),
    readFile(new URL('./src/pages/Children.tsx', import.meta.url), 'utf8'),
    readFile(new URL('./src/services/index.ts', import.meta.url), 'utf8'),
    readFile(new URL('./src/types/index.ts', import.meta.url), 'utf8'),
    readFile(new URL('../FamilyReward.Api/Program.cs', import.meta.url), 'utf8'),
  ]);
  assert.match(layout, /label: '圈子管理'/);
  assert.match(layout, /label: '家庭管理'/);
  assert.match(familyPage, /孩子成员/);
  assert.match(familyPage, /其他家庭成员/);
  assert.match(familyPage, /定义当前用户角色/);
  for (const role of ['爸爸', '妈妈', '爷爷', '奶奶', '外公', '外婆', '监护人', '其他']) {
    assert.match(familyPage, new RegExp(role));
  }
  assert.match(types, /interface HouseholdMember/);
  assert.match(services, /api\/family-members/);
  assert.match(api, /CREATE TABLE IF NOT EXISTS household_members/);
  assert.match(api, /owner_parent_app_user_id/);
  assert.match(api, /当前用户不能从家庭成员中删除/);
});
