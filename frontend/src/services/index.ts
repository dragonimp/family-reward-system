import http from './api';
import type { Child } from '../types';
import type { FamilyGroup, FamilyGroupInvite } from '../types';
import type { ChildAuthCode, ChildWatchDevices } from '../types';
import type { AgentInvokeRequest, AgentInvokeResponse, RewardParseRequest, RewardParseResponse, SystemConfig } from '../types';

export const getFamilyGroups = (params?: { userId?: string }) => http.get<unknown, FamilyGroup[]>('/api/family-groups', { params });
export const createFamilyGroup = (data: Partial<FamilyGroup> & { userId?: string }) => http.post<unknown, FamilyGroup>('/api/family-groups', data);
export const getFamilyGroupInvite = (id: number) => http.get<unknown, FamilyGroupInvite>(`/api/family-groups/${id}/invite`);
export const joinFamilyGroup = (data: { familyGroupId: number; userId?: string; role?: string; childId?: number }) => http.post('/api/family-groups/join', data);
export const linkFamilyGroupUser = (id: number, data: { userId: string; role?: string }) => http.put(`/api/family-groups/${id}/users`, data);

export const getChildren = (params?: { familyGroupId?: number; userId?: string }) => http.get('/api/children', { params });
export const getChild = (id: number) => http.get(`/api/children/${id}`);
export const createChild = (data: Partial<Child>) => http.post('/api/children', data);
export const updateChild = (id: number, data: Partial<Child>) => http.put(`/api/children/${id}`, data);
export const deleteChild = (id: number, params?: { familyGroupId?: number }) => http.delete(`/api/children/${id}`, { params });
export const generateChildAuthCode = (id: number, data?: { familyGroupId?: number; expiresInMinutes?: number }) =>
  http.post<unknown, ChildAuthCode>(`/api/children/${id}/auth-code`, data || {});
export const getChildWatchDevices = (id: number, params?: { familyGroupId?: number }) =>
  http.get<unknown, ChildWatchDevices>(`/api/children/${id}/devices`, { params });
export const revokeChildWatchDevice = (childId: number, deviceId: number, params?: { familyGroupId?: number }) =>
  http.delete(`/api/children/${childId}/devices/${deviceId}`, { params });

export const getTransactions = (params: any) => http.get('/api/transactions', { params });
export const createTransaction = (data: any) => http.post('/api/transactions', data);
export const deleteTransaction = (id: number, params?: { familyGroupId?: number }) => http.delete(`/api/transactions/${id}`, { params });

export const getRules = () => http.get('/api/rules');
export const createRule = (data: any) => http.post('/api/rules', data);
export const updateRule = (id: number, data: any) => http.put(`/api/rules/${id}`, data);
export const deleteRule = (id: number) => http.delete(`/api/rules/${id}`);

export const getChildStats = (params?: { familyGroupId?: number }) => http.get('/api/stats/dashboard', { params });
export const getLeaderboard = (params?: { familyGroupId?: number }) => http.get('/api/stats/leaderboard', { params });
export const getCategoryStats = (params?: { familyGroupId?: number }) => http.get('/api/stats/categories', { params });

export const getSystemConfig = () => http.get<unknown, SystemConfig>('/api/system/config');
export const updateSystemConfig = (data: SystemConfig) => http.put<unknown, SystemConfig>('/api/system/config', data);
export const invokeAgent = (data: AgentInvokeRequest) => http.post<unknown, AgentInvokeResponse>('/api/agent/invoke', data);
export const parseRewardVoice = (data: RewardParseRequest) => http.post<unknown, RewardParseResponse>('/api/agent/parse-reward', data);
