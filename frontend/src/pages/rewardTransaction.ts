import type { Child, Rule } from '../types';

export type RewardTransactionType = 'score' | 'cash' | 'item';

export interface RewardTransactionPreview {
  child: Pick<Child, 'id' | 'name'>;
  rule?: Pick<Rule, 'name'> | null;
  amount: number;
  type: RewardTransactionType;
  category?: string;
  description?: string;
}

export interface RewardTransactionPayload {
  child_id: number;
  child_name: string;
  category: string;
  description: string;
  type: 'points' | 'cash' | 'items';
  direction: '+' | '-';
  points?: number;
  cash_cny?: number;
  items?: string;
}

export function buildRewardTransactionPayload(
  preview: RewardTransactionPreview,
): RewardTransactionPayload {
  const { child, rule, amount, type, category, description } = preview;
  const resolvedDescription = description || rule?.name || '自定义操作';
  const payload: RewardTransactionPayload = {
    child_id: child.id,
    child_name: child.name,
    category: category || '其他',
    description: resolvedDescription,
    type: type === 'score' ? 'points' : type === 'cash' ? 'cash' : 'items',
    direction: amount >= 0 ? '+' : '-',
  };

  if (type === 'score') {
    payload.points = Math.abs(amount);
  } else if (type === 'cash') {
    payload.cash_cny = Math.abs(amount);
  } else {
    payload.items = description || rule?.name || '物品';
  }

  return payload;
}
