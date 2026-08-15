import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

test('parent shell keeps mobile navigation focused and safe-area aware', async () => {
  const [layout, styles, document] = await Promise.all([
    readFile(new URL('./src/components/Layout.tsx', import.meta.url), 'utf8'),
    readFile(new URL('./src/styles/global.css', import.meta.url), 'utf8'),
    readFile(new URL('./index.html', import.meta.url), 'utf8'),
  ]);

  assert.match(layout, /grid-cols-5/);
  assert.match(layout, /手机端主导航/);
  assert.match(layout, /role="dialog"/);
  assert.match(layout, /家庭管理/);
  assert.doesNotMatch(layout, /grid-cols-7/);
  assert.match(styles, /height:\s*100dvh/);
  assert.match(styles, /env\(safe-area-inset-bottom\)/);
  assert.match(document, /viewport-fit=cover/);
});

test('children management uses cards on phones and a table on larger screens', async () => {
  const page = await readFile(new URL('./src/pages/Children.tsx', import.meta.url), 'utf8');

  assert.match(page, /手机端卡片列表/);
  assert.match(page, /space-y-3 sm:hidden/);
  assert.match(page, /hidden sm:block/);
  assert.match(page, /grid grid-cols-4/);
});
