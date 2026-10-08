#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="/opt/homebrew/opt/node@24/bin:/Users/wengzhishan/.local/npm-global/bin:$PATH"
command -v npm >/dev/null && command -v node >/dev/null || {
  echo 'The trusted Mac Node.js toolchain is unavailable.' >&2
  exit 2
}
: "${ATLAS_MERGE_COMMIT:?Atlas source integration must provide the merged commit}"
[[ "$(git -C "$root" rev-parse HEAD)" == "$ATLAS_MERGE_COMMIT" ]] || {
  echo 'Build worktree does not match the Atlas merge commit.' >&2
  exit 2
}

stage="$(mktemp -d "${TMPDIR:-/tmp}/family-atlas-check.XXXXXXXX")"
trap 'rm -rf "$stage"' EXIT
version="pipeline-check-${ATLAS_MERGE_COMMIT:0:12}"
ATLAS_SOURCE_ROOT="${ATLAS_SOURCE_ROOT:-/Users/wengzhishan/Projects/Atlas}" \
FAMILY_REWARD_SHARED_PROJECTS_ROOT="${FAMILY_REWARD_SHARED_PROJECTS_ROOT:-/Users/wengzhishan/Projects}" \
  bash "$root/scripts/build-atlas-release.sh" "$version" "$stage/release" >&2

node - "$stage/release/bundle.json" "$version" <<'NODE'
const manifest = require(process.argv[2]);
if (manifest.version !== process.argv[3] || manifest.artifacts.length !== 3)
  throw new Error('Atlas release bundle does not match the source integration build');
NODE
printf 'Validated Atlas API, Web and server bundle for %s\n' "$ATLAS_MERGE_COMMIT" >&2
