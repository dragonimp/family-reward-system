#!/usr/bin/env bash
set -euo pipefail
: "${ATLAS_BUILD_WORK:?}"
: "${ATLAS_BUILD_OUTPUT:?}"
export MSBUILDDISABLENODEREUSE=1 DOTNET_CLI_DO_NOT_USE_MSBUILD_SERVER=1
projects=/Users/wengzhishan/Projects
mkdir -p "$ATLAS_BUILD_WORK/source"
for project in AgentIdentity Linko family-reward-system; do
  source="$projects/$project"
  commit="$(git -C "$source" rev-parse HEAD)"
  remote="$(git -C "$source" ls-remote origin refs/heads/main | cut -f1)"
  [[ "$commit" == "$remote" ]] || { echo "$project source is not pushed main"; exit 1; }
  mkdir -p "$ATLAS_BUILD_WORK/source/$project"
  git -C "$source" archive "$commit" | tar -x -C "$ATLAS_BUILD_WORK/source/$project"
  printf '%s %s\n' "$project" "$commit" >> "$ATLAS_BUILD_OUTPUT/source-commits.txt"
done
ln -s "$projects/MyVnc" "$ATLAS_BUILD_WORK/source/MyVnc"
export TMPDIR="$ATLAS_BUILD_WORK/tmp"
mkdir -p "$TMPDIR"
export ATLAS_ROOT="$projects/Atlas" AtlasRoot="$projects/Atlas" ATLAS_SOURCE_ROOT="$projects/Atlas" MyVncRoot="$projects/MyVnc"
export AGENTIDENTITY_API_ONLY=1
export AGENTIDENTITY_ROOT="$projects/AgentIdentity" FAMILY_REWARD_SHARED_PROJECTS_ROOT="$projects"
# Verify the exact Linko snapshot, including HEAD versions of any concurrently edited files.
(cd "$ATLAS_BUILD_WORK/source/Linko" && bash scripts/check-moment-connect.sh)
# The User Center tests protect subject routing and app-specific APNs topic isolation.
dotnet test "$ATLAS_BUILD_WORK/source/AgentIdentity/tests/AgentIdentity.Tests/AgentIdentity.Tests.csproj" --filter FullyQualifiedName~ApplicationNotificationTests \
  --artifacts-path "$ATLAS_BUILD_WORK/auth-tests" -p:AtlasRoot="$AtlasRoot" -p:MyVncRoot="$MyVncRoot" -p:UseSharedCompilation=false -nr:false -m:1 \
  > "$ATLAS_BUILD_LOGS/auth-tests.log" 2>&1 || { tail -40 "$ATLAS_BUILD_LOGS/auth-tests.log"; exit 1; }
for project in AgentIdentity Linko family-reward-system; do
  version="$(date +%Y%m%d-%H%M%S)-moment-$(git -C "$projects/$project" rev-parse --short HEAD)"
  [[ "$version" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$ && "$version" != latest ]] || exit 2
  echo "$project $version" | tee -a "$ATLAS_BUILD_OUTPUT/service-versions.txt"
  bash "$ATLAS_BUILD_WORK/source/$project/scripts/build-atlas-release.sh" "$version" "$ATLAS_BUILD_OUTPUT/$project" \
    > "$ATLAS_BUILD_LOGS/$project.log" 2>&1 || { tail -45 "$ATLAS_BUILD_LOGS/$project.log"; exit 1; }
done
echo 'PASS: committed service snapshots tested and packaged' > "$ATLAS_BUILD_OUTPUT/services-checks.txt"
