import test from 'node:test';
import assert from 'node:assert/strict';
import { consumeAgentEventStream } from './src/services/agentSse.ts';

const encoder = new TextEncoder();

function eventStream(chunks: string[]) {
  return new ReadableStream({
    start(controller) {
      for (const chunk of chunks) controller.enqueue(encoder.encode(chunk));
      controller.close();
    },
  });
}

test('agent stream parses fragmented SSE deltas before completion', async () => {
  const stream = eventStream([
    'data: {"type":"stream.start","payload":{}}\n\n',
    'data: {"type":"stream.delta","payload":{"delta":"家长端',
    '流式","channel":"content"}}\n\n',
    'data: {"type":"stream.done","payload":{}}\n\n',
  ]);
  const events: string[] = [];
  await consumeAgentEventStream(stream, (event) => {
    if (event.payload?.delta) events.push(event.payload.delta);
  });
  assert.deepEqual(events, ['家长端流式']);
});

test('agent stream rejects a connection closed without stream.done', async () => {
  const stream = eventStream([
    'data: {"type":"stream.start","payload":{}}\n\n',
    'data: {"type":"stream.delta","payload":{"delta":"部分回答"}}\n\n',
  ]);
  await assert.rejects(
    consumeAgentEventStream(stream, () => {}),
    /智能体连接已中断/,
  );
});
