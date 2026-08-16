export interface AgentStreamEvent {
  type: 'stream.start' | 'stream.delta' | 'stream.done' | 'stream.error';
  payload?: {
    delta?: string;
    channel?: string;
    message?: string;
  };
}

export async function consumeAgentEventStream(
  stream: ReadableStream<Uint8Array>,
  onEvent: (event: AgentStreamEvent) => void,
): Promise<void> {
  const reader = stream.getReader();
  const decoder = new TextDecoder();
  let buffer = '';
  let completed = false;

  const consumeFrames = (flush = false) => {
    buffer = buffer.replace(/\r\n/g, '\n');
    const frames = buffer.split('\n\n');
    buffer = flush ? '' : frames.pop() || '';
    for (const frame of frames) {
      const raw = frame
        .split('\n')
        .filter((line) => line.trimStart().startsWith('data:'))
        .map((line) => line.replace(/^\s*data:\s?/, ''))
        .join('\n')
        .trim();
      if (!raw || raw === '[DONE]') continue;
      const event = JSON.parse(raw) as AgentStreamEvent;
      onEvent(event);
      if (event.type === 'stream.done') completed = true;
      if (event.type === 'stream.error') {
        throw new Error(event.payload?.message || '智能体服务响应失败');
      }
    }
  };

  while (true) {
    const { value, done } = await reader.read();
    if (done) break;
    buffer += decoder.decode(value, { stream: true });
    consumeFrames();
  }
  buffer += decoder.decode();
  if (buffer.trim()) {
    buffer += '\n\n';
    consumeFrames(true);
  }
  if (!completed) throw new Error('智能体连接已中断，请重试');
}
