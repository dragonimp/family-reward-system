#!/usr/bin/env bash
set -euo pipefail
[[ $# == 1 && -f "$1" ]] || { echo 'Usage: publish-atlas-release.sh <bundle.json>' >&2; exit 2; }
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
atlas_root="${ATLAS_SOURCE_ROOT:-$root/../Atlas}"
: "${ATLAS_RELEASE_BASE_URL:?Configure the verified Atlas release origin}"
# Dedicated credentials are supplied through the official SDK environment/file contract.
# This adapter does not create credentials, upload directly, or change server installation paths.
app_id="$(node -e 'console.log(require(process.argv[1]).appId)' "$root/deploy/atlas-release.json")"
exec bash "$atlas_root/scripts/atlas-release.sh" publish-bundle "$app_id" "$1"
