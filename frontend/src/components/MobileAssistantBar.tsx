import { useEffect, useRef, useState } from 'react';
import { streamAgent } from '../services/agentStream';

interface ChatMessage {
  role: 'user' | 'assistant';
  content: string;
}

export default function MobileAssistantBar() {
  const [chatMode, setChatMode] = useState(false);
  const [input, setInput] = useState('');
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [sending, setSending] = useState(false);
  const [streamedText, setStreamedText] = useState('');
  const [listening, setListening] = useState(false);
  const recognitionRef = useRef<any>(null);
  const abortRef = useRef<AbortController | null>(null);
  const listRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    listRef.current?.scrollTo({ top: listRef.current.scrollHeight, behavior: 'smooth' });
  }, [messages, sending, streamedText]);

  useEffect(() => () => {
    recognitionRef.current?.abort?.();
    abortRef.current?.abort();
  }, []);

  const appendError = (content: string) => {
    setChatMode(true);
    setMessages((current) => [...current, { role: 'assistant', content }]);
  };

  const startVoice = () => {
    setChatMode(true);
    const SpeechRecognition = (window as any).SpeechRecognition || (window as any).webkitSpeechRecognition;
    if (!SpeechRecognition) {
      appendError('当前浏览器不支持语音识别，请输入文字。');
      return;
    }
    try {
      recognitionRef.current?.abort?.();
      const recognition = new SpeechRecognition();
      recognitionRef.current = recognition;
      recognition.lang = 'zh-CN';
      recognition.interimResults = false;
      recognition.maxAlternatives = 1;
      recognition.onstart = () => setListening(true);
      recognition.onresult = (event: any) => {
        const text = event.results?.[0]?.[0]?.transcript || '';
        if (text) setInput(text);
      };
      recognition.onerror = (event: any) => {
        const denied = event?.error === 'not-allowed' || event?.error === 'service-not-allowed';
        appendError(denied ? '麦克风权限未开启，请在浏览器设置中允许访问麦克风。' : '语音识别失败，请重试或输入文字。');
      };
      recognition.onend = () => setListening(false);
      recognition.start();
    } catch {
      setListening(false);
      appendError('无法启动语音识别，请检查麦克风权限。');
    }
  };

  const send = async () => {
    const prompt = input.trim();
    if (!prompt || sending) return;
    setMessages((current) => [...current, { role: 'user', content: prompt }]);
    setInput('');
    setChatMode(true);
    setSending(true);
    setStreamedText('');
    const controller = new AbortController();
    abortRef.current = controller;
    let answer = '';
    try {
      await streamAgent({ prompt }, (event) => {
        if (event.type !== 'stream.delta' || !event.payload?.delta) return;
        answer += event.payload.delta;
        setStreamedText(answer);
      }, controller.signal);
      if (!answer.trim()) throw new Error('智能体没有返回内容');
      setMessages((current) => [...current, { role: 'assistant', content: answer.trim() }]);
    } catch (error) {
      const aborted = error instanceof Error && error.name === 'AbortError';
      const content = aborted ? answer.trim() || '已停止生成' : error instanceof Error ? error.message : '智能体调用失败';
      setMessages((current) => [...current, { role: 'assistant', content }]);
    } finally {
      abortRef.current = null;
      setStreamedText('');
      setSending(false);
    }
  };

  const composer = (
    <div className="grid grid-cols-[1fr_44px] items-center gap-2 border-t border-gray-200 bg-white px-3 py-2 pb-[max(8px,env(safe-area-inset-bottom))]">
      <input
        value={input}
        onChange={(event) => setInput(event.target.value)}
        onFocus={() => setChatMode(true)}
        onKeyDown={(event) => { if (event.key === 'Enter') void send(); }}
        placeholder={listening ? '正在听...' : '输入家庭积分指令'}
        className="h-10 min-w-0 rounded-md border border-gray-300 bg-gray-50 px-3 text-sm focus:border-[#4A90D9] focus:bg-white focus:outline-none"
        aria-label="输入家庭积分指令"
      />
      <button
        type="button"
        onClick={() => sending ? abortRef.current?.abort() : input.trim() ? void send() : startVoice()}
        className={`grid h-10 w-10 place-items-center rounded-full text-lg text-white ${sending || listening ? 'bg-red-600' : 'bg-[#4A90D9]'}`}
        aria-label={sending ? '停止生成' : input.trim() ? '发送' : '语音输入'}
      >
        {sending ? '■' : input.trim() ? '↑' : '🎙'}
      </button>
    </div>
  );

  if (chatMode) {
    return (
      <section className="fixed inset-0 z-[70] flex flex-col bg-[#F7F9FC] lg:hidden" aria-label="家庭积分应用对话">
        <header className="flex min-h-14 items-center justify-between border-b border-gray-200 bg-white px-4 pt-[env(safe-area-inset-top)]">
          <h2 className="text-base font-semibold text-gray-900">家庭积分应用</h2>
          <button type="button" onClick={() => setChatMode(false)} className="grid h-9 w-9 place-items-center rounded-md text-2xl text-gray-500 hover:bg-gray-100" aria-label="返回仪表盘">×</button>
        </header>
        <div ref={listRef} className="flex-1 space-y-3 overflow-y-auto px-4 py-4">
          {messages.length === 0 && <p className="py-12 text-center text-sm text-gray-400">请输入家庭积分相关指令</p>}
          {messages.map((message, index) => (
            <div key={`${message.role}-${index}`} className={`flex ${message.role === 'user' ? 'justify-end' : 'justify-start'}`}>
              <p className={`max-w-[86%] whitespace-pre-wrap rounded-md px-3 py-2 text-sm leading-6 ${message.role === 'user' ? 'bg-[#4A90D9] text-white' : 'border border-gray-200 bg-white text-gray-700'}`}>{message.content}</p>
            </div>
          ))}
          {sending && (
            <div className="flex justify-start">
              <p className="max-w-[86%] whitespace-pre-wrap rounded-md border border-gray-200 bg-white px-3 py-2 text-sm leading-6 text-gray-700">
                {streamedText || '正在连接智能体...'}
              </p>
            </div>
          )}
        </div>
        {composer}
      </section>
    );
  }

  return <nav className="lg:hidden" aria-label="移动端智能体操作栏">{composer}</nav>;
}
