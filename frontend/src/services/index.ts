import http from './api';
import type { Child, CreditDetail } from '../types';
import type { FamilyGroup, FamilyGroupInvite, HouseholdMember, JoinFamilyGroupResult } from '../types';
import type { GenealogyDiscovery, GenealogyInferredRelationship, GenealogyJoinRequest, GenealogyPerson, GenealogyRelationship, GenealogyTree, MyGenealogyJoinRequest } from '../types';
import type {
  ChildAuthCode,
  ChildFriendNotificationsPayload,
  ChildFriendsPayload,
  ChildWatchDevices,
  WatchDeviceUnbindCode,
  WatchRewardRequestsPayload,
} from '../types';
import type { SystemConfig } from '../types';
import type { XiaotiancaiDeviceTestEmailPreview, XiaotiancaiDeviceTestEmailSubmission } from '../types';
import type { ChildGrowthStats, GrowthReport, WarmMoment } from '../types';

export const getFamilyGroups = (params?: { userId?: string }) => http.get<unknown, FamilyGroup[]>('/api/family-groups', { params });
export const createFamilyGroup = (data: Partial<FamilyGroup>) => http.post<unknown, FamilyGroup>('/api/family-groups', data);
export const updateFamilyGroup = (id: number, data: Partial<FamilyGroup>) =>
  http.put<unknown, FamilyGroup>(`/api/family-groups/${id}`, data);
export const deleteFamilyGroup = (id: number) => http.delete(`/api/family-groups/${id}`);
export const getFamilyGroupInvite = (id: number) => http.get<unknown, FamilyGroupInvite>(`/api/family-groups/${id}/invite`);
export const joinFamilyGroup = (data: { inviteCode: string }) =>
  http.post<unknown, JoinFamilyGroupResult>('/api/family-groups/join', data);
export const linkFamilyGroupUser = (id: number, data: { userId: string; role?: string }) => http.put(`/api/family-groups/${id}/users`, data);
export const getFamilyGroupChildren = (id: number) =>
  http.get<unknown, Child[]>(`/api/family-groups/${id}/children`);
export const removeFamilyGroupChild = (id: number, childId: number) =>
  http.delete(`/api/family-groups/${id}/children/${childId}`);

export const getHouseholdMembers = () => http.get<unknown, HouseholdMember[]>('/api/family-members');
export const createHouseholdMember = (data: Pick<HouseholdMember, 'displayName' | 'role' | 'note'>) =>
  http.post<unknown, HouseholdMember>('/api/family-members', data);
export const updateHouseholdMember = (id: number, data: Pick<HouseholdMember, 'displayName' | 'role' | 'note'>) =>
  http.put<unknown, HouseholdMember>(`/api/family-members/${id}`, data);
export const deleteHouseholdMember = (id: number) => http.delete(`/api/family-members/${id}`);

export const getGenealogies = () => http.get<unknown, GenealogyTree[]>('/api/genealogies');
export const discoverGenealogies = (q: string) => http.get<unknown, GenealogyDiscovery[]>('/api/genealogies/discover', { params: { q } });
export const getMyGenealogyJoinRequests = () => http.get<unknown, MyGenealogyJoinRequest[]>('/api/genealogies/my-join-requests');
export const createGenealogy = (data: { name: string; surname: string; description: string }) => http.post<unknown, GenealogyTree>('/api/genealogies', data);
export const getGenealogy = (id: number) => http.get<unknown, GenealogyTree>(`/api/genealogies/${id}`);
export const requestGenealogyJoin = (id: number, data: { displayName: string; message: string }) => http.post(`/api/genealogies/${id}/join-requests`, data);
export const getGenealogyJoinRequests = (id: number) => http.get<unknown, GenealogyJoinRequest[]>(`/api/genealogies/${id}/join-requests`);
export const decideGenealogyJoin = (id: number, requestId: number, decision: 'approve' | 'reject', personId?: number) => http.post(`/api/genealogies/${id}/join-requests/${requestId}/decision`, { decision, ...(personId ? { personId } : {}) });
export const getGenealogyPeople = (id: number, q = '') => http.get<unknown, { people: GenealogyPerson[]; hasMore: boolean }>(`/api/genealogies/${id}/people`, { params: { q } });
export const getGenealogyPerson = (id: number, personId: number) => http.get<unknown, GenealogyPerson>(`/api/genealogies/${id}/people/${personId}`);
export const createGenealogyPerson = (id: number, data: Pick<GenealogyPerson, 'displayName' | 'generationLabel' | 'branchName' | 'note' | 'gender' | 'birthYear' | 'birthMonth' | 'birthDay'>) => http.post<unknown, GenealogyPerson>(`/api/genealogies/${id}/people`, data);
export const updateGenealogyPerson = (id: number, personId: number, data: Pick<GenealogyPerson, 'displayName' | 'generationLabel' | 'branchName' | 'note' | 'gender' | 'birthYear' | 'birthMonth' | 'birthDay'>) => http.put<unknown, GenealogyPerson>(`/api/genealogies/${id}/people/${personId}`, data);
export interface GenealogyInvitation { treeId: number; personId: number; treeName: string; personName: string; expiresAt: string; available: boolean }
export const createGenealogyInvitation = (id: number, personId: number) => http.post<unknown, { path: string; expiresAt: string }>(`/api/genealogies/${id}/people/${personId}/invitations`);
export const getGenealogyInvitation = (token: string) => http.get<unknown, GenealogyInvitation>(`/api/genealogies/invitations/${encodeURIComponent(token)}`);
export const acceptGenealogyInvitation = (token: string) => http.post<unknown, { treeId: number; personId: number }>(`/api/genealogies/invitations/${encodeURIComponent(token)}/accept`);
export const getGenealogyRelationships = (id: number) => http.get<unknown, GenealogyRelationship[]>(`/api/genealogies/${id}/relationships`);
export const getGenealogyInferredRelationships = (id: number, personId: number) => http.get<unknown, GenealogyInferredRelationship[]>(`/api/genealogies/${id}/people/${personId}/inferred-relationships`);
export const createGenealogyRelationship = (id: number, data: { fromPersonId: number; toPersonId: number; kind: 'parent' | 'spouse' }) => http.post(`/api/genealogies/${id}/relationships`, data);
export const deleteGenealogyRelationship = (id: number, relationId: number) => http.delete(`/api/genealogies/${id}/relationships/${relationId}`);

export const getChildren = (params?: { familyGroupId?: number; ownedOnly?: boolean }) => http.get('/api/children', { params });
export type ConnectionKind = 'special_time' | 'listen' | 'reconnect' | 'meeting';
export type ConnectionEntryType = 'message' | 'feeling' | 'hope' | 'proposal' | 'reflection';
export interface ConnectionThread {
  id: number; childProfileKey: string; childName: string; kind: ConnectionKind; title: string;
  intent: string; status: string; scheduledAt: string | null; reviewAt: string | null;
  trialPlan: string; createdBy: string; createdAt: string; updatedAt: string;
}
export interface ConnectionEntry { id: number; connectionId: number; authorRole: 'child' | 'parent'; type: ConnectionEntryType; content: string; createdAt: string }
export interface ConnectionsPayload { threads: ConnectionThread[]; entries: ConnectionEntry[] }
export const getFamilyConnections = () => http.get<unknown, ConnectionsPayload>('/api/family-connections');
export const createFamilyConnection = (data: { childId: number; kind: ConnectionKind; title: string; intent: string; requestId: string }) =>
  http.post<unknown, ConnectionsPayload>('/api/family-connections', data);
export const addFamilyConnectionEntry = (id: number, data: { type: ConnectionEntryType; content: string; requestId: string }) =>
  http.post<unknown, ConnectionsPayload>(`/api/family-connections/${id}/entries`, data);
export const transitionFamilyConnection = (id: number, data: { action: string; scheduledAt?: string; plan?: string }) =>
  http.post<unknown, ConnectionsPayload>(`/api/family-connections/${id}/transition`, data);
export const getCreditOverview = () => http.get<unknown, { children: Array<{ profileKey: string; creditEnabled: boolean; creditScore: number | null }> }>('/api/credit/overview');
export const getChildCredit = (childId: number) => http.get<unknown, CreditDetail>(`/api/children/${childId}/credit`);
export const enableChildCredit = (childId: number) => http.post<unknown, CreditDetail>(`/api/children/${childId}/credit/enable`, {});
export const createCreditCommitment = (childId: number, data: { title: string; dueAt: string; requestId: string }) =>
  http.post<unknown, CreditDetail>(`/api/children/${childId}/credit/commitments`, data);
export const resolveCreditCommitment = (childId: number, commitmentId: number, data: { action: 'completed' | 'overdue'; note?: string }) =>
  http.post<unknown, CreditDetail>(`/api/children/${childId}/credit/commitments/${commitmentId}/resolve`, data);
export const adjustChildCredit = (childId: number, data: { reasonCode: string; delta: number; note: string; requestId: string }) =>
  http.post<unknown, CreditDetail>(`/api/children/${childId}/credit/adjustments`, data);
export const reverseCreditEvent = (childId: number, eventId: number, note: string) =>
  http.post<unknown, CreditDetail>(`/api/children/${childId}/credit/events/${eventId}/reverse`, { note });
export const resolveCreditDispute = (childId: number, disputeId: number, data: { action: 'accepted' | 'rejected'; response: string }) =>
  http.post<unknown, CreditDetail>(`/api/children/${childId}/credit/disputes/${disputeId}/resolve`, data);
export const getChild = (id: number) => http.get(`/api/children/${id}`);
export const createChild = (data: Partial<Child>) => http.post('/api/children', data);
export const updateChild = (id: number, data: Partial<Child>) => http.put(`/api/children/${id}`, data);
export const deleteChild = (id: number, params?: { familyGroupId?: number }) => http.delete(`/api/children/${id}`, { params });
export const generateChildAuthCode = (id: number, data?: { familyGroupId?: number; expiresInMinutes?: number }) =>
  http.post<unknown, ChildAuthCode>(`/api/children/${id}/auth-code`, data || {});
export const pairChildWatchDevice = (id: number, code: string) =>
  http.post<unknown, { deviceId: number; status: string }>(`/api/children/${id}/pair-device`, { code });
export const getChildWatchDevices = (id: number, params?: { familyGroupId?: number }) =>
  http.get<unknown, ChildWatchDevices>(`/api/children/${id}/devices`, { params });
export const revokeChildWatchDevice = (childId: number, deviceId: number, params?: { familyGroupId?: number }) =>
  http.delete(`/api/children/${childId}/devices/${deviceId}`, { params });
export const generateWatchDeviceUnbindCode = (
  childId: number,
  deviceId: number,
  data?: { familyGroupId?: number; expiresInMinutes?: number },
) => http.post<unknown, WatchDeviceUnbindCode>(`/api/children/${childId}/devices/${deviceId}/unbind-code`, data || {});
export const getChildFriends = (id: number, params?: { familyGroupId?: number }) =>
  http.get<unknown, ChildFriendsPayload>(`/api/children/${id}/friends`, { params });
export const getChildFriendNotifications = (params?: { unreadOnly?: boolean }) =>
  http.get<unknown, ChildFriendNotificationsPayload>('/api/children/friend-notifications', { params });
export const markChildFriendNotificationRead = (id: number) =>
  http.post<unknown, { status: string }>(`/api/children/friend-notifications/${id}/read`, {});
export const getRewardRequests = (params?: { familyGroupId?: number; status?: string; limit?: number }) =>
  http.get<unknown, WatchRewardRequestsPayload>('/api/reward-requests', { params });
export const approveRewardRequest = (id: number, data?: { familyGroupId?: number; reviewNote?: string }) =>
  http.post<unknown, { status: string; request: unknown; transaction: unknown }>(`/api/reward-requests/${id}/approve`, data || {});

export const getTransactions = (params: any) => http.get('/api/transactions', { params });
export const createTransaction = (data: any) => http.post('/api/transactions', data);
export const deleteTransaction = (id: number, params?: { familyGroupId?: number }) => http.delete(`/api/transactions/${id}`, { params });

export const getRules = () => http.get('/api/rules');
export const createRule = (data: any) => http.post('/api/rules', data);
export const updateRule = (id: number, data: any) => http.put(`/api/rules/${id}`, data);
export const deleteRule = (id: number) => http.delete(`/api/rules/${id}`);
export const saveRuleTemplate = (ruleIds: number[]) => http.put('/api/rule-template', { ruleIds });

export const getChildStats = (params?: { familyGroupId?: number }) => http.get('/api/stats/dashboard', { params });
export const getLeaderboard = (params?: { familyGroupId?: number }) => http.get('/api/stats/leaderboard', { params });
export const getCategoryStats = (params?: { familyGroupId?: number }) => http.get('/api/stats/categories', { params });
export const getGrowthStats = (params?: { familyGroupId?: number }) =>
  http.get<unknown, { children: ChildGrowthStats[] }>('/api/stats/growth', { params });
export const getWarmMoments = (params?: { childId?: number; limit?: number }) =>
  http.get<unknown, { moments: WarmMoment[] }>('/api/warm-moments', { params });
export const getGrowthReports = (params: { audience: 'child' | 'parent'; period: 'daily' | 'weekly' | 'monthly'; childId?: number; ai?: boolean }) =>
  http.get<unknown, { reports: GrowthReport[] }>('/api/growth-reports', { params });
export const getChildGrowthSettings = (childId: number, params?: { familyGroupId?: number }) =>
  http.get<unknown, { friendLeaderboardEnabled: boolean }>(`/api/children/${childId}/growth-settings`, { params });
export const updateChildGrowthSettings = (childId: number, data: { familyGroupId?: number; friendLeaderboardEnabled: boolean }) =>
  http.put<unknown, { friendLeaderboardEnabled: boolean }>(`/api/children/${childId}/growth-settings`, data);

export const getSystemConfig = () => http.get<unknown, SystemConfig>('/api/system/config');
export const updateSystemConfig = (data: SystemConfig) => http.put<unknown, SystemConfig>('/api/system/config', data);

export const getXiaotiancaiDeviceTestApplication = () =>
  http.get<unknown, XiaotiancaiDeviceTestEmailPreview>('/api/xiaotiancai/device-test-application');

export const sendXiaotiancaiDeviceTestApplication = (data: {
  deviceModel: string;
  confirmed: boolean;
  expectedApkSha256: string;
  expectedReportSha256: string;
}) => http.post<unknown, XiaotiancaiDeviceTestEmailSubmission>('/api/xiaotiancai/device-test-application/send', data);

export interface AdminUser { unifiedUserId: string; username: string; channel: string; role: string; status: string; childCount: number; activeDeviceCount: number; subscriptionPlanCode?: string | null; hasAppProfile: boolean; applicationRoles?: string[]; }
export interface AdminPlanFeature { planCode: string; featureCode: string; enabled: boolean; }
export interface AdminPlanPayload { catalog: unknown; features: AdminPlanFeature[]; onlyVipFeature: string; }
export const getAdminUsers = () => http.get<unknown, { users: AdminUser[] }>('/api/admin/users');
export const setAdminUserStatus = (id: string, data: { status: 'active' | 'disabled'; reason?: string }) => http.put(`/api/admin/users/${encodeURIComponent(id)}/status`, data);
export const getAdminPlans = () => http.get<unknown, AdminPlanPayload>('/api/admin/plans');
export const setAdminPlanFeature = (planCode: string, featureCode: string, enabled: boolean) => http.put(`/api/admin/plans/${planCode}/features/${featureCode}`, { enabled });
export const bootstrapAdminCatalog = () => http.post('/api/admin/catalog/bootstrap', {});

export interface SubscriptionInfo { planCode: string; status: string; startsAt: string; expiresAt: string; updatedAt: string; }
export interface FamilySubscription { productCode: string; standardIncluded: boolean; vipWatchFaces: boolean; featureCode: string; subscription?: SubscriptionInfo | null; }
export interface CheckoutSession { id: string; amountCents: number; currency: string; paymentChannels: { code: string; name: string; status: string }[]; }
export interface PaymentOrder { paymentUrl: string; qrCodeUrl: string; status: string; }
export const getSubscription = () => http.get<unknown, FamilySubscription>('/api/subscription');
export const createSubscriptionCheckout = () => http.post<unknown, CheckoutSession>('/api/subscription/checkout', {});
export const createSubscriptionOrder = (checkoutId: string, channel: 'wechatpay' | 'alipay') => http.post<unknown, PaymentOrder>(`/api/subscription/checkout/${encodeURIComponent(checkoutId)}/order`, { channel });
