import test from 'node:test';
import assert from 'node:assert/strict';

globalThis.window = {
  localStorage: {
    getItem: () => JSON.stringify({ id: 'stale', username: 'stale-user' }),
    removeItem: () => undefined,
  },
} as unknown as Window & typeof globalThis;

const { readCurrentUser, refreshCurrentUser } = await import('./src/auth.ts');

test('browser storage cannot authenticate before /auth/me succeeds', async () => {
  let resolveFetch!: (value: Response) => void;
  globalThis.fetch = () => new Promise<Response>(resolve => { resolveFetch = resolve; });

  const refresh = refreshCurrentUser();
  assert.equal(readCurrentUser(), null);

  resolveFetch({
    ok: true,
    status: 200,
    json: async () => ({ id: 'verified', username: 'verified-user' }),
  } as Response);

  assert.deepEqual(await refresh, { id: 'verified', username: 'verified-user' });
});
