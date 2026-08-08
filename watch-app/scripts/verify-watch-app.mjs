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
