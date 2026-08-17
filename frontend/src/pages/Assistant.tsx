import { AgentFreeWebAppChat } from '../components/agentfree-webapp/AgentFreeWebAppChat';
import { getSystemConfig } from '../services';
import { useAuth } from '../contexts/AuthContext';
import { useEffect, useState } from 'react';

export default function AssistantPage() {
  const { user } = useAuth();
  const [webAppBotId, setWebAppBotId] = useState('');

  useEffect(() => {
    getSystemConfig().then((config) => {
      setWebAppBotId(config.agent.webAppBotId.trim());
    }).catch(() => {
      setWebAppBotId('');
    });
  }, []);

  if (!webAppBotId) {
    return <div className="flex h-full items-center justify-center text-sm text-gray-500">正在读取智能体入口配置...</div>;
  }

  return (
    <div className="h-full min-h-0">
      <AgentFreeWebAppChat
        currentUser={user}
        routeBase="/assistant"
        webAppBotId={webAppBotId}
        emptyAgentText="暂无可用的家庭积分应用智能体"
        welcomeTitle="家庭积分应用"
        welcomeHint="从左侧创建或选择会话"
        mobileWelcomeHint="打开右侧菜单创建或选择会话"
        storageKey="happylife.agentChat.sidebarWidth"
      />
    </div>
  );
}
