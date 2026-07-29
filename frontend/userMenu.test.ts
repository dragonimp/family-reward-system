import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

import { getUserCenterUrl } from './src/auth.ts';

test('account actions use same-origin AgentIdentity SDK routes', () => {
  assert.equal(getUserCenterUrl('info'), '/auth/user-center?section=info');
  assert.equal(getUserCenterUrl('password'), '/auth/user-center?section=password');
});

test('all account actions live inside the username menu', async () => {
  const [layout, userMenu] = await Promise.all([
    readFile(new URL('./src/components/Layout.tsx', import.meta.url), 'utf8'),
    readFile(new URL('./src/components/UserMenu.tsx', import.meta.url), 'utf8'),
  ]);

  assert.doesNotMatch(layout, /auth\/logout|退出登录/);
  assert.match(userMenu, /修改信息/);
  assert.match(userMenu, /修改密码/);
  assert.match(userMenu, /退出登录/);
});
