import { useCallback, useEffect, useRef, useState } from 'react';
import { getSystemConfig, updateSystemConfig, invokeAgent } from '../services';
import type { AgentInvokeResponse, SystemConfig } from '../types';

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
    endpoint: '',
    apiKey: '',
    model: 'gpt-4o-mini',
    timeout_seconds: 20,
    systemPrompt: '你是家加分智能助手，输出简短可执行建议。',
  },
};

export default function Settings() {
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [testing, setTesting] = useState(false);
  const [config, setConfig] = useState<SystemConfig>(defaultConfig);
  const [testPrompt, setTestPrompt] = useState('给我一个根据孩子表现自动扣分/加分的建议');
  const [agentResult, setAgentResult] = useState<unknown>(null);
  const [agentError, setAgentError] = useState('');
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

  const runAgentTest = async () => {
    try {
      setTesting(true);
      setAgentError('');
      setAgentResult(null);
      const result = await invokeAgent({
        prompt: testPrompt,
        payload: {
          model: config.agent.model,
          timeout_seconds: config.agent.timeout_seconds,
          messages: [
            { role: 'system', content: config.agent.systemPrompt },
            { role: 'user', content: testPrompt },
          ],
        },
      });
      if (result.ok) {
        setAgentResult(result.response);
      } else {
        setAgentError(result.error || '调用失败');
      }
    } catch (err) {
      setAgentError((err as Error).message || '测试失败');
      setAgentResult(null);
      console.error(err);
    } finally {
      setTesting(false);
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
            <label className="block text-sm font-medium text-gray-700 mb-1">服务地址（API）</label>
            <input
              type="text"
              value={config.agent.endpoint}
              onChange={(e) => {
                updateConfig((draft) => {
                  draft.agent.endpoint = e.target.value;
                });
              }}
              placeholder="https://api.example.com/v1/chat/completions"
              className="w-full px-3 py-2 border border-gray-300 rounded-lg"
            />
          </div>
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">API Key</label>
            <input
              type="password"
              value={config.agent.apiKey}
              onChange={(e) => {
                updateConfig((draft) => {
                  draft.agent.apiKey = e.target.value;
                });
              }}
              placeholder="sk-..."
              className="w-full px-3 py-2 border border-gray-300 rounded-lg"
            />
          </div>
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">模型</label>
            <input
              type="text"
              value={config.agent.model}
              onChange={(e) => {
                updateConfig((draft) => {
                  draft.agent.model = e.target.value;
                });
              }}
              className="w-full px-3 py-2 border border-gray-300 rounded-lg"
              placeholder="gpt-4o-mini"
            />
          </div>
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">超时（秒）</label>
            <input
              type="number"
              min={5}
              value={config.agent.timeout_seconds}
              onChange={(e) => {
                updateConfig((draft) => {
                  draft.agent.timeout_seconds = parseInt(e.target.value, 10) || 20;
                });
              }}
              className="w-full px-3 py-2 border border-gray-300 rounded-lg"
            />
          </div>
          <div className="sm:col-span-2">
            <label className="block text-sm font-medium text-gray-700 mb-1">系统提示词</label>
            <div className="flex flex-col gap-2 sm:flex-row sm:items-start">
              <textarea
                value={config.agent.systemPrompt}
                onChange={(e) => {
                  updateConfig((draft) => {
                    draft.agent.systemPrompt = e.target.value;
                  });
                }}
                rows={3}
                className="flex-1 px-3 py-2 border border-gray-300 rounded-lg"
              />
              <button
                type="button"
                onClick={() => startSpeechInput((text) => {
                  updateConfig((draft) => {
                    draft.agent.systemPrompt = `${draft.agent.systemPrompt ? `${draft.agent.systemPrompt}\n` : ''}${text}`;
                  });
                })}
                className="w-full rounded-lg border border-[#4A90D9] px-3 py-2 text-sm text-[#4A90D9] sm:w-auto"
              >
                🎤 输入
              </button>
            </div>
          </div>
        </div>
      </section>

      {/* 测试调用 */}
      <section className="rounded-lg border border-gray-200 bg-white p-4 sm:p-5">
        <h3 className="mb-4 text-base font-semibold text-gray-800 sm:text-lg">🧪 服务测试</h3>
        <div className="space-y-3">
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">测试提示词</label>
            <div className="flex flex-col gap-2 sm:flex-row sm:items-center">
              <textarea
                value={testPrompt}
                onChange={(e) => setTestPrompt(e.target.value)}
                rows={2}
                className="flex-1 px-3 py-2 border border-gray-300 rounded-lg"
              />
              <button
                type="button"
                onClick={() => startSpeechInput(setTestPrompt)}
                className="w-full rounded-lg border border-[#4A90D9] px-3 py-2 text-sm text-[#4A90D9] sm:w-auto"
              >
                🎤 输入
              </button>
            </div>
          </div>
          <div className="flex flex-wrap items-center gap-2 sm:gap-3">
            <button
              onClick={() => {
                if (!config.agent.enabled) {
                  showToast('请先开启智能体服务', 'error');
                  return;
                }
                stopSpeech();
                runAgentTest();
              }}
              className="px-4 py-2 bg-[#4A90D9] text-white rounded-lg text-sm"
            >
              {testing ? '调用中...' : '测试调用'}
            </button>
            <button
              onClick={saveConfig}
              disabled={saving}
              className="px-4 py-2 bg-[#F5A623] text-white rounded-lg text-sm disabled:opacity-60"
            >
              {saving ? '保存中...' : '保存配置'}
            </button>
            {speechInfo && <span className="text-sm text-gray-500 ml-2">{speechInfo}</span>}
          </div>
          {(agentError || agentResult !== null) && (
            <div className="bg-gray-50 border border-gray-200 rounded-lg p-3 text-sm">
              {agentError ? (
                <p className="text-red-500">{agentError}</p>
              ) : (
                <pre className="max-w-full overflow-x-auto whitespace-pre-wrap break-words text-gray-700">{JSON.stringify(agentResult, null, 2)}</pre>
              )}
            </div>
          )}
        </div>
      </section>
    </div>
  );
}
