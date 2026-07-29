import test from 'node:test';
import assert from 'node:assert/strict';
import config from './vite.config.ts';

test('development server proxies SDK auth endpoints to the API', () => {
  const proxy = config.server?.proxy;
  assert.ok(proxy && '/auth' in proxy);
  assert.equal(proxy?.['/auth']?.target, 'http://localhost:5102');
});
