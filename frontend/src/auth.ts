import type { AuthUser } from './types';

let cachedUser: AuthUser | null = null;

export function readCurrentUser(): AuthUser | null {
  return cachedUser;
}

export async function refreshCurrentUser(): Promise<AuthUser | null> {
  const response = await fetch('/auth/me', { credentials: 'include' });
  if (response.status === 204 || !response.ok) {
    cachedUser = null;
    return null;
  }

  cachedUser = await response.json();
  return cachedUser;
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
  window.localStorage.removeItem('agentidentity.user');
}
