import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';

const source = readFileSync(new URL('../../FamilyReward.Api/PublicActivityIntroduction.cs', import.meta.url), 'utf8');
const script = source.match(/<script nonce="\{\{nonce\}\}">(.*?)<\/script>/s)[1];
for (const wechat of [true, false]) {
  let focused = 0, scrolled = 0;
  const guide = { hidden: true, focus: () => focused++, scrollIntoView: () => scrolled++ };
  const help = { hidden: true };
  const links = ['open-app', 'install'].map(id => ({ id, addEventListener(_, handler) { this.click = handler; } }));
  const timers = [];
  vm.runInNewContext(script, {
    navigator: { userAgent: wechat ? 'iPhone MicroMessenger/8.0' : 'iPhone Safari/605.1' },
    document: { hidden: false, querySelector: selector => ({ time: { dateTime: '' }, '#wechat-guide': guide, '#app-help': help })[selector], querySelectorAll: () => links },
    setTimeout: fn => timers.push(fn),
  });
  assert.equal(guide.hidden, !wechat, 'WeChat guidance is immediately visible');
  for (const link of links) {
    let prevented = false;
    link.click({ preventDefault() { prevented = true; } });
    assert.equal(prevented, wechat, 'App and install links guide WeChat and navigate normally elsewhere');
  }
  assert.equal(focused, wechat ? 2 : 0);
  assert.equal(scrolled, wechat ? 2 : 0);
  assert.equal(timers.length, wechat ? 0 : 1);
  timers.forEach(fn => fn());
  assert.equal(help.hidden, wechat);
}
assert.match(source, /class="secondary" href="\{\{enter\}\}"/);
assert.doesNotMatch(source, /querySelectorAll\([^)]*secondary/);
console.log('PASS: WeChat and Safari interaction checks; browser entry remains accessible');
