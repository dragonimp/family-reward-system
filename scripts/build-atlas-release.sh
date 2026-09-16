#!/usr/bin/env bash
set -euo pipefail
[[ $# == 2 ]] || { echo 'Usage: build-atlas-release.sh <version> <new-output-directory>' >&2; exit 2; }
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
atlas_root="${ATLAS_SOURCE_ROOT:-$root/../Atlas}"
[[ -f "$atlas_root/scripts/atlas-package-server.sh" ]] || { echo 'Atlas shared packager is required.' >&2; exit 2; }
[[ ! -e "$2" ]] || { echo 'Output directory must not exist.' >&2; exit 2; }
version="$1"
[[ "$version" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$ && "$version" != latest ]] || exit 2
stage="$(mktemp -d "${TMPDIR:-/tmp}/family-atlas-build.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
app_code="$(node -e 'console.log(require(process.argv[1]).appCode)' "$root/deploy/atlas-release.json")"
dotnet publish "$root/FamilyReward.Api/FamilyReward.Api.csproj" -c Release -r linux-x64 --self-contained false -o "$stage/api"
npm --prefix "$root/frontend" run build -- --outDir "$stage/web"
# Atlas owns package validation, release identity, checksums and combined API/Web layout.
bash "$atlas_root/scripts/atlas-package-server.sh" "$stage/api" "$stage/web" "$2" "$app_code" "$version"
