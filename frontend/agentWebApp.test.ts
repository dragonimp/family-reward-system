import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

test('mobile assistant reuses the complete AgentFree WebApp chat surface', async () => {
  const [page, chat, cleanChat, api, backend] = await Promise.all([
    readFile(new URL('./src/pages/Assistant.tsx', import.meta.url), 'utf8'),
    readFile(new URL('./src/components/agentfree-webapp/AgentFreeWebAppChat.tsx', import.meta.url), 'utf8'),
    readFile(new URL('./src/components/agentfree-webapp/CleanChatView.tsx', import.meta.url), 'utf8'),
    readFile(new URL('./src/components/agentfree-webapp/api.ts', import.meta.url), 'utf8'),
    readFile(new URL('../FamilyReward.Api/Program.cs', import.meta.url), 'utf8'),
  ]);

  assert.match(page, /<AgentFreeWebAppChat/);
  assert.match(page, /routeBase="\/assistant"/);
  assert.match(page, /webAppBotId="web"/);
  assert.match(chat, /import CleanChatView from '\.\/CleanChatView'/);
  assert.match(chat, /getSessions\('WebApp'/);
  assert.match(cleanChat, /streamChat\(/);
  assert.match(cleanChat, /stream\.delta/);
  assert.match(cleanChat, /parseAgUiEnvelope/);
  assert.match(api, /\/api\/agentfree\/chat\/stream/);
  assert.match(backend, /agentCode"\), "happylife"/);
  assert.match(backend, /\/api\/webapp\/chat\/stream/);
  assert.doesNotMatch(backend, /\/api\/agent\/invoke\/stream/);
});
