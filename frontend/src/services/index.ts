import http from './api';
import type { Child } from '../types';

export const getChildren = () => http.get('/api/children');
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
