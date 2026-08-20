import { execFileSync } from 'node:child_process';
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const output = resolve(root, 'docs/publishing/xiaotiancai/assets');
mkdirSync(output, { recursive: true });

const font = "'PingFang SC','Microsoft YaHei',sans-serif";
const esc = (value) => value.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
const text = (x, y, value, size = 14, color = '#193425', weight = 500, anchor = 'start') =>
  `<text x="${x}" y="${y}" font-family="${font}" font-size="${size}" font-weight="${weight}" fill="${color}" text-anchor="${anchor}">${esc(value)}</text>`;
const rounded = (x, y, width, height, fill, radius = 12, stroke = 'none') =>
  `<rect x="${x}" y="${y}" width="${width}" height="${height}" rx="${radius}" fill="${fill}" stroke="${stroke}"/>`;
const shell = (title, subtitle, body, accent = '#16643a') => `
<svg xmlns="http://www.w3.org/2000/svg" width="320" height="360" viewBox="0 0 320 360">
  <rect width="320" height="360" fill="#eef5ef"/>
  <rect width="320" height="72" fill="${accent}"/>
  ${text(20, 31, title, 20, '#ffffff', 700)}
  ${text(20, 54, subtitle, 12, '#eaf4ec', 500)}
  ${body}
</svg>`;

const assets = [
  {
    name: 'intro-01-bind',
    svg: shell('绑定孩子手表', '家长生成一次性认证码', `
      ${rounded(18, 92, 284, 226, '#ffffff', 16)}
      <circle cx="160" cy="132" r="28" fill="#dff0e3"/>
      <path d="M145 133l10 10 22-25" fill="none" stroke="#16643a" stroke-width="7" stroke-linecap="round" stroke-linejoin="round"/>
      ${text(160, 177, '输入 6 位儿童认证码', 17, '#193425', 700, 'middle')}
      ${rounded(42, 194, 236, 46, '#f4f7f4', 8, '#b9cdbd')}
      ${text(160, 223, '•  •  •  •  •  •', 18, '#75877a', 600, 'middle')}
      ${rounded(42, 254, 236, 44, '#16643a', 8)}
      ${text(160, 282, '绑定手表', 16, '#ffffff', 700, 'middle')}
      ${text(160, 340, '认证码一次有效 · 由家长管理', 12, '#5b7161', 500, 'middle')}
    `),
  },
  {
    name: 'intro-02-score',
    svg: shell('测试儿童的积分', '家庭奖励一目了然', `
      ${rounded(16, 90, 288, 120, '#ffffff', 16)}
      <circle cx="82" cy="150" r="43" fill="#fff4d6" stroke="#f3bd42" stroke-width="8"/>
      ${text(82, 147, '128', 28, '#7a5100', 800, 'middle')}
      ${text(82, 168, '积分', 12, '#7a5100', 600, 'middle')}
      ${text(146, 129, '今天也在进步', 17, '#193425', 700)}
      ${text(146, 155, '现金奖励  ¥20', 14, '#44604b', 600)}
      ${text(146, 181, '物品奖励  3 件', 14, '#44604b', 600)}
      ${rounded(16, 225, 138, 72, '#e4efff', 12)}
      ${text(85, 255, '积分申请', 16, '#1f538b', 700, 'middle')}
      ${text(85, 278, '选择规则提交', 12, '#42698f', 500, 'middle')}
      ${rounded(166, 225, 138, 72, '#ffe9e0', 12)}
      ${text(235, 255, '最近申请', 16, '#963f24', 700, 'middle')}
      ${text(235, 278, '查看审核状态', 12, '#975c48', 500, 'middle')}
      ${text(160, 333, '仅展示当前孩子自己的奖励', 12, '#5b7161', 500, 'middle')}
    `, '#315c9b'),
  },
  {
    name: 'intro-03-request',
    svg: shell('申请积分', '选择家长设置的奖励规则', `
      ${rounded(16, 88, 288, 62, '#ffffff', 12)}
      <circle cx="45" cy="119" r="18" fill="#fff0bd"/>${text(45, 125, '☀', 18, '#a26b00', 700, 'middle')}
      ${text(75, 113, '早睡早起', 15, '#193425', 700)}${text(75, 135, '按时作息', 12, '#637367', 500)}
      ${text(278, 125, '+10', 18, '#16643a', 800, 'end')}
      ${rounded(16, 160, 288, 62, '#ffffff', 12)}
      <circle cx="45" cy="191" r="18" fill="#dcecff"/>${text(45, 197, '书', 13, '#315c9b', 700, 'middle')}
      ${text(75, 185, '阅读 30 分钟', 15, '#193425', 700)}${text(75, 207, '养成阅读习惯', 12, '#637367', 500)}
      ${text(278, 197, '+8', 18, '#16643a', 800, 'end')}
      ${rounded(16, 232, 288, 62, '#ffffff', 12)}
      <circle cx="45" cy="263" r="18" fill="#ffe2d7"/>${text(45, 269, '包', 13, '#a34828', 700, 'middle')}
      ${text(75, 257, '整理书包', 15, '#193425', 700)}${text(75, 279, '自己的事情自己做', 12, '#637367', 500)}
      ${text(278, 269, '+5', 18, '#16643a', 800, 'end')}
      ${rounded(52, 308, 216, 38, '#16643a', 8)}${text(160, 333, '提交申请', 15, '#ffffff', 700, 'middle')}
    `, '#a34828'),
  },
  {
    name: 'intro-04-status',
    svg: shell('最近申请', '处理进度及时可见', `
      ${rounded(16, 92, 288, 72, '#ffffff', 12)}
      ${text(32, 119, '阅读 30 分钟', 15, '#193425', 700)}
      ${text(32, 143, '今天 18:20 · +8 积分', 12, '#637367', 500)}
      ${rounded(226, 110, 60, 30, '#fff0c9', 15)}${text(256, 130, '待审核', 12, '#835b00', 700, 'middle')}
      ${rounded(16, 176, 288, 72, '#ffffff', 12)}
      ${text(32, 203, '整理书包', 15, '#193425', 700)}
      ${text(32, 227, '昨天 20:05 · +5 积分', 12, '#637367', 500)}
      ${rounded(226, 194, 60, 30, '#dff0e3', 15)}${text(256, 214, '已通过', 12, '#16643a', 700, 'middle')}
      ${rounded(16, 260, 288, 72, '#ffffff', 12)}
      ${text(32, 287, '早睡早起', 15, '#193425', 700)}
      ${text(32, 311, '8月18日 · +10 积分', 12, '#637367', 500)}
      ${rounded(226, 278, 60, 30, '#f0f2f0', 15)}${text(256, 298, '已处理', 12, '#526157', 700, 'middle')}
    `, '#6f4f8b'),
  },
  {
    name: 'intro-05-voice',
    svg: shell('语音输入申请', '也可以随时改用键盘', `
      ${rounded(18, 92, 284, 218, '#ffffff', 16)}
      <circle cx="160" cy="153" r="48" fill="#e4efff"/>
      <rect x="148" y="121" width="24" height="48" rx="12" fill="#315c9b"/>
      <path d="M137 153c0 15 10 27 23 27s23-12 23-27M160 180v18M145 198h30" fill="none" stroke="#315c9b" stroke-width="5" stroke-linecap="round"/>
      ${text(160, 229, '“今天完成了阅读”', 17, '#193425', 700, 'middle')}
      ${text(160, 255, '识别结果可确认后再提交', 13, '#637367', 500, 'middle')}
      ${rounded(56, 270, 208, 34, '#315c9b', 8)}${text(160, 292, '确认文字', 14, '#ffffff', 700, 'middle')}
      ${text(160, 338, '仅主动点击时使用麦克风 · 不保存录音', 11, '#5b7161', 500, 'middle')}
    `, '#315c9b'),
  },
];

const icon = `
<svg xmlns="http://www.w3.org/2000/svg" width="148" height="148" viewBox="0 0 148 148">
  <rect width="148" height="148" fill="#16643a"/>
  <circle cx="74" cy="74" r="48" fill="#eef5ef"/>
  <path d="M50 78l15 15 34-40" fill="none" stroke="#16643a" stroke-width="12" stroke-linecap="round" stroke-linejoin="round"/>
  <path d="M53 8h42l7 22H46l7-22zm-7 110h56l-7 22H53l-7-22z" fill="#8fd19e"/>
</svg>`;

const writeAsset = (name, svg, width, height) => {
  const svgPath = resolve(output, `${name}.svg`);
  const pngPath = resolve(output, `${name}.png`);
  writeFileSync(svgPath, svg.trimStart(), 'utf8');
  execFileSync('rsvg-convert', ['-w', String(width), '-h', String(height), '-o', pngPath, svgPath]);
};

writeAsset('app-icon-148x148', icon, 148, 148);
for (const asset of assets) writeAsset(asset.name, asset.svg, 320, 360);
console.log(`Generated ${assets.length + 1} Xiaotiancai assets in ${output}`);
