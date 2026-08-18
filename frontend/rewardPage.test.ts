import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

import { buildRewardTransactionPayload } from './src/pages/rewardTransaction.ts';

test('parent reward page builds positive and negative point transactions', () => {
  assert.deepEqual(buildRewardTransactionPayload({
    child: { id: 7, name: '小明' },
    rule: { name: '主动阅读' },
    amount: 5,
    type: 'score',
    category: '学习',
    description: '主动阅读',
  }), {
    child_id: 7,
    child_name: '小明',
    category: '学习',
    description: '主动阅读',
    type: 'points',
    direction: '+',
    points: 5,
  });

  assert.deepEqual(buildRewardTransactionPayload({
    child: { id: 7, name: '小明' },
    amount: -3,
    type: 'score',
  }), {
    child_id: 7,
    child_name: '小明',
    category: '其他',
    description: '自定义操作',
    type: 'points',
    direction: '-',
    points: 3,
  });
});

test('parent reward page builds cash and item transactions', () => {
  const child = { id: 9, name: '小雨' };

  assert.deepEqual(buildRewardTransactionPayload({
    child,
    amount: -12.5,
    type: 'cash',
    category: '零花钱',
    description: '购买文具',
  }), {
    child_id: 9,
    child_name: '小雨',
    category: '零花钱',
    description: '购买文具',
    type: 'cash',
    direction: '-',
    cash_cny: 12.5,
  });

  assert.deepEqual(buildRewardTransactionPayload({
    child,
    rule: { name: '周末电影' },
    amount: 1,
    type: 'item',
    category: '娱乐',
  }), {
    child_id: 9,
    child_name: '小雨',
    category: '娱乐',
    description: '周末电影',
    type: 'items',
    direction: '+',
    items: '周末电影',
  });

  assert.equal(buildRewardTransactionPayload({
    child,
    amount: -1,
    type: 'item',
  }).items, '物品');
});

test('parent reward page loads owned children and supports watch request approval', async () => {
  const page = await readFile(new URL('./src/pages/Reward.tsx', import.meta.url), 'utf8');

  assert.match(page, /getChildren\(\{ ownedOnly: true \}\)/);
  assert.match(page, /getRewardRequests\(\{ status: 'pending', limit: 20 \}\)/);
  assert.match(page, /approveRewardRequest\(requestId/);
  assert.match(page, /await loadData\(true\)/);
});
