import { MessageOutlined } from '@ant-design/icons';
import { useNavigate } from 'react-router-dom';

export default function MobileAssistantBar() {
  const navigate = useNavigate();

  return (
    <div className="fixed inset-x-0 bottom-0 z-40 border-t border-gray-200 bg-white px-3 py-2 pb-[max(8px,env(safe-area-inset-bottom))] lg:hidden">
      <button
        type="button"
        onClick={() => navigate('/assistant')}
        className="flex h-11 w-full items-center gap-3 rounded-md border border-gray-300 bg-gray-50 px-4 text-left text-sm text-gray-600 shadow-sm"
        aria-label="打开家庭积分应用智能对话"
      >
        <MessageOutlined className="text-lg text-[#4A90D9]" />
        <span className="min-w-0 flex-1 truncate">与家庭积分应用对话</span>
        <span className="text-[#4A90D9]">打开</span>
      </button>
    </div>
  );
}
