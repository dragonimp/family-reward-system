import type { Child } from '../types';

/**
 * 全局共享的孩子数据 - 所有页面统一引用
 * 管理页面新增/修改孩子时，数据来自 API，其他页面通过 getChildren() 获取
 * 此常量仅用于 fallback（API 失败时）
 */
export const CHILDREN_DATA: Child[] = [
  { id: 1, name: '彦谦', score: 108, cash: 230, items: 2, createdAt: '', updatedAt: '' },
  { id: 2, name: '玥玥', score: 123, cash: 30, items: 1, createdAt: '', updatedAt: '' },
  { id: 3, name: '嘟嘟', score: 100, cash: 0, items: 0, createdAt: '', updatedAt: '' },
  { id: 4, name: '薇薇', score: 100, cash: 0, items: 0, createdAt: '', updatedAt: '' },
  { id: 5, name: '小宇', score: 100, cash: 0, items: 0, createdAt: '', updatedAt: '' },
];
