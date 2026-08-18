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

test('username menu only switches circles and closes after use', async () => {
  const userMenu = await readFile(new URL('./src/components/UserMenu.tsx', import.meta.url), 'utf8');

  assert.match(userMenu, /切换圈子/);
  assert.doesNotMatch(userMenu, /新增圈子|createGroup|showCreateGroupModal/);
  assert.match(userMenu, /selectGroup\(group\.id\);\s*closeMenu\(\)/);
  assert.match(userMenu, /menuRef\.current\?\.removeAttribute\('open'\)/);
});

test('circle management exposes child owners and scoped removal', async () => {
  const [page, services] = await Promise.all([
    readFile(new URL('./src/pages/FamilyGroups.tsx', import.meta.url), 'utf8'),
    readFile(new URL('./src/services/index.ts', import.meta.url), 'utf8'),
  ]);

  assert.match(page, />圈子管理</);
  assert.match(page, /归属家长：\{child\.parentNames/);
  assert.match(page, /removeFamilyGroupChild\(selectedGroupId, childToRemove\.id\)/);
  assert.match(services, /api\/family-groups\/\$\{id\}\/children/);
  assert.match(services, /api\/family-groups\/\$\{id\}\/children\/\$\{childId\}/);
});

test('circle management can delete circles without deleting global children', async () => {
  const [page, services] = await Promise.all([
    readFile(new URL('./src/pages/FamilyGroups.tsx', import.meta.url), 'utf8'),
    readFile(new URL('./src/services/index.ts', import.meta.url), 'utf8'),
  ]);

  assert.match(services, /deleteFamilyGroup = \(id: number\) => http\.delete\(`\/api\/family-groups\/\$\{id\}`\)/);
  assert.match(page, /title="删除圈子"/);
  assert.match(page, /孩子、归属家长和积分账户会保留/);
});

test('reward and transaction pages use parent-owned children globally', async () => {
  const [reward, transactions] = await Promise.all([
    readFile(new URL('./src/pages/Reward.tsx', import.meta.url), 'utf8'),
    readFile(new URL('./src/pages/Transactions.tsx', import.meta.url), 'utf8'),
  ]);

  assert.match(reward, /getChildren\(\{ ownedOnly: true \}\)/);
  assert.doesNotMatch(reward, /family_group_id: selectedGroupId|familyGroupId: selectedGroupId/);
  assert.match(transactions, /getChildren\(\{ ownedOnly: true \}\)/);
  assert.doesNotMatch(transactions, /familyGroupId: selectedGroupId/);
});
