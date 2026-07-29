import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from 'react';
import { clearAuthCookies, readCurrentUser, redirectToAuth, redirectToAuthLogout, refreshCurrentUser } from '../auth';
import type { AuthContextType, AuthUser } from '../types';

const AuthContext = createContext<AuthContextType | null>(null);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<AuthUser | null>(() => readCurrentUser());
  const [ready, setReady] = useState(() => readCurrentUser() !== null);

  const refresh = useCallback(async () => {
    const currentUser = await refreshCurrentUser();
    setUser(currentUser);
    return currentUser;
  }, []);

  useEffect(() => {
    let disposed = false;

    refreshCurrentUser()
      .then((currentUser) => {
        if (!disposed) setUser(currentUser);
      })
      .catch(() => {
        if (!disposed) setUser(null);
      })
      .finally(() => {
        if (!disposed) setReady(true);
      });

    return () => {
      disposed = true;
    };
  }, []);

  const login = useCallback((returnUrl?: string) => {
    redirectToAuth(returnUrl);
  }, []);

  const logout = useCallback(() => {
    clearAuthCookies();
    setUser(null);
    redirectToAuthLogout();
  }, []);

  const value = useMemo<AuthContextType>(() => ({
    user,
    userId: user?.userId || user?.id || null,
    ready,
    login,
    logout,
    refresh,
    isAuthenticated: Boolean(user),
  }), [user, ready, login, logout, refresh]);

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth(): AuthContextType {
  const ctx = useContext(AuthContext);
  if (!ctx) {
    throw new Error('useAuth must be used within AuthProvider');
  }
  return ctx;
}
