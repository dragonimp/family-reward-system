import { useEffect, type ReactNode } from 'react';
import { useLocation, Navigate } from 'react-router-dom';
import { useAuth } from '../contexts/AuthContext';

export default function IdentityGate({ children }: { children: ReactNode }) {
  const { appProfile, profileReady } = useAuth();
  const location = useLocation();

  useEffect(() => {
    if (profileReady && appProfile?.role === 'child' && location.pathname !== '/identity') {
      window.location.replace('/watch');
    }
  }, [appProfile?.role, location.pathname, profileReady]);

  if (!profileReady) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-[#F7F9FC] text-gray-500">
        正在读取身份...
      </div>
    );
  }

  if (!appProfile || appProfile.needsRole || !appProfile.role) {
    return <Navigate to="/identity" replace state={{ from: location }} />;
  }

  if (appProfile.role === 'child') {
    return (
      <div className="min-h-screen flex items-center justify-center bg-[#F7F9FC] text-gray-500">
        正在进入手表端...
      </div>
    );
  }

  return <>{children}</>;
}
