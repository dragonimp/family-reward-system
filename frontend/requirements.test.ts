import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

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
  assert.match(widget, /https:\/\/home\.ai\.impx\.net\/feedback-widget\.js/);
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
  assert.match(page, /flex flex-col gap-2 sm:flex-row/);
  assert.match(page, /max-w-full overflow-x-auto/);
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
  assert.match(chat, /import CleanChatView/);
  assert.match(chat, /getSessions\('WebApp'/);
  assert.match(cleanChat, /parseAgUiEnvelope/);
  assert.match(cleanChat, /stream\.delta/);
  assert.match(cleanChat, /stream\.done/);
  assert.match(agentApi, /\/api\/agentfree\/chat\/stream/);
  assert.match(agentApi, /credentials: 'include'/);
  assert.match(api, /InvokeGoldfishAcp/);
  assert.match(api, /\/api\/agentfree\/sessions/);
  assert.match(api, /\/api\/webapp\/sessions/);
  assert.match(api, /\/api\/webapp\/chat\/stream/);
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
  assert.match(api, /FamilyRewardMcpQueryRulesToolName => new\(StringComparer\.Ordinal\) \{ "user_id" \}/);
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

test('REQ-040 organizes family management into four tabs', async () => {
  const page = await readFile(new URL('./src/pages/FamilyGroups.tsx', import.meta.url), 'utf8');
  assert.match(page, /role="tablist"/);
  for (const label of ['查看家庭', '新增家庭', '邀请他人加入家庭', '加入其他家庭']) assert.match(page, new RegExp(label));
  assert.match(page, /id="family-view-select"/);
  assert.match(page, /我创建的/);
  assert.match(page, /我加入的/);
  assert.match(page, /孩子归属家长关系不会因切换家庭而改变/);
});
