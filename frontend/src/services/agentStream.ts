import { readCurrentAppProfile, readCurrentUser } from '../auth';
import type { AgentInvokeRequest } from '../types';
import { consumeAgentEventStream } from './agentSse';
import type { AgentStreamEvent } from './agentSse';

function authHeaders(): Record<string, string> {
  const user = readCurrentUser();
  const profile = readCurrentAppProfile();
  const userId = user?.userId || user?.id;
  return {
    'Content-Type': 'application/json',
    ...(userId ? { 'X-User-Id': userId } : {}),
    ...(profile?.appUserId ? { 'X-App-User-Id': profile.appUserId } : {}),
    ...(profile?.role ? { 'X-App-User-Role': profile.role } : {}),
  };
}

export async function streamAgent(
  request: AgentInvokeRequest,
  onEvent: (event: AgentStreamEvent) => void,
  signal?: AbortSignal,
): Promise<void> {
  const response = await fetch('/api/agent/invoke/stream', {
    method: 'POST',
    credentials: 'include',
    headers: authHeaders(),
    body: JSON.stringify(request),
    signal,
  });

  if (!response.ok || !response.body) {
    const detail = await response.json().catch(() => null) as { error?: string } | null;
    throw new Error(detail?.error || `智能体服务响应失败（${response.status}）`);
  }

  await consumeAgentEventStream(response.body, onEvent);
}
