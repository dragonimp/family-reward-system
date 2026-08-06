import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from 'react';
import {
  clearAuthCookies,
  readCurrentAppProfile,
  readCurrentUser,
  redirectToAuth,
  redirectToAuthLogout,
  refreshAppUserProfile,
  refreshCurrentUser,
  saveAppUserRole,
} from '../auth';
import type { AppUserProfile, AuthContextType, AuthUser } from '../types';

const AuthContext = createContext<AuthContextType | null>(null);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<AuthUser | null>(() => readCurrentUser());
  const [appProfile, setAppProfile] = useState<AppUserProfile | null>(() => readCurrentAppProfile());
  const [ready, setReady] = useState(() => readCurrentUser() !== null);
  const [profileReady, setProfileReady] = useState(() => readCurrentAppProfile() !== null);

  const refresh = useCallback(async () => {
    const currentUser = await refreshCurrentUser();
    setUser(currentUser);
    if (currentUser) {
      const profile = await refreshAppUserProfile();
      setAppProfile(profile);
      setProfileReady(true);
    } else {
      setAppProfile(null);
      setProfileReady(true);
    }
    return currentUser;
  }, []);

  const refreshAppProfile = useCallback(async () => {
    const profile = await refreshAppUserProfile();
    setAppProfile(profile);
    setProfileReady(true);
    return profile;
  }, []);

  const selectAppRole = useCallback(async (role: 'parent' | 'child') => {
    const profile = await saveAppUserRole(role);
    setAppProfile(profile);
    setProfileReady(true);
    return profile;
  }, []);

  useEffect(() => {
    let disposed = false;

    refreshCurrentUser()
      .then((currentUser) => {
        if (disposed) return null;
        setUser(currentUser);
        return currentUser ? refreshAppUserProfile() : null;
      })
      .then((profile) => {
        if (!disposed) setAppProfile(profile);
      })
      .catch(() => {
        if (!disposed) {
          setUser(null);
          setAppProfile(null);
        }
      })
      .finally(() => {
        if (!disposed) {
          setReady(true);
          setProfileReady(true);
        }
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
    setAppProfile(null);
    redirectToAuthLogout();
  }, []);

  const value = useMemo<AuthContextType>(() => ({
    user,
    userId: user?.userId || user?.id || null,
    appProfile,
    profileReady,
    ready,
    login,
    logout,
    refresh,
    refreshAppProfile,
    selectAppRole,
    isAuthenticated: Boolean(user),
  }), [user, appProfile, profileReady, ready, login, logout, refresh, refreshAppProfile, selectAppRole]);

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth(): AuthContextType {
  const ctx = useContext(AuthContext);
  if (!ctx) {
    throw new Error('useAuth must be used within AuthProvider');
  }
  return ctx;
}
