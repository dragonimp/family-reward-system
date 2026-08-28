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
  assert.match(chat, /messageMode === 'steer' \? 'steer' : undefined/);
  assert.doesNotMatch(chat, /messageMode: request\.messageMode === 'steer' \? 'steer' : 'queue'/);
  assert.match(cleanChat, /export \{ CleanChatView as default \} from '@agentfree\/webapp-chat'/);
  assert.doesNotMatch(cleanChat, /streamChat\(/);
  assert.match(api, /\/api\/agentfree\/chat\/stream/);
  assert.match(api, /getSessions = \(gatewayType\?: string, user\?: string, agentId\?: number, limit\?: number\)/);
  assert.match(api, /agentId: agentId \|\| undefined,[\s\S]*limit: limit \|\| undefined,[\s\S]*webAppBotId: getWebAppBotId\(\)/);
  assert.match(api, /readCurrentAppProfile/);
  assert.match(api, /AGENTFREE_REQUEST_TIMEOUT_MS = 10 \* 60 \* 1000/);
  assert.match(api, /function agentFreeRequestConfig/);
  assert.match(api, /timeout: AGENTFREE_REQUEST_TIMEOUT_MS/);
  assert.match(api, /respondInteraction[\s\S]*agentFreeRequestConfig\(\)/);
  assert.match(api, /'X-App-User-Id': appProfile\.appUserId/);
  assert.match(api, /'X-App-User-Role': appProfile\.role/);
  assert.match(api, /headers:\s*\{\s*'Content-Type': 'application\/json',\s*\.\.\.authHeaders\(\)/s);
  assert.match(backend, /webAppBotId/);
  assert.match(backend, /request\.Query\.Int\("agentId"\)/);
  assert.match(backend, /authorizedAgentIds\.Contains\(requestedAgentId\.Value\)/);
  assert.match(backend, /authorizedAgentIds\.Contains\(session\.AgentId\)/);
  assert.match(backend, /GetSessionsAsync\(/);
  assert.match(backend, /GetSessionMessagesAsync\(/);
  assert.match(backend, /GetSessionTimelineAsync\(/);
  assert.match(backend, /GetSessionQueueAsync\(/);
  assert.match(backend, /Queue polling is auxiliary[\s\S]*waitingCount["'\]]+\s*=\s*0/);
  assert.doesNotMatch(backend, /获取智能体会话队列失败/);
  assert.match(backend, /CreateSessionAsync\(/);
  assert.match(backend, /UpdateSessionAsync\(/);
  assert.match(backend, /ResetSessionContextAsync\(/);
  assert.match(backend, /RespondInteractionAsync\(/);
  assert.doesNotMatch(backend, /SendAgentFreeJson/);
  assert.doesNotMatch(backend, /GetFamilyRewardAgentFreeSessionForBot\(httpClientFactory, sessionId, userName, "web-jiajaifen-chat"/);
  assert.match(backend, /if \(active\) result\.Add\(item\.DeepClone\(\)\)/);
  assert.match(backend, /OpenChatStreamAsync/);
  assert.match(backend, /gatewayBaseUrl/);
  assert.doesNotMatch(backend, /\/api\/agent\/invoke\/stream/);
  assert.match(html, /initial-scale=1\.0, viewport-fit=cover/);
  assert.doesNotMatch(html, /user-scalable=no|maximum-scale=1/);
  assert.match(layout, /assistantOpen \? 'assistant-mode '/);
  assert.match(layout, /document\.body\.classList\.toggle\('assistant-mode', assistantOpen\)/);
  assert.match(layout, /app-viewport flex flex-col/);
  assert.match(layout, /className="app-safe-header/);
  assert.match(styles, /height: 100dvh/);
  assert.match(styles, /-webkit-text-size-adjust: 100%/);
  assert.match(styles, /@media \(max-width: 768px\)[\s\S]*textarea,[\s\S]*font-size: 16px !important/);
  assert.match(styles, /body\.assistant-mode \.adfw-dock[\s\S]*bottom: calc\(132px \+ env\(safe-area-inset-bottom, 0px\)\)/);
});

test('family reward MCP requires tool-grounded business answers', async () => {
  const [backend, gatewayLibrary, splitLibrary] = await Promise.all([
    readFile(new URL('../FamilyReward.Api/Program.cs', import.meta.url), 'utf8'),
    readFile(new URL('../application/goldfish-tool-library.json', import.meta.url), 'utf8'),
    readFile(new URL('../application/mcp/family-reward-mcp-tool-library-split.json', import.meta.url), 'utf8'),
  ]);

  for (const source of [backend, gatewayLibrary, splitLibrary]) {
    assert.match(source, /必须先调用对应工具/);
    assert.match(source, /只能依据(?:工具)?本次返回的数据回答/);
    assert.match(source, /不得(?:依赖记忆、会话)?猜测/);
    assert.match(source, /无法核验/);
  }
  assert.match(backend, /instructions = \$"[^"]*\{FamilyRewardMcpGroundingInstructions\}"/);
});
