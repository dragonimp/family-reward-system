#!/usr/bin/env bash
set -euo pipefail
[[ $# == 1 && "$1" == source || $# == 1 && "$1" == deployment ]] || exit 2
mode="$1"
host="${FAMILY_REWARD_SOURCE_HOST:?Configure the verified Tailscale source host}"
[[ "$host" =~ ^[0-9A-Za-z.-]+$ ]] || exit 2

if [[ "$mode" == source ]]; then
  : "${ATLAS_SOURCE_BRANCH:?}"
  : "${ATLAS_TARGET_BRANCH:?}"
  : "${ATLAS_SOURCE_COMMIT:?}"
  : "${ATLAS_PROJECT_CODE:?}"
  [[ "$ATLAS_SOURCE_BRANCH" =~ ^[A-Za-z0-9._/-]{1,120}$ && "$ATLAS_TARGET_BRANCH" =~ ^[A-Za-z0-9._/-]{1,120}$ ]] || exit 2
  [[ "$ATLAS_SOURCE_COMMIT" =~ ^[0-9a-f]{40}$ && "$ATLAS_PROJECT_CODE" == family-reward ]] || exit 2
  ssh -o BatchMode=yes -o StrictHostKeyChecking=yes -o ConnectTimeout=10 \
    "wengzhishan@$host" bash -s -- "$ATLAS_SOURCE_BRANCH" "$ATLAS_TARGET_BRANCH" "$ATLAS_SOURCE_COMMIT" "$ATLAS_PROJECT_CODE" "${ATLAS_DRY_RUN:-0}" <<'REMOTE'
set -euo pipefail
export ATLAS_WORKTREE=/Users/wengzhishan/Projects/family-reward-system
export ATLAS_SOURCE_BRANCH="$1" ATLAS_TARGET_BRANCH="$2" ATLAS_SOURCE_COMMIT="$3" ATLAS_PROJECT_CODE="$4"
export ATLAS_DRY_RUN="$5"
exec bash /Users/wengzhishan/Projects/Atlas/scripts/atlas-source-integration.sh
REMOTE
else
  : "${ATLAS_RELEASE_VERSION:?}"
  : "${ATLAS_SOURCE_COMMIT:?}"
  [[ "$ATLAS_RELEASE_VERSION" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$ && "$ATLAS_SOURCE_COMMIT" =~ ^[0-9a-f]{40}$ ]] || exit 2
  ssh -o BatchMode=yes -o StrictHostKeyChecking=yes -o ConnectTimeout=10 \
    "wengzhishan@$host" bash -s -- "$ATLAS_RELEASE_VERSION" "$ATLAS_SOURCE_COMMIT" <<'REMOTE'
set -euo pipefail
export ATLAS_RELEASE_VERSION="$1" ATLAS_SOURCE_COMMIT="$2"
root=/Users/wengzhishan/Projects/family-reward-system
git -C "$root" fetch --no-tags origin refs/heads/main:refs/remotes/origin/main
merge_commit="$(git -C "$root" rev-parse refs/remotes/origin/main)"
git -C "$root" merge-base --is-ancestor "$ATLAS_SOURCE_COMMIT" "$merge_commit"
# The checked-out main worktree can lag behind GitHub. Run the adapter from the
# exact merged revision without touching the user's current checkout.
adapter="$(mktemp "$root/scripts/.atlas-deploy.XXXXXXXX")"
trap 'rm -f "$adapter"' EXIT
git -C "$root" show "$merge_commit:scripts/atlas-deploy-server.sh" > "$adapter"
chmod 700 "$adapter"
bash "$adapter"
REMOTE
fi
