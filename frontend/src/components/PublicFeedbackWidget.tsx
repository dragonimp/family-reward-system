import { useEffect } from 'react';
import { useAuth } from '../contexts/AuthContext';
import { sanitizeFeedbackLocation } from '../utils/feedbackPrivacy';

interface PublicFeedbackConfig {
  projectCode: string;
  projectName: string;
  projectCodename: string;
  appCode: string;
  clientId: string;
  endpoint: string;
  sourceApp: string;
  currentUser: {
    id: string;
    username: string;
    displayName: string;
    email: string;
    phone: string;
  } | null;
}

declare global {
  interface Window {
    AgentDashFeedback?: PublicFeedbackConfig;
  }
}

const PUBLIC_WIDGET_ID = 'atlas-public-feedback-widget';
const PUBLIC_WIDGET_URL = 'https://auth.ai.xmkurt.com/feedback-widget.js';

export default function PublicFeedbackWidget() {
  const { user } = useAuth();

  useEffect(() => {
    const sanitizedLocation = sanitizeFeedbackLocation(window.location.href);
    if (sanitizedLocation !== window.location.href) {
      window.history.replaceState(window.history.state, '', sanitizedLocation);
    }

    window.AgentDashFeedback = {
      projectCode: 'family-reward',
      projectName: '家加分',
      projectCodename: '家加分',
      appCode: '家加分',
      clientId: 'happylife.ai',
      endpoint: '/api/feedback',
      sourceApp: '家加分',
      currentUser: user ? {
        id: user.userId || user.id || '',
        username: user.username,
        displayName: user.displayName || user.username,
        email: user.email || '',
        phone: user.phoneNumber || '',
      } : null,
    };

    if (!document.getElementById(PUBLIC_WIDGET_ID)) {
      const script = document.createElement('script');
      script.id = PUBLIC_WIDGET_ID;
      script.src = PUBLIC_WIDGET_URL;
      script.async = true;
      document.body.appendChild(script);
    }
  }, [user]);

  return null;
}
