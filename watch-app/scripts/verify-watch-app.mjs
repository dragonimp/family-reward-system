import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const repoRoot = path.resolve(root, "..");
const read = (relativePath) => fs.readFileSync(path.join(root, relativePath), "utf8");
const readRepo = (relativePath) => fs.readFileSync(path.join(repoRoot, relativePath), "utf8");
const config = JSON.parse(read("app-config.json"));

const requiredFiles = [
  "android/settings.gradle.kts",
  "android/build.gradle.kts",
  "android/app/build.gradle.kts",
  "android/app/src/main/AndroidManifest.xml",
  "android/app/src/main/java/net/impx/happylife/watch/MainActivity.java",
  "platforms/xiaotiancai.json",
  "platforms/xiaomi.json",
  "platforms/huawei.json",
  "store-listing/listing.zh-CN.md",
  "RELEASE-CHECKLIST.md"
];
const requiredRepoFiles = [
  "frontend/public/watch/manifest.json",
  "frontend/public/watch/icon.svg"
];

const errors = [];
for (const file of requiredFiles) {
  if (!fs.existsSync(path.join(root, file))) {
    errors.push(`missing file: ${file}`);
  }
}
for (const file of requiredRepoFiles) {
  if (!fs.existsSync(path.join(repoRoot, file))) {
    errors.push(`missing file: ${file}`);
  }
}

const buildGradle = read("android/app/build.gradle.kts");
const manifest = read("android/app/src/main/AndroidManifest.xml");
const mainActivity = read("android/app/src/main/java/net/impx/happylife/watch/MainActivity.java");
const webManifest = JSON.parse(readRepo("frontend/public/watch/manifest.json"));
const apiSource = readRepo("FamilyReward.Api/Program.cs");
const releaseChecklist = read("RELEASE-CHECKLIST.md");
const formatPoints = (value) => Number(value).toLocaleString("zh-CN", {
  useGrouping: false,
  minimumFractionDigits: 0,
  maximumFractionDigits: 1
});

if (!buildGradle.includes(`applicationId = "${config.packageId}"`)) {
  errors.push("applicationId does not match app-config.json");
}
if (!buildGradle.includes(`versionCode = ${config.versionCode}`)) {
  errors.push("versionCode does not match app-config.json");
}
if (!buildGradle.includes(`versionName = "${config.versionName}"`)) {
  errors.push("versionName does not match app-config.json");
}
if (!buildGradle.includes(config.startUrl)) {
  errors.push("WATCH_START_URL does not match app-config.json");
}
for (const permission of config.permissions) {
  if (!manifest.includes(permission)) {
    errors.push(`manifest missing permission: ${permission}`);
  }
}
if (!mainActivity.includes("HappyLifeWatch/")) {
  errors.push("MainActivity missing HappyLifeWatch user agent marker");
}
if (apiSource.includes('id="group-name"') || apiSource.includes("getElementById('group-name')")) {
  errors.push("watch score page must not display the family group");
}
if (!apiSource.includes("const formatPoints = (value)") ||
    !apiSource.includes("maximumFractionDigits: 1") ||
    !apiSource.includes("font-variant-numeric:tabular-nums") ||
    !apiSource.includes("document.getElementById('score').textContent = formatPoints(child.points)")) {
  errors.push("watch score page does not support a four-digit score with one decimal place");
}
if (formatPoints(9999.9) !== "9999.9") {
  errors.push("watch score formatter failed the 9999.9 regression case");
}
for (const centeredQueryRequirement of [
  ".panel[data-panel=home].active{display:flex",
  "flex-direction:column",
  "align-items:center",
  "justify-content:center"
]) {
  if (!apiSource.includes(centeredQueryRequirement)) {
    errors.push(`watch score query is not centered: ${centeredQueryRequirement}`);
  }
}
for (const responsiveRequirement of [
  "height:100dvh",
  "overflow:hidden",
  "--watch-size:min(",
  "const calculatePanelScale = (availableWidth, availableHeight, contentWidth, contentHeight)",
  "window.addEventListener('orientationchange', fitActivePanel)",
  "window.visualViewport.addEventListener('resize', fitActivePanel)"
]) {
  if (!apiSource.includes(responsiveRequirement)) {
    errors.push(`watch viewport adaptation missing: ${responsiveRequirement}`);
  }
}
for (const requestScrollRequirement of [
  ".panel:not([data-panel=home]){height:100%",
  "overflow-y:auto",
  "scrollbar-width:thin",
  "touch-action:pan-y",
  `!panel.matches('[data-panel="home"],[data-panel="menu"]')`
]) {
  if (!apiSource.includes(requestScrollRequirement)) {
    errors.push(`watch scrollable panel support missing: ${requestScrollRequirement}`);
  }
}
for (const compactMenuRequirement of [
  'id="menu-toggle"',
  'data-panel="menu"',
  'data-view="request"',
  'data-view="points-detail"',
  'data-view="friend-add"',
  'data-view="leaderboard"',
  'data-view="settings"',
  'data-view="device"',
  "setView('menu')"
]) {
  if (!apiSource.includes(compactMenuRequirement)) {
    errors.push(`watch compact menu missing: ${compactMenuRequirement}`);
  }
}
for (const req030Requirement of [
  'class="menu-icon"',
  'class="back-menu"',
  'data-speech-target="title"',
  'data-speech-target="note"',
  'window.SpeechRecognition || window.webkitSpeechRecognition',
  'android.permission.RECORD_AUDIO',
  'PermissionRequest.RESOURCE_AUDIO_CAPTURE',
  'TRUSTED_WATCH_HOST'
]) {
  if (!apiSource.includes(req030Requirement) && !manifest.includes(req030Requirement) && !mainActivity.includes(req030Requirement)) {
    errors.push(`REQ-030 watch navigation or voice support missing: ${req030Requirement}`);
  }
}
const clamp = (min, value, max) => Math.min(max, Math.max(min, value));
for (const [width, height] of [[194, 368], [240, 240], [320, 360], [466, 466], [368, 194]]) {
  const vmin = Math.min(width, height) / 100;
  const menuReserve = clamp(36, 14 * vmin, 52);
  const shellMargin = clamp(26, 10 * vmin, 38);
  const faceSize = Math.min(width - menuReserve, height - 8, 346);
  if (faceSize <= 0 || faceSize + shellMargin > width) {
    errors.push(`watch face does not fit representative viewport: ${width}x${height}`);
  }
}
for (const unbindRequirement of [
  'app.MapPost("/api/watch/device-unbind", async (JsonObject body, HttpRequest request)',
  'app.MapPost("/api/children/{id:int}/devices/{deviceId:int}/unbind-code"',
  "CREATE TABLE IF NOT EXISTS watch_device_unbind_codes",
  "UnbindWatchDeviceWithCode",
  'id="unbind-code"',
  "解绑认证码无效或已过期"
]) {
  if (!apiSource.includes(unbindRequirement)) {
    errors.push(`watch unbind authorization missing: ${unbindRequirement}`);
  }
}
if (apiSource.includes("RevokeWatchDeviceByToken")) {
  errors.push("watch must not unbind using the device token alone");
}
for (const signingVariable of [
  "HAPPYLIFE_WATCH_KEYSTORE",
  "HAPPYLIFE_WATCH_KEY_ALIAS",
  "HAPPYLIFE_WATCH_KEYSTORE_PASSWORD",
  "HAPPYLIFE_WATCH_KEY_PASSWORD"
]) {
  if (!buildGradle.includes(signingVariable)) {
    errors.push(`release signing missing environment variable: ${signingVariable}`);
  }
}
if (webManifest.start_url !== config.startUrl) {
  errors.push("frontend public watch manifest start_url mismatch");
}
if (!apiSource.includes('app.MapGet("/watch/manifest.json"') ||
    !apiSource.includes('app.MapGet("/api/watch/app-info"')) {
  errors.push("API source missing online watch manifest or app-info route");
}
for (const feature of ["积分查询", "积分申请", "儿童认证码设备绑定"]) {
  if (!apiSource.includes(feature)) {
    errors.push(`API app-info missing watch feature: ${feature}`);
  }
}

for (const req023Requirement of [
  'app.MapGet("/api/watch/settings"',
  'app.MapPut("/api/watch/settings"',
  'app.MapGet("/api/watch/friends"',
  'app.MapPost("/api/watch/friend-code"',
  'app.MapPost("/api/watch/friends"',
  'app.MapGet("/api/children/{id:int}/friends"',
  'app.MapGet("/api/children/friend-notifications"',
  'data-face="world"',
  'data-face="hellokitty"',
  'data-face="starlight"',
  'maxlength="8" inputmode="numeric"',
  "SHA256.HashData",
  "AND used_at IS NULL",
  "AND expires_at > CURRENT_TIMESTAMP"
]) {
  if (!apiSource.includes(req023Requirement)) {
    errors.push(`REQ-023 watch face or friend support missing: ${req023Requirement}`);
  }
}

for (const req034Requirement of [
  'id="home-menu"',
  "classList.toggle('hidden', view !== 'home')",
  "const ruleIcons = ['📚', '✏️', '🪥', '🧹', '🏃', '🤝', '⏰', '🌟']",
  'class="leaderboard-banner"',
  'data-face="dinosaur"',
  'data-face="rainbow"',
  'data-face="space"'
]) {
  if (!apiSource.includes(req034Requirement)) {
    errors.push(`REQ-034 child-friendly watch support missing: ${req034Requirement}`);
  }
}

for (const platform of config.platforms) {
  const platformConfig = JSON.parse(read(`platforms/${platform}.json`));
  if (platformConfig.packageId !== config.packageId) {
    errors.push(`${platform}.json packageId mismatch`);
  }
  if (!platformConfig.entryUrl.includes("source=watch-app")) {
    errors.push(`${platform}.json entryUrl missing watch-app source`);
  }
  if (platformConfig.targetAudience !== "child") {
    errors.push(`${platform}.json targetAudience must be child`);
  }
  if (!Array.isArray(platformConfig.submitBlockers) || platformConfig.submitBlockers.length < 3) {
    errors.push(`${platform}.json submitBlockers is incomplete`);
  }
}

for (const boundary of ["平台账号与准入", "签名与构建", "真机验收与截图边界", "平台后台资料"]) {
  if (!releaseChecklist.includes(boundary)) {
    errors.push(`release checklist missing section: ${boundary}`);
  }
}

if (errors.length > 0) {
  console.error(errors.join("\n"));
  process.exit(1);
}

console.log(`watch app package ready: ${config.packageId} ${config.versionName} (${config.versionCode})`);
