import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const source = fs.readFileSync(new URL('../../FamilyReward.Api/Program.cs', import.meta.url), 'utf8');
const script = source.split('app.MapGet("/watch", () =>')[1].split('<script>')[1].split('</script>')[0];
const challenge = { code: 'ABCD2345', deviceToken: 'private-fixture-token', qrModules: [[true, false], [false, true]] };
const storage = new Map();
let pollStatus = 'pending', failure = 0, created = 0;
const nodes = new Map();
const node = id => {
  if (!nodes.has(id)) nodes.set(id, { textContent: '', style: {}, classList: { toggle() {}, add() {}, remove() {} }, addEventListener() {},
    getContext: () => ({ fillRect() {} }), value: '', innerHTML: '' });
  return nodes.get(id);
};
let poll;
const fixtures = { score: { children: [{ id: 1, name: 'Fixture child', points: 2 }], updatedAt: new Date().toISOString() },
  rules: { rules: [] }, requests: { requests: [] }, settings: { watchFace: 'world' }, friends: {}, 'warm-moment-options': { parents: [] }, 'growth-report': {} };
const context = vm.createContext({
  URLSearchParams, console, Date, FormData,
  location: { search: '', href: 'https://example.test/watch' },
  localStorage: { getItem: k => storage.get(k) ?? null, setItem: (k, v) => storage.set(k, v), removeItem: k => storage.delete(k) },
  document: { getElementById: node, querySelectorAll: () => [], hidden: false },
  navigator: { userAgent: 'Fixture H5' },
  window: { addEventListener() {} }, history: { replaceState() {}, pushState() {} },
  requestAnimationFrame: action => action(), setInterval: action => { poll = action; },
  fetch: async (url, options = {}) => {
    if (failure) return { ok: false, status: failure, json: async () => ({ error: 'fixture failure' }) };
    let payload;
    if (url === '/api/watch/pairing') {
      if (options.method === 'POST') { created++; payload = challenge; }
      else { assert.equal(options.headers['X-Watch-Device-Token'], challenge.deviceToken); payload = { status: pollStatus }; }
    } else { payload = fixtures[url.split('/').pop().split('?')[0]]; }
    return { ok: true, status: 200, json: async () => payload };
  }
});
vm.runInContext(script, context);
await new Promise(resolve => setImmediate(resolve));
assert.equal(created, 1);
assert.equal(nodes.get('pair-code').textContent, 'ABCD 2345');
assert(storage.has('happylife_watch_pending_pairing'));
await poll();
assert(!storage.has('happylife_watch_device_token'));
failure = 500; await poll();
assert(storage.has('happylife_watch_pending_pairing'));
failure = 0; pollStatus = 'approved'; await poll();
assert.equal(storage.get('happylife_watch_device_token'), challenge.deviceToken);
assert(!storage.has('happylife_watch_pending_pairing'));
assert.equal(nodes.get('child-name').textContent, 'Fixture child');
failure = 500; await vm.runInContext('load()', context);
assert.equal(storage.get('happylife_watch_device_token'), challenge.deviceToken);
assert.equal(nodes.get('pair-start').textContent, '重新连接');
assert.equal(nodes.get('bind-sub').textContent, '设备绑定已保留，请检查网络');
failure = 401; await vm.runInContext('load()', context);
assert(!storage.has('happylife_watch_device_token'));
failure = 0; await vm.runInContext('beginPairing()', context);
pollStatus = 'expired'; await poll();
assert.equal(nodes.get('pair-code').textContent, '');
assert.equal(nodes.get('pair-qr').style.display, 'none');
console.log('PASS: H5 displays code/QR, pending/offline token retention, approval enters child page, 500 keeps binding, 401 clears binding, expiry hides QR');
