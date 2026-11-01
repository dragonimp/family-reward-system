#!/usr/bin/env bash
set -euo pipefail
: "${ATLAS_BUILD_WORK:?run through host-build-output}"
: "${ATLAS_BUILD_OUTPUT:?}"
: "${ATLAS_BUILD_LOGS:?}"
export MSBUILDDISABLENODEREUSE=1 DOTNET_CLI_DO_NOT_USE_MSBUILD_SERVER=1
projects=/Users/wengzhishan/Projects
mkdir -p "$ATLAS_BUILD_WORK/source"
for project in AgentIdentity MyVnc Linko family-reward-system; do
  root="$projects/$project"
  commit="$(git -C "$root" rev-parse HEAD)"
  remote="$(git -C "$root" ls-remote origin refs/heads/main | cut -f1)"
  [[ "$commit" == "$remote" ]] || { echo "$project source is not pushed main"; exit 1; }
  if [[ "$project" == AgentIdentity ]]; then
    # The Family adapter verifies SDK ancestry through Git; keep that proof in
    # this disposable, detached dependency checkout without duplicating objects.
    git clone --quiet --shared --no-checkout "$root" "$ATLAS_BUILD_WORK/source/$project"
    git -C "$ATLAS_BUILD_WORK/source/$project" checkout --quiet --detach "$commit"
  else
    mkdir -p "$ATLAS_BUILD_WORK/source/$project"
    git -C "$root" archive "$commit" | tar -x -C "$ATLAS_BUILD_WORK/source/$project"
  fi
  printf '%s %s\n' "$project" "$commit" >> "$ATLAS_BUILD_OUTPUT/source-commits.txt"
done
export ATLAS_ROOT="$projects/Atlas" AtlasRoot="$projects/Atlas" ATLAS_SOURCE_ROOT="$projects/Atlas"
export MyVncRoot="$ATLAS_BUILD_WORK/source/MyVnc"
export AgentIdentityRoot="$ATLAS_BUILD_WORK/source/AgentIdentity"
export AGENTIDENTITY_ROOT="$AgentIdentityRoot"
export FAMILY_REWARD_SHARED_PROJECTS_ROOT="$ATLAS_BUILD_WORK/source"
(cd "$ATLAS_BUILD_WORK/source/Linko" && bash scripts/check-moment-connect.sh)
for project in Linko family-reward-system; do
  frozen_commit="$(awk -v project="$project" '$1 == project {print $2}' "$ATLAS_BUILD_OUTPUT/source-commits.txt")"
  version="$(date +%Y%m%d-%H%M%S)-activity-${frozen_commit:0:7}"
  [[ "$version" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$ && "$version" != latest ]] || exit 2
  echo "$project $version" | tee -a "$ATLAS_BUILD_OUTPUT/service-versions.txt"
  bash "$ATLAS_BUILD_WORK/source/$project/scripts/build-atlas-release.sh" "$version" "$ATLAS_BUILD_OUTPUT/$project" \
    > "$ATLAS_BUILD_LOGS/$project.log" 2>&1 || { tail -50 "$ATLAS_BUILD_LOGS/$project.log"; exit 1; }
done
printf '%s\n' 'PASS: frozen activity/comment service sources tested and packaged' > "$ATLAS_BUILD_OUTPUT/services-checks.txt"
