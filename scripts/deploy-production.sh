#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEPLOY_HOST="${DEPLOY_HOST:-zz.impx.net}"
REMOTE_ROOT="${REMOTE_ROOT:-/var/www/happylife}"
STAMP="$(date +%Y%m%d%H%M%S)"
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/family-reward-build.XXXXXX")"
REMOTE_STAGE="/tmp/family-reward-deploy-${STAMP}"

cleanup() {
  rm -rf "$BUILD_DIR"
  ssh "$DEPLOY_HOST" "rm -rf '$REMOTE_STAGE'" >/dev/null 2>&1 || true
}
trap cleanup EXIT

if ! command -v npm >/dev/null 2>&1 && [[ -x /opt/homebrew/opt/node@24/bin/npm ]]; then
  export PATH="/opt/homebrew/opt/node@24/bin:$PATH"
fi
command -v npm >/dev/null 2>&1 || { echo "npm is required" >&2; exit 1; }

dotnet publish "$ROOT_DIR/FamilyReward.Api/FamilyReward.Api.csproj" \
  --configuration Release \
  --output "$BUILD_DIR/api"

npm --prefix "$ROOT_DIR/frontend" run build

ssh "$DEPLOY_HOST" "mkdir -p '$REMOTE_STAGE/api' '$REMOTE_STAGE/frontend'"
rsync -az --delete "$BUILD_DIR/api/" "$DEPLOY_HOST:$REMOTE_STAGE/api/"
rsync -az --delete "$ROOT_DIR/frontend/dist/" "$DEPLOY_HOST:$REMOTE_STAGE/frontend/"

ssh "$DEPLOY_HOST" "set -e
  sudo test -s '$REMOTE_ROOT/api/system_config.json'
  sudo test -s '/etc/agent-secrets/xiaotiancai-email.env'
  sudo mkdir -p '/opt/backups/family-reward/$STAMP'
  sudo cp -a '$REMOTE_ROOT/api' '/opt/backups/family-reward/$STAMP/api'
  sudo cp -a '$REMOTE_ROOT/frontend/static' '/opt/backups/family-reward/$STAMP/frontend-static'
  sudo rsync -a --delete --exclude system_config.json '$REMOTE_STAGE/api/' '$REMOTE_ROOT/api/'
  sudo rsync -a --delete '$REMOTE_STAGE/frontend/' '$REMOTE_ROOT/frontend/static/'
  sudo chown -R www-data:www-data '$REMOTE_ROOT/api' '$REMOTE_ROOT/frontend/static'
  sudo chmod 600 '$REMOTE_ROOT/api/system_config.json'
  sudo mkdir -p /etc/systemd/system/family-reward-api.service.d
  printf '[Service]\nEnvironmentFile=/etc/agent-secrets/application-feedback.env\n' | sudo tee /etc/systemd/system/family-reward-api.service.d/feedback.conf >/dev/null
  printf '[Service]\nEnvironmentFile=/etc/agent-secrets/xiaotiancai-email.env\n' | sudo tee /etc/systemd/system/family-reward-api.service.d/xiaotiancai-email.conf >/dev/null
  sudo systemctl daemon-reload
  sudo systemctl restart family-reward-api.service
  sleep 2
  systemctl is-active family-reward-api.service
  curl -fsS http://127.0.0.1:5102/health"

echo
echo "Deployed to https://happylife.ai.impx.net (backup: /opt/backups/family-reward/$STAMP)"
