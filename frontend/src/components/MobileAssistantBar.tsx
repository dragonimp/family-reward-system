import { ClockCircleOutlined, MessageOutlined } from '@ant-design/icons';
import { useNavigate } from 'react-router-dom';

export default function MobileAssistantBar() {
  const navigate = useNavigate();

  return (
    <div className="fixed inset-x-0 bottom-0 z-40 grid grid-cols-2 gap-2 border-t border-gray-200 bg-white px-3 py-2 pb-[max(8px,env(safe-area-inset-bottom))] lg:hidden">
      <button
        type="button"
        onClick={() => navigate('/virtual-watch')}
        className="flex h-11 min-w-0 items-center justify-center gap-2 rounded-md border border-gray-300 bg-gray-50 px-3 text-sm text-gray-700 shadow-sm"
        aria-label="打开虚拟手表"
      >
        <ClockCircleOutlined className="shrink-0 text-lg text-[#2F7D4A]" />
        <span className="truncate">虚拟手表</span>
      </button>
      <button
        type="button"
        onClick={() => navigate('/assistant')}
        className="flex h-11 min-w-0 items-center justify-center gap-2 rounded-md border border-gray-300 bg-gray-50 px-3 text-sm text-gray-700 shadow-sm"
        aria-label="打开家庭积分应用智能对话"
      >
        <MessageOutlined className="text-lg text-[#4A90D9]" />
        <span className="truncate">智能对话</span>
      </button>
    </div>
  );
}
