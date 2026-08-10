import type { AppUserProfile, AuthUser } from './types';

let cachedUser: AuthUser | null = null;
let cachedAppProfile: AppUserProfile | null = null;
const WEB_SDK_URL = '/auth/sdk/agentidentity-auth.js';
type WebSdkClient = {
  refresh: () => Promise<AuthUser | null>
}
let webSdkClientPromise: Promise<WebSdkClient> | null = null;

async function getWebSdkClient(): Promise<WebSdkClient> {
  if (!webSdkClientPromise) {
    webSdkClientPromise = import(/* @vite-ignore */ WEB_SDK_URL)
      .then(({ AgentIdentityAuthClient }) => new AgentIdentityAuthClient() as WebSdkClient);
  }
  return webSdkClientPromise;
}

export function readCurrentUser(): AuthUser | null {
  return cachedUser;
}

export function readCurrentAppProfile(): AppUserProfile | null {
  return cachedAppProfile;
}

export async function refreshCurrentUser(): Promise<AuthUser | null> {
  if (typeof window === 'undefined' || !window.location?.origin) {
    const response = await fetch('/auth/me', { credentials: 'include' });
    if (response.status === 204 || !response.ok) {
      cachedUser = null;
      return null;
    }
    cachedUser = await response.json();
    return cachedUser;
  }
  const user = await (await getWebSdkClient()).refresh();
  if (!user) {
    cachedUser = null;
    return null;
  }

  cachedUser = user;
  return cachedUser;
}

export async function refreshAppUserProfile(): Promise<AppUserProfile | null> {
  const response = await fetch('/api/user/profile?channel=pc', { credentials: 'include' });
  if (!response.ok) {
    cachedAppProfile = null;
    return null;
  }

  cachedAppProfile = await response.json();
  if (!cachedAppProfile) {
    throw new Error('身份保存失败');
  }
  return cachedAppProfile;
}

export async function saveAppUserRole(role: 'parent' | 'child'): Promise<AppUserProfile> {
  const response = await fetch('/api/user/profile', {
    method: 'POST',
    credentials: 'include',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ channel: 'pc', role }),
  });
  if (!response.ok) {
    const payload = await response.json().catch(() => ({}));
    throw new Error(payload.error || '身份保存失败');
  }

  cachedAppProfile = await response.json();
  if (!cachedAppProfile) {
    throw new Error('身份保存失败');
  }
  return cachedAppProfile;
}

function getCurrentReturnUrl() {
  if (window.location.pathname === '/login' || window.location.pathname.startsWith('/auth/')) {
    return `${window.location.origin}/dashboard`;
  }

  return `${window.location.origin}${window.location.pathname}${window.location.search}${window.location.hash}`;
}

export function getAuthLoginUrl(returnUrl = getCurrentReturnUrl()) {
  return `/auth/login?returnUrl=${encodeURIComponent(returnUrl)}`;
}

export function getUserCenterUrl(section: 'info' | 'password') {
  return `/auth/user-center?section=${section}`;
}

export function redirectToAuth(returnUrl = getCurrentReturnUrl()) {
  window.location.href = getAuthLoginUrl(returnUrl);
}

export function redirectToAuthLogout() {
  window.location.href = '/auth/logout';
}

export function clearAuthCookies() {
  cachedUser = null;
  cachedAppProfile = null;
  window.localStorage.removeItem('agentidentity.user');
}
