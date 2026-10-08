#!/usr/bin/env bash
set -euo pipefail
export PATH="/opt/homebrew/opt/node@24/bin:/Users/wengzhishan/.local/npm-global/bin:$PATH"
command -v npm >/dev/null && command -v node >/dev/null || {
  echo 'The trusted Mac Node.js toolchain is unavailable.' >&2
  exit 2
}

: "${ATLAS_RELEASE_VERSION:?Atlas must provide the immutable release version}"
: "${ATLAS_SOURCE_COMMIT:?Atlas must provide the requested source commit}"
version="$ATLAS_RELEASE_VERSION"
source_commit="$ATLAS_SOURCE_COMMIT"
[[ "$version" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$ && "$version" != latest ]] || exit 2
[[ "$source_commit" =~ ^[0-9a-f]{40}$ ]] || exit 2
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ "$root" == /Users/wengzhishan/Projects/family-reward-system ]] || {
  echo 'Atlas deployment adapter must run from the trusted project repository.' >&2
  exit 2
}
git -C "$root" fetch --no-tags origin refs/heads/main:refs/remotes/origin/main
merge_commit="$(git -C "$root" rev-parse refs/remotes/origin/main)"
git -C "$root" merge-base --is-ancestor "$source_commit" "$merge_commit" || {
  echo 'The published target branch does not contain the requested source commit.' >&2
  exit 2
}

scratch="$(mktemp -d "$HOME/.codex/worktrees/family-reward-atlas-deploy.XXXXXXXX")"
checkout="$scratch/source"
cleanup() {
  if [[ -d "$checkout" ]] && [[ "$(git -C "$checkout" rev-parse HEAD 2>/dev/null || true)" == "$merge_commit" ]] \
      && [[ -z "$(git -C "$checkout" status --porcelain --untracked-files=all 2>/dev/null || true)" ]]; then
    git -C "$root" worktree remove "$checkout" || true
  fi
  if [[ ! -e "$checkout" ]]; then rmdir "$scratch" 2>/dev/null || true; fi
}
trap cleanup EXIT
git -C "$root" worktree add --detach "$checkout" "$merge_commit" >&2
ATLAS_SOURCE_ROOT=/Users/wengzhishan/Projects/Atlas \
FAMILY_REWARD_SHARED_PROJECTS_ROOT=/Users/wengzhishan/Projects \
  bash "$checkout/scripts/build-atlas-release.sh" "$version" "$scratch/release" >&2

stage="/opt/Atlas/release-staging/family-points-pipeline/$version"
ssh -o BatchMode=yes root@zz.impx.net "test ! -e '$stage' && mkdir -p '$stage'"
scp -q "$scratch/release/bundle.json" "$scratch/release/family-points-api.tar.gz" \
  "$scratch/release/family-points-web.tar.gz" "$scratch/release/family-points-server.tar.gz" \
  "$checkout/scripts/atlas-activate-server.sh" "root@zz.impx.net:$stage/"
ssh -o BatchMode=yes root@zz.impx.net \
  "bash '$stage/atlas-activate-server.sh' '$version' '$source_commit' '$stage'"
