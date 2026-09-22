#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ "${ATLAS_DRY_RUN:-0}" == "1" ]]; then
  printf '{"summary":"服务器部署预检查通过","evidence":"standard_deploy_entrypoint"}\n'
  exit 0
fi
# A bounded static legal-page release: no service restart, database or other assets.
if [[ "${1:-}" == --linko-family-legal ]]; then
  git -C "$ROOT_DIR" diff --quiet HEAD -- frontend/public/legal/linko-family-privacy.html
  revision="$(git -C "$ROOT_DIR" rev-parse HEAD)"
  remote_revision="$(git -C "$ROOT_DIR" ls-remote origin refs/heads/main | cut -f1)"
  [[ "$revision" == "$remote_revision" ]] || { echo 'Release commit must match GitHub main' >&2; exit 1; }
  stage="/tmp/linko-family-legal-$revision.html"
  scp "$ROOT_DIR/frontend/public/legal/linko-family-privacy.html" "zz.impx.net:$stage"
  ssh zz.impx.net bash -s -- "$stage" "$revision" <<'REMOTE'
set -euo pipefail
stage="$1"
revision="$2"
target=/var/www/happylife/frontend/static/legal/linko-family-privacy.html
sudo mkdir -p "/opt/backups/family-reward/legal-$revision"
if sudo test -f "$target"; then sudo cp -a "$target" "/opt/backups/family-reward/legal-$revision/"; fi
sudo install -o www-data -g www-data -m 644 "$stage" "$target.new"
sudo mv "$target.new" "$target"
rm "$stage"
REMOTE
  curl -fsS https://happylife.ai.impx.net/legal/linko-family-privacy.html | cmp - "$ROOT_DIR/frontend/public/legal/linko-family-privacy.html"
  echo "Verified legal page release $revision"
  exit 0
fi
exec "$ROOT_DIR/scripts/deploy-production.sh" "$@"
printf '{"summary":"服务器部署完成","evidence":"standard_deploy_entrypoint"}\n'

