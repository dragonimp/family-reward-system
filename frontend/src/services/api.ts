import axios from 'axios';
import type { ApiResponse } from '../types';
import { readCurrentUser } from '../auth';

const API_BASE = import.meta.env.DEV ? 'http://localhost:5102' : '';

const http = axios.create({
  baseURL: API_BASE,
  timeout: 10000,
  withCredentials: true,
  headers: {
    'Content-Type': 'application/json',
  },
});

http.interceptors.request.use((config) => {
  const user = readCurrentUser();
  const userId = user?.userId || user?.id;
  if (userId) {
    config.headers['X-User-Id'] = userId;
  }
  return config;
});

// 响应拦截器 - Python后端返回原始JSON，不需要包装
http.interceptors.response.use(
  (response) => {
    return response.data;
  },
  (error) => {
    const message =
      error.response?.data?.message || error.message || '网络请求失败';
    console.error('API Error:', message);
    return Promise.reject(new Error(message));
  }
);

export default http;
