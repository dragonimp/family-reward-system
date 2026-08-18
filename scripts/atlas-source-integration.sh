#!/usr/bin/env bash
set -euo pipefail

root="${ATLAS_WORKTREE:?ATLAS_WORKTREE is required}"
source_branch="${ATLAS_SOURCE_BRANCH:?ATLAS_SOURCE_BRANCH is required}"
target_branch="${ATLAS_TARGET_BRANCH:?ATLAS_TARGET_BRANCH is required}"
cd "$root"
git rev-parse --show-toplevel >/dev/null
if [[ -n "$(git status --porcelain)" ]]; then
  if [[ "${ATLAS_CLEAN_WORKTREE:-0}" != "1" ]]; then
    echo '工作树存在未提交改动；设置 ATLAS_CLEAN_WORKTREE=1 才允许清理。' >&2
    exit 2
  fi
  git reset --hard HEAD
  git clean -fd
fi
if [[ "${ATLAS_DRY_RUN:-0}" == "1" ]]; then
  printf '{"summary":"源码合并预检查通过","evidence":"worktree_clean"}\n'
  exit 0
fi
git fetch --all --prune
git checkout "$target_branch"
git pull --ff-only
git merge --no-ff "$source_branch" -m "Merge $source_branch into $target_branch"
printf '{"summary":"源码合并完成","evidence":"merge_commit_sha=%s"}\n' "$(git rev-parse HEAD)"

