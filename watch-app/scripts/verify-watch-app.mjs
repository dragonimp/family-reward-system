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
  "store-listing/listing.zh-CN.md"
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
if (webManifest.start_url !== config.startUrl) {
  errors.push("frontend public watch manifest start_url mismatch");
}

for (const platform of config.platforms) {
  const platformConfig = JSON.parse(read(`platforms/${platform}.json`));
  if (platformConfig.packageId !== config.packageId) {
    errors.push(`${platform}.json packageId mismatch`);
  }
  if (!platformConfig.entryUrl.includes("source=watch-app")) {
    errors.push(`${platform}.json entryUrl missing watch-app source`);
  }
}

if (errors.length > 0) {
  console.error(errors.join("\n"));
  process.exit(1);
}

console.log(`watch app package ready: ${config.packageId} ${config.versionName} (${config.versionCode})`);
