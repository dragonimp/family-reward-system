import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

test('mobile assistant reuses the complete AgentFree WebApp chat surface', async () => {
  const [page, chat, cleanChat, api, backend, html, layout, styles] = await Promise.all([
    readFile(new URL('./src/pages/Assistant.tsx', import.meta.url), 'utf8'),
    readFile(new URL('./src/components/agentfree-webapp/AgentFreeWebAppChat.tsx', import.meta.url), 'utf8'),
    readFile(new URL('./src/components/agentfree-webapp/CleanChatView.tsx', import.meta.url), 'utf8'),
    readFile(new URL('./src/components/agentfree-webapp/api.ts', import.meta.url), 'utf8'),
    readFile(new URL('../FamilyReward.Api/Program.cs', import.meta.url), 'utf8'),
    readFile(new URL('./index.html', import.meta.url), 'utf8'),
    readFile(new URL('./src/components/Layout.tsx', import.meta.url), 'utf8'),
    readFile(new URL('./src/styles/global.css', import.meta.url), 'utf8'),
  ]);

  assert.match(page, /<AgentFreeWebAppChat/);
  assert.match(page, /routeBase="\/assistant"/);
  assert.match(page, /webAppBotId=\{webAppBotId\}/);
  assert.match(page, /getSystemConfig\(\)/);
  assert.match(chat, /@agentfree\/webapp-chat/);
  assert.match(chat, /apiAdapter/);
  assert.match(cleanChat, /export \{ CleanChatView as default \} from '@agentfree\/webapp-chat'/);
  assert.doesNotMatch(cleanChat, /streamChat\(/);
  assert.match(api, /\/api\/agentfree\/chat\/stream/);
  assert.match(api, /readCurrentAppProfile/);
  assert.match(api, /'X-App-User-Id': appProfile\.appUserId/);
  assert.match(api, /'X-App-User-Role': appProfile\.role/);
  assert.match(api, /headers:\s*\{\s*'Content-Type': 'application\/json',\s*\.\.\.authHeaders\(\)/s);
  assert.match(backend, /webAppBotId/);
  assert.match(backend, /if \(active\) result\.Add\(item\.DeepClone\(\)\)/);
  assert.match(backend, /OpenChatStreamAsync/);
  assert.match(backend, /gatewayBaseUrl/);
  assert.doesNotMatch(backend, /\/api\/agent\/invoke\/stream/);
  assert.match(html, /initial-scale=1\.0, viewport-fit=cover/);
  assert.doesNotMatch(html, /user-scalable=no|maximum-scale=1/);
  assert.match(layout, /className="app-viewport/);
  assert.match(layout, /className="app-safe-header/);
  assert.match(styles, /height: 100dvh/);
  assert.match(styles, /-webkit-text-size-adjust: 100%/);
  assert.match(styles, /@media \(max-width: 768px\)[\s\S]*textarea,[\s\S]*font-size: 16px !important/);
});
