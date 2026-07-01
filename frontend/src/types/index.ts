// 用户/孩子类型定义
export interface Child {
  id: number;
  name: string;
  score?: number;
  cash?: number;
  items?: number;
  avatar?: string;
  createdAt?: string;
  updatedAt?: string;
}

// 交易记录类型
export interface Transaction {
  id: number;
  childId: number;
  childName: string;
  type: 'points' | 'cash' | 'items' | 'score' | 'cash' | 'item'; // 类型
  category: string; // 分类
  amount?: number; // 金额/积分
  description?: string; // 描述
  ruleId?: number; // 关联规则
  createdAt?: string;
}

// 积分规则类型
export interface Rule {
  id: number;
  name: string;
  description: string;
  category: string; // 分类
  type: 'positive' | 'negative'; // 正向/负向
  isRedLine: boolean; // 是否红线规则
  score: number; // 积分值
  enabled: boolean; // 是否启用
  createdAt: string;
  updatedAt: string;
}

// 统计数据类型
export interface ChildStats {
  childId: number;
  childName: string;
  totalScore: number; // 累计积分
  totalCash: number; // 累计现金
  totalItems: number; // 累计物品
  scoreCount: number; // 积分交易次数
  cashCount: number; // 现金交易次数
  itemCount: number; // 物品交易次数;
  avgDailyScore: number; // 日均积分
}

// 趋势数据
export interface TrendData {
  date: string;
  score: number;
  cash: number;
  item: number;
}

// API 响应通用格式
export interface ApiResponse<T> {
  code: number;
  message: string;
  data: T;
}

export interface VoiceConfig {
  enabled: boolean;
  recognitionLanguage: string;
  transcriptionProvider: string;
}

export interface AgentConfig {
  enabled: boolean;
  endpoint: string;
  apiKey: string;
  model: string;
  timeout_seconds: number;
  systemPrompt: string;
}

export interface SystemConfig {
  voice: VoiceConfig;
  agent: AgentConfig;
}

export interface AgentInvokeRequest {
  prompt: string;
  payload?: Record<string, unknown>;
  apiKey?: string;
}

export interface AgentInvokeResponse {
  ok: boolean;
  status?: number;
  response?: unknown;
  error?: string;
}

export interface RewardCommand {
  childId?: number | null;
  childName?: string | null;
  type: 'score' | 'cash' | 'item';
  amount: number;
  category?: string;
  description?: string;
  confidence?: number;
}

export interface RewardParseRequest {
  text: string;
}

export interface RewardParseResponse {
  ok: boolean;
  command?: RewardCommand;
  raw?: string;
  error?: string;
}

// 分页请求参数
export interface PaginationParams {
  page: number;
  pageSize: number;
}

// 分页响应
export interface PaginatedResponse<T> {
  items: T[];
  total: number;
  page: number;
  pageSize: number;
}

// 交易筛选条件
export interface TransactionFilters {
  childId?: number;
  type?: 'score' | 'cash' | 'item';
  startDate?: string;
  endDate?: string;
  category?: string;
  search?: string;
}
