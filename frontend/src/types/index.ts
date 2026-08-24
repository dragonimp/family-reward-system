// 用户/孩子类型定义
export interface Child {
  id: number;
  familyGroupId?: number;
  family_group_id?: number;
  familyGroupName?: string;
  family_group_name?: string;
  profileKey?: string;
  profile_key?: string;
  name: string;
  score?: number;
  cash?: number;
  items?: number;
  parentNames?: string;
  avatar?: string;
  createdAt?: string;
  updatedAt?: string;
}

export interface ChildAuthCode {
  code: string;
  expiresAt: string;
  expiresInMinutes: number;
  child: Child;
}

export interface WatchDeviceBinding {
  id: number;
  childId: number;
  familyGroupId: number;
  childProfileKey: string;
  parentAppUserId: string;
  deviceName: string;
  platform: string;
  userAgent: string;
  boundAt: string;
  lastSeenAt: string;
  revokedAt?: string | null;
  active: boolean;
}

export interface ChildWatchDevices {
  child: Child;
  devices: WatchDeviceBinding[];
}

export interface ChildFriend {
  friendshipId?: number;
  profileKey: string;
  name: string;
  score: number;
  cash: number;
  items: number;
  createdAt?: string;
  rank?: number;
  isSelf?: boolean;
}

export interface ChildFriendsPayload {
  child?: Child;
  friends: ChildFriend[];
  leaderboard: ChildFriend[];
}

export interface ChildFriendNotification {
  id: number;
  childProfileKey: string;
  childName: string;
  friendProfileKey: string;
  friendName: string;
  friendshipId: number;
  message: string;
  readAt?: string | null;
  createdAt: string;
}

export interface ChildFriendNotificationsPayload {
  notifications: ChildFriendNotification[];
}

export interface WatchDeviceUnbindCode {
  code: string;
  deviceId: number;
  expiresAt: string;
  expiresInMinutes: number;
}

export interface WatchRewardRequest {
  id: number;
  familyGroupId: number;
  childId: number;
  childName: string;
  ruleId?: number | null;
  ruleName?: string;
  title: string;
  category: string;
  points: number;
  note?: string;
  status: string;
  statusText: string;
  requestedAt: string;
  reviewedAt?: string | null;
  completedAt?: string | null;
}

export interface WatchRewardRequestsPayload {
  familyGroupId: number;
  requests: WatchRewardRequest[];
}

export interface XiaotiancaiEmailAttachment {
  fileName: string;
  sizeBytes: number;
  sha256: string;
  contentType: string;
}

export interface XiaotiancaiDeviceTestEmailSubmission {
  id: number;
  requestedBy: string;
  recipient: string;
  sender: string;
  deviceModel: string;
  versionName: string;
  versionCode: number;
  subject: string;
  messageId?: string | null;
  previousMessageId?: string | null;
  attachments: XiaotiancaiEmailAttachment[];
  status: 'sending' | 'sent' | 'failed';
  providerResponse?: string | null;
  errorMessage?: string | null;
  sentAt?: string | null;
  createdAt: string;
  updatedAt: string;
}

export interface XiaotiancaiDeviceTestEmailPreview {
  recipient: string;
  sender: string;
  deviceModel: string;
  appName: string;
  packageId: string;
  versionName: string;
  versionCode: number;
  lastVerifiedAt: string;
  apkSha256: string;
  reportSha256: string;
  previousMessageId?: string | null;
  subject: string;
  body: string;
  attachments: XiaotiancaiEmailAttachment[];
  sendingConfigured: boolean;
  credentialReady: boolean;
  requestedBy: string;
  submissions: XiaotiancaiDeviceTestEmailSubmission[];
}

export interface FamilyGroup {
  id: number;
  name: string;
  description?: string;
  createdBy?: string;
  role?: string;
  createdAt?: string;
  updatedAt?: string;
}

export interface FamilyGroupInvite {
  familyGroupId: number;
  familyGroupName: string;
  inviteCode: string;
  inviteUrl: string;
  qrImageUrl: string;
}

export interface JoinFamilyGroupResult {
  ok: boolean;
  familyGroupId: number;
  familyGroupName: string;
  linkedChildCount: number;
}

export type HouseholdRole =
  | 'father'
  | 'mother'
  | 'grandfather'
  | 'grandmother'
  | 'maternal_grandfather'
  | 'maternal_grandmother'
  | 'guardian'
  | 'other';

export interface HouseholdMember {
  id: number;
  displayName: string;
  role: HouseholdRole;
  note?: string;
  isCurrentUser: boolean;
  createdAt: string;
  updatedAt: string;
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
  ownerAppUserId?: string | null;
  sourceRedlineId?: number | null;
  isPublic?: boolean;
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

export interface AuthUser {
  id?: string;
  userId?: string;
  username: string;
  displayName?: string;
  realName?: string;
  email?: string;
  phoneNumber?: string;
  role?: string;
  iconEmoji?: string;
  applicationKey?: string;
}

export interface AppUserProfile {
  unifiedUserId?: string;
  username?: string;
  channel?: 'pc' | 'watch' | string;
  role?: 'parent' | 'child' | string;
  appUserId?: string;
  childProfileKey?: string | null;
  childId?: number | null;
  needsRole?: boolean;
}

export interface AuthContextType {
  user: AuthUser | null;
  userId: string | null;
  appProfile: AppUserProfile | null;
  profileReady: boolean;
  ready: boolean;
  login: (returnUrl?: string) => void;
  logout: () => void;
  refresh: () => Promise<AuthUser | null>;
  refreshAppProfile: () => Promise<AppUserProfile | null>;
  selectAppRole: (role: 'parent' | 'child') => Promise<AppUserProfile>;
  isAuthenticated: boolean;
}

export interface VoiceConfig {
  enabled: boolean;
  recognitionLanguage: string;
  transcriptionProvider: string;
}

export interface AgentConfig {
  enabled: boolean;
  webAppBotId: string;
  gatewayBaseUrl: string;
}

export interface SystemConfig {
  voice: VoiceConfig;
  agent: AgentConfig;
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
