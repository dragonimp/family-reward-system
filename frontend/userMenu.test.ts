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

test('username menu only switches families and closes after use', async () => {
  const userMenu = await readFile(new URL('./src/components/UserMenu.tsx', import.meta.url), 'utf8');

  assert.match(userMenu, /切换家庭/);
  assert.doesNotMatch(userMenu, /新增家庭组|createGroup|showCreateGroupModal/);
  assert.match(userMenu, /selectGroup\(group\.id\);\s*closeMenu\(\)/);
  assert.match(userMenu, /menuRef\.current\?\.removeAttribute\('open'\)/);
});

test('family management exposes child owners and scoped removal', async () => {
  const [page, services] = await Promise.all([
    readFile(new URL('./src/pages/FamilyGroups.tsx', import.meta.url), 'utf8'),
    readFile(new URL('./src/services/index.ts', import.meta.url), 'utf8'),
  ]);

  assert.match(page, />家庭管理</);
  assert.match(page, /归属家长：\{child\.parentNames/);
  assert.match(page, /removeFamilyGroupChild\(selectedGroupId, childToRemove\.id\)/);
  assert.match(services, /api\/family-groups\/\$\{id\}\/children/);
  assert.match(services, /api\/family-groups\/\$\{id\}\/children\/\$\{childId\}/);
});
