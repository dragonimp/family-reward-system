import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from 'react';
import { createFamilyGroup, getFamilyGroups } from '../services';
import type { FamilyGroup } from '../types';
import { useAuth } from './AuthContext';

interface FamilyGroupContextType {
  groups: FamilyGroup[];
  selectedGroupId: number | null;
  selectedGroup: FamilyGroup | null;
  loading: boolean;
  error: string | null;
  selectGroup: (id: number) => void;
  createGroup: (name: string) => Promise<FamilyGroup>;
  refreshGroups: () => Promise<void>;
}

const FamilyGroupContext = createContext<FamilyGroupContextType | null>(null);

export function FamilyGroupProvider({ children }: { children: ReactNode }) {
  const [groups, setGroups] = useState<FamilyGroup[]>([]);
  const [selectedGroupId, setSelectedGroupId] = useState<number | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const refreshGroups = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);
      const res = await getFamilyGroups();
      const nextGroups = Array.isArray(res) ? res : [];
      setGroups(nextGroups);
      setSelectedGroupId((current) => {
        if (current && nextGroups.some((group) => group.id === current)) return current;
        return nextGroups[0]?.id ?? null;
      });
    } catch (err) {
      console.error('家庭组加载失败:', err);
      setGroups([]);
      setSelectedGroupId(null);
      setError('家庭组加载失败');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    refreshGroups();
  }, [refreshGroups]);

  const selectGroup = useCallback((id: number) => {
    setSelectedGroupId(id);
  }, []);

  const createGroup = useCallback(async (name: string) => {
    const trimmed = name.trim();
    if (!trimmed) {
      throw new Error('请输入家庭组名称');
    }
    const created = await createFamilyGroup({ name: trimmed });
    setGroups((current) => [...current, created]);
    setSelectedGroupId(created.id);
    setError(null);
    return created;
  }, []);

  const selectedGroup = useMemo(
    () => groups.find((group) => group.id === selectedGroupId) ?? null,
    [groups, selectedGroupId],
  );

  const value = useMemo<FamilyGroupContextType>(() => ({
    groups,
    selectedGroupId,
    selectedGroup,
    loading,
    error,
    selectGroup,
    createGroup,
    refreshGroups,
  }), [groups, selectedGroupId, selectedGroup, loading, error, selectGroup, createGroup, refreshGroups]);

  return <FamilyGroupContext.Provider value={value}>{children}</FamilyGroupContext.Provider>;
}

export function useFamilyGroup(): FamilyGroupContextType {
  const ctx = useContext(FamilyGroupContext);
  if (!ctx) {
    throw new Error('useFamilyGroup must be used within FamilyGroupProvider');
  }
  return ctx;
}
