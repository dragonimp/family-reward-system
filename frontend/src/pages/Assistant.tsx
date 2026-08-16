import { AgentFreeWebAppChat } from '../components/agentfree-webapp/AgentFreeWebAppChat';
import { useAuth } from '../contexts/AuthContext';

export default function AssistantPage() {
  const { user } = useAuth();

  return (
    <div className="h-full min-h-0">
      <AgentFreeWebAppChat
        currentUser={user}
        routeBase="/assistant"
        webAppBotId="web"
        emptyAgentText="暂无可用的家庭积分应用智能体"
        welcomeTitle="家庭积分应用"
        welcomeHint="从左侧创建或选择会话"
        mobileWelcomeHint="打开右侧菜单创建或选择会话"
        storageKey="happylife.agentChat.sidebarWidth"
      />
    </div>
  );
}
