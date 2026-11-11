#!/usr/bin/env bash
set -euo pipefail
[[ $# == 2 ]] || { echo 'Usage: build-atlas-release.sh <version> <new-output-directory>' >&2; exit 2; }
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
atlas_root="${ATLAS_SOURCE_ROOT:-$root/../Atlas}"
[[ -f "$atlas_root/scripts/atlas-package-server.sh" ]] || { echo 'Atlas shared packager is required.' >&2; exit 2; }
[[ ! -e "$2" ]] || { echo 'Output directory must not exist.' >&2; exit 2; }
version="$1"
[[ "$version" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$ && "$version" != latest ]] || exit 2
stage="$(python3 "$root/scripts/release-temp.py" create family-atlas-build.)"
trap 'python3 "$root/scripts/release-temp.py" cleanup "$stage"' EXIT
app_code="$(node -e 'console.log(require(process.argv[1]).appCode)' "$root/deploy/atlas-release.json")"
shared_projects_root="${FAMILY_REWARD_SHARED_PROJECTS_ROOT:-$root/..}"
identity_root="$shared_projects_root/AgentIdentity"
green_login_commit="f4fa8f7323a4e904d564c6c27c28fa9290aa0d18"
git -C "$identity_root" merge-base --is-ancestor "$green_login_commit" HEAD || { echo 'AgentIdentity SDK does not include the green native login page.' >&2; exit 2; }
git -C "$identity_root" diff --quiet HEAD -- src/AgentIdentity.Sdk || { echo 'AgentIdentity SDK has uncommitted source changes.' >&2; exit 2; }
git -C "$identity_root" diff --quiet HEAD -- src/AgentIdentity.NativeClient || { echo 'AgentIdentity native client has uncommitted source changes.' >&2; exit 2; }
dotnet_args=(-p:UseSharedCompilation=false -m:1 -nr:false)
if [[ -n "${ATLAS_BUILD_WORK:-}" ]]; then dotnet_args+=(-p:UseArtifactsOutput=true -p:ArtifactsPath="$ATLAS_BUILD_WORK/family-publish"); fi
dotnet publish "$root/FamilyReward.Api/FamilyReward.Api.csproj" -c Release -r linux-x64 --self-contained false "${dotnet_args[@]}" -p:SharedProjectsRoot="$shared_projects_root" -o "$stage/api"
rsync -a --exclude=node_modules --exclude=dist "$root/frontend/" "$stage/frontend/"
mkdir -p "$stage/shared-sdk"
git -C "$shared_projects_root/AgentFree" archive HEAD packages/agentfree-webapp-chat | tar -x -C "$stage/shared-sdk"
git -C "$identity_root" archive HEAD src/AgentIdentity.WebSdk | tar -x -C "$stage/shared-sdk"
shared_chat_package="$stage/shared-sdk/packages/agentfree-webapp-chat"
shared_identity_package="$stage/shared-sdk/src/AgentIdentity.WebSdk"
[[ -s "$shared_chat_package/dist/index.js" && -s "$shared_chat_package/dist/index.d.ts" ]] || {
  echo 'Committed AgentFree WebApp chat package is incomplete.' >&2; exit 1;
}
[[ -s "$shared_identity_package/dist/index.js" && -s "$shared_identity_package/dist/index.d.ts" ]] || {
  echo 'Committed AgentIdentity Web SDK is incomplete.' >&2; exit 1;
}
node - "$stage/frontend/package.json" "$shared_chat_package" "$shared_identity_package" <<'NODE'
const fs = require('fs');
const [manifestPath, chatPackage, identityPackage] = process.argv.slice(2);
const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
manifest.dependencies['@agentfree/webapp-chat'] = `file:${chatPackage}`;
manifest.dependencies['@aihome/agentidentity-web-sdk'] = `file:${identityPackage}`;
fs.writeFileSync(manifestPath, JSON.stringify(manifest, null, 2) + '\n');
NODE
(
  cd "$stage/frontend"
  npm install --package-lock-only --ignore-scripts
  npm ci
  npm run lint
  npm run build -- --outDir "$stage/web"
)
# Ship the maintained Linko feature UI under the same Moment site, without copying sources.
linko_root="$shared_projects_root/Linko"
[[ -f "$linko_root/apps/web/package-lock.json" ]] || { echo 'Committed Linko web package required.' >&2; exit 2; }
(
  cd "$linko_root/apps/web"
  npm ci
  node --test src/requestPhoto.test.mjs src/photoLocation.test.mjs
  VITE_MOMENT_INTEGRATED=true npm run build -- --base /moment/ --outDir "$stage/web/moment"
)
node - "$stage/web/version.json" "$app_code" "$version" <<'NODE'
const fs = require('fs');
const [file, appCode, releaseVersion] = process.argv.slice(2);
fs.writeFileSync(file, JSON.stringify({ appCode, version: releaseVersion }) + '\n');
NODE
mkdir -p "$stage/api/migrations"
cp "$root/scripts/migrations/"*.sql "$stage/api/migrations/"
cp "$root/scripts/run-db-migrations.sh" "$stage/api/migrations/run-db-migrations.sh"
mkdir -p "$stage/api/deploy/moment-cache"
cp "$root/deploy/moment-cache/"* "$stage/api/deploy/moment-cache/"
mkdir -p "$stage/api/deploy/moment-native-auth"
cp "$root/deploy/native-auth-origin/"* "$stage/api/deploy/moment-native-auth/"
mkdir -p "$stage/api/deploy/moment-domain"
cp "$root/deploy/activate-moment-domain.py" "$root/deploy/happylife.ai.impx.net.nginx.conf" "$root/deploy/happylife.ai.xmkurt.com.nginx.conf" "$stage/api/deploy/moment-domain/"
cp "$linko_root/deploy/nginx-linko-ai-impx.conf" "$stage/api/deploy/moment-domain/linko.ai.impx.net.nginx.conf"
cp "$linko_root/deploy/configure-turn.sh" "$stage/api/deploy/moment-domain/"
# Atlas owns package validation, release identity, checksums and combined API/Web layout.
bash "$atlas_root/scripts/atlas-package-server.sh" "$stage/api" "$stage/web" "$2" "$app_code" "$version"
