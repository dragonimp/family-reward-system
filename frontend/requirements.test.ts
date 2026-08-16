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

test('REQ-031 submits feedback through the same-origin Atlas proxy and lists current user records', async () => {
  const [widget, services, api] = await Promise.all([
    readFile(new URL('./src/components/FeedbackWidget.tsx', import.meta.url), 'utf8'),
    readFile(new URL('./src/services/index.ts', import.meta.url), 'utf8'),
    readFile(new URL('../FamilyReward.Api/Program.cs', import.meta.url), 'utf8'),
  ]);
  assert.match(widget, /sourceRecordId: recordId/);
  assert.match(widget, /页面信息/);
  assert.match(services, /'\/api\/feedback'/);
  assert.match(services, /'\/api\/feedback\/mine'/);
  assert.match(api, /source_system"] = "family-reward-web"/);
  assert.match(api, /X-Atlas-User-Id/);
  assert.match(api, /\["path"\] = SanitizeFeedbackPath/);
});

test('REQ-032 keeps service configuration usable on narrow screens', async () => {
  const page = await readFile(new URL('./src/pages/Settings.tsx', import.meta.url), 'utf8');
  assert.match(page, />服务配置</);
  assert.match(page, /flex flex-col gap-2 sm:flex-row/);
  assert.match(page, /max-w-full overflow-x-auto/);
});

test('REQ-033 replaces mobile bottom navigation with the family agent command bar', async () => {
  const [layout, assistant] = await Promise.all([
    readFile(new URL('./src/components/Layout.tsx', import.meta.url), 'utf8'),
    readFile(new URL('./src/components/MobileAssistantBar.tsx', import.meta.url), 'utf8'),
  ]);
  assert.match(layout, /<MobileAssistantBar/);
  assert.doesNotMatch(layout, /mobileNavItems\.slice\(0, 6\)/);
  assert.match(assistant, /家庭积分应用/);
  assert.match(assistant, /startVoice/);
  assert.match(assistant, /invokeAgent/);
  assert.match(assistant, /onOpenMenu/);
});
