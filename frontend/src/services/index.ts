import http from './api';
import type { Child } from '../types';
import type { FamilyGroup } from '../types';
import type { AgentInvokeRequest, AgentInvokeResponse, RewardParseRequest, RewardParseResponse, SystemConfig } from '../types';

export const getFamilyGroups = (params?: { userId?: string }) => http.get<unknown, FamilyGroup[]>('/api/family-groups', { params });
export const createFamilyGroup = (data: Partial<FamilyGroup> & { userId?: string }) => http.post<unknown, FamilyGroup>('/api/family-groups', data);
export const linkFamilyGroupUser = (id: number, data: { userId: string; role?: string }) => http.put(`/api/family-groups/${id}/users`, data);

export const getChildren = (params?: { familyGroupId?: number; userId?: string }) => http.get('/api/children', { params });
export const getChild = (id: number) => http.get(`/api/children/${id}`);
export const createChild = (data: Partial<Child>) => http.post('/api/children', data);
export const updateChild = (id: number, data: Partial<Child>) => http.put(`/api/children/${id}`, data);
export const deleteChild = (id: number) => http.delete(`/api/children/${id}`);

export const getTransactions = (params: any) => http.get('/api/transactions', { params });
export const createTransaction = (data: any) => http.post('/api/transactions', data);
export const deleteTransaction = (id: number) => http.delete(`/api/transactions/${id}`);

export const getRules = () => http.get('/api/rules');
export const createRule = (data: any) => http.post('/api/rules', data);
export const updateRule = (id: number, data: any) => http.put(`/api/rules/${id}`, data);
export const deleteRule = (id: number) => http.delete(`/api/rules/${id}`);

export const getChildStats = () => http.get('/api/stats/dashboard');
export const getLeaderboard = () => http.get('/api/stats/leaderboard');
export const getCategoryStats = () => http.get('/api/stats/categories');

export const getSystemConfig = () => http.get<unknown, SystemConfig>('/api/system/config');
export const updateSystemConfig = (data: SystemConfig) => http.put<unknown, SystemConfig>('/api/system/config', data);
export const invokeAgent = (data: AgentInvokeRequest) => http.post<unknown, AgentInvokeResponse>('/api/agent/invoke', data);
export const parseRewardVoice = (data: RewardParseRequest) => http.post<unknown, RewardParseResponse>('/api/agent/parse-reward', data);
