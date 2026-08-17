import { useCallback, useEffect, useRef, useState } from 'react';
import { getSystemConfig, updateSystemConfig } from '../services';
import type { SystemConfig } from '../types';

type SpeechResultHandler = (value: string) => void;

const defaultConfig: SystemConfig = {
  voice: {
    enabled: false,
    recognitionLanguage: 'zh-CN',
    transcriptionProvider: 'browser',
  },
  agent: {
    enabled: false,
    webAppBotId: '',
    gatewayBaseUrl: 'https://agent.ai.impx.net',
  },
};

export default function Settings() {
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [config, setConfig] = useState<SystemConfig>(defaultConfig);
  const [speechInfo, setSpeechInfo] = useState('');
  const [toast, setToast] = useState<{ show: boolean; message: string; type: 'success' | 'error' }>(
    { show: false, message: '', type: 'success' }
  );
  const recognitionRef = useRef<null | { start: () => void; stop: () => void }>(null);

  const showToast = (message: string, type: 'success' | 'error' = 'success') => {
    setToast({ show: true, message, type });
    setTimeout(() => setToast({ show: false, message: '', type: 'success' }), 2500);
  };

  const loadConfig = useCallback(async () => {
    try {
      setLoading(true);
      const cfg = await getSystemConfig();
      setConfig(cfg);
    } catch (error) {
      setConfig(defaultConfig);
      console.error('读取配置失败', error);
      showToast('读取配置失败，使用本地默认配置', 'error');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    loadConfig();
  }, [loadConfig]);

  const updateConfig = (updater: (draft: SystemConfig) => void) => {
    const next = { ...config } as SystemConfig;
    updater(next);
    setConfig(next);
  };

  const startSpeechInput = useCallback((handler: SpeechResultHandler) => {
    const SpeechRecognition =
      (window as any).SpeechRecognition || (window as any).webkitSpeechRecognition;

    if (!SpeechRecognition) {
      setSpeechInfo('当前浏览器不支持语音识别');
      showToast('当前浏览器不支持语音识别', 'error');
      return;
    }

    try {
      const rec = new SpeechRecognition();
      recognitionRef.current = rec;
      rec.lang = config.voice.recognitionLanguage || 'zh-CN';
      rec.interimResults = false;
      rec.maxAlternatives = 1;
      rec.onresult = (event: any) => {
        const text = event.results?.[0]?.[0]?.transcript;
        if (text) {
          handler(text);
          setSpeechInfo('已识别完成');
        }
      };
      rec.onerror = () => {
        setSpeechInfo('语音识别失败，请重试');
        showToast('语音识别失败，请重试', 'error');
      };
      rec.onend = () => {
        setSpeechInfo('');
      };
      setSpeechInfo('正在监听... 说完后自动结束');
      rec.start();
    } catch (err) {
      setSpeechInfo('语音初始化失败');
      showToast('语音初始化失败', 'error');
      console.error(err);
    }
  }, [config.voice.recognitionLanguage]);

  const stopSpeech = () => {
    if (recognitionRef.current) {
      recognitionRef.current.stop();
      recognitionRef.current = null;
      setSpeechInfo('已停止');
    }
  };

  const saveConfig = async () => {
    try {
      setSaving(true);
      await updateSystemConfig(config);
      showToast('保存成功');
    } catch (error) {
      console.error('保存失败', error);
      showToast('保存失败', 'error');
    } finally {
      setSaving(false);
    }
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center py-20">
        <div className="text-center">
          <div className="inline-block animate-spin rounded-full h-10 w-10 border-4 border-[#4A90D9] border-t-transparent" />
          <p className="mt-4 text-gray-500">加载配置中...</p>
        </div>
      </div>
    );
  }

  return (
    <div className="space-y-4 pb-3 sm:space-y-6">
      {toast.show && (
        <div
          className={`fixed top-4 right-4 z-50 px-6 py-3 rounded-lg shadow-lg text-white transition-all
            ${toast.type === 'success' ? 'bg-green-500' : 'bg-red-500'}`}
        >
          {toast.message}
        </div>
      )}

      <div className="flex items-center justify-between gap-3">
        <div className="min-w-0">
          <h2 className="text-xl font-bold text-gray-900 sm:text-2xl">服务配置</h2>
          <p className="mt-1 text-sm text-gray-500">语音与智能体服务</p>
        </div>
        <button onClick={saveConfig} disabled={saving} className="shrink-0 rounded-lg bg-[#4A90D9] px-4 py-2 text-sm font-medium text-white disabled:opacity-60">
          {saving ? '保存中...' : '保存'}
        </button>
      </div>

      {/* 语音配置 */}
      <section className="rounded-lg border border-gray-200 bg-white p-4 sm:p-5">
        <h3 className="mb-4 text-base font-semibold text-gray-800 sm:text-lg">🎤 语音输入</h3>
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <label className="flex items-center gap-2">
            <input
              type="checkbox"
              checked={config.voice.enabled}
              onChange={(e) => {
                const next = e.target.checked;
                updateConfig((draft) => {
                  draft.voice.enabled = next;
                });
              }}
            />
            <span>开启语音输入配置</span>
          </label>
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">识别语言</label>
            <select
              value={config.voice.recognitionLanguage}
              onChange={(e) => {
                updateConfig((draft) => {
                  draft.voice.recognitionLanguage = e.target.value;
                });
              }}
              className="w-full px-3 py-2 border border-gray-300 rounded-lg"
            >
              <option value="zh-CN">中文（普通话）</option>
              <option value="en-US">English (US)</option>
              <option value="ja-JP">日本語</option>
            </select>
          </div>
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">转写引擎</label>
            <select
              value={config.voice.transcriptionProvider}
              onChange={(e) => {
                updateConfig((draft) => {
                  draft.voice.transcriptionProvider = e.target.value;
                });
              }}
              className="w-full px-3 py-2 border border-gray-300 rounded-lg"
            >
              <option value="browser">浏览器内置</option>
            </select>
          </div>
        </div>
        <p className="text-xs text-gray-500 mt-3">在配置页的文本字段中可使用麦克风按钮进行语音输入。</p>
      </section>

      {/* 智能体服务 */}
      <section className="rounded-lg border border-gray-200 bg-white p-4 sm:p-5">
        <h3 className="mb-4 text-base font-semibold text-gray-800 sm:text-lg">🤖 智能体服务</h3>
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <label className="flex items-center gap-2">
            <input
              type="checkbox"
              checked={config.agent.enabled}
              onChange={(e) => {
                updateConfig((draft) => {
                  draft.agent.enabled = e.target.checked;
                });
              }}
            />
            <span>启用智能体服务调用</span>
          </label>
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">WEBAP 入口标识</label>
            <input
              type="text"
              value={config.agent.webAppBotId}
              onChange={(e) => {
                updateConfig((draft) => {
                  draft.agent.webAppBotId = e.target.value;
                });
              }}
              placeholder="例如：web-jiajaifen-chat"
              className="w-full px-3 py-2 border border-gray-300 rounded-lg"
            />
          </div>
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">AgentFree 网关地址</label>
            <input
              type="text"
              value={config.agent.gatewayBaseUrl}
              onChange={(e) => {
                updateConfig((draft) => {
                  draft.agent.gatewayBaseUrl = e.target.value;
                });
              }}
              placeholder="https://agent.ai.impx.net"
              className="w-full px-3 py-2 border border-gray-300 rounded-lg"
            />
          </div>
        </div>
        <p className="mt-3 text-xs text-gray-500">应用通过 SDK 调用网关的 WEBAP 接口；模型、API Key、工作目录和 ACP 节点均由 AgentFree 智能体配置统一管理。</p>
      </section>
    </div>
  );
}
