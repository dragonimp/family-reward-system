#!/usr/bin/env bash
set -euo pipefail
[[ $# == 2 ]] || { echo 'Usage: install-social-photo-proxy.sh <config> <stage>' >&2; exit 2; }
source_config="$1"
stage="$2"
[[ "$stage" == /opt/Atlas/release-staging/family-points-pipeline/* && "$source_config" == "$stage/happylife.ai.xmkurt.com.nginx.conf" ]] || exit 2
[[ -f "$source_config" ]] || exit 2
live=/etc/nginx/conf.d/happylife.ai.xmkurt.com.conf
backup="$stage/happylife.ai.xmkurt.com.nginx.previous.conf"
baseline=ed516b0742d17ac042255699e55dde8c719e80b7834af4fdd62605949dd3b7e6
actual="$(sha256sum "$live" | cut -d ' ' -f 1)"
target="$(sha256sum "$source_config" | cut -d ' ' -f 1)"
if [[ "$actual" == "$target" ]]; then
  nginx -t
  systemctl reload nginx
  exit 0
fi
[[ "$actual" == "$baseline" ]] || { echo 'Nginx configuration changed since review; photo proxy was not installed.' >&2; exit 1; }
[[ ! -e "$backup" ]] || { echo 'Existing Nginx rollback copy needs review.' >&2; exit 1; }
cp -a "$live" "$backup"
install -m 644 "$source_config" "$live.new"
mv "$live.new" "$live"
if ! nginx -t || ! systemctl reload nginx; then
  cp -a "$backup" "$live"
  nginx -t && systemctl reload nginx
  echo 'Photo proxy installation failed; previous Nginx configuration restored.' >&2
  exit 1
fi
[[ "$(sha256sum "$live" | cut -d ' ' -f 1)" == "$target" ]] || exit 1
echo "Photo transfer proxy installed; rollback copy: $backup"
