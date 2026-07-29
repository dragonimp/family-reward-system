import { useEffect, type ReactNode } from 'react';
import { useAuth } from '../contexts/AuthContext';

export default function ProtectedRoute({ children }: { children: ReactNode }) {
  const { isAuthenticated, ready, login } = useAuth();

  useEffect(() => {
    if (ready && !isAuthenticated) {
      login();
    }
  }, [ready, isAuthenticated, login]);

  if (!ready || !isAuthenticated) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-[#F7F9FC] text-gray-500">
        正在前往用户中心...
      </div>
    );
  }

  return <>{children}</>;
}
