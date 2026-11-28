import { type ReactNode } from 'react';
import { useAuth } from '../contexts/AuthContext';

export default function IdentityGate({ children }: { children: ReactNode }) {
  const { appProfile, profileReady, refreshAppProfile } = useAuth();

  if (!profileReady) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-[#F7F9FC] text-gray-500">
        正在读取账号资料…
      </div>
    );
  }

  if (!appProfile) {
    return (
      <div className="min-h-screen flex flex-col items-center justify-center gap-4 bg-[#F7F9FC] text-gray-500">
        <p>账号资料读取失败，请重试。</p>
        <button type="button" className="rounded-lg bg-teal-700 px-4 py-2 text-white" onClick={() => void refreshAppProfile()}>重新加载</button>
      </div>
    );
  }

  return <>{children}</>;
}
