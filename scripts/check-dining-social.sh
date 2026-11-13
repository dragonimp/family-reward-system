#!/usr/bin/env bash
set -euo pipefail
: "${ATLAS_BUILD_WORK:?Use host-build-output}" "${ATLAS_BUILD_OUTPUT:?}" "${ATLAS_BUILD_LOGS:?}"
export PATH="/opt/homebrew/opt/postgresql@18/bin:$PATH"
db="dining_social_test_$(python3 -c 'import uuid; print(uuid.uuid4().hex)')"
createdb "$db"
trap 'if [[ -n "${server:-}" ]]; then kill "$server" 2>/dev/null || true; wait "$server" 2>/dev/null || true; fi; dropdb "$db"' EXIT
pg_dump -Fc "$db" > "$ATLAS_BUILD_WORK/before.dump"
mkdir "$ATLAS_BUILD_WORK/migrations"
cp scripts/migrations/20261113-dining-{gatherings,social}-v1.sql scripts/migrations/20261114-dining-short-codes-v1.sql "$ATLAS_BUILD_WORK/migrations/"
export FAMILY_REWARD_DB_DSN="dbname=$db" FAMILY_REWARD_DB_BACKUP="$ATLAS_BUILD_WORK/before.dump"
for attempt in 1 2; do
    bash scripts/run-db-migrations.sh "$ATLAS_BUILD_WORK/migrations"
done
dotnet build tests/DiningSocial/DiningSocial.csproj -o "$ATLAS_BUILD_WORK/harness" --artifacts-path "$ATLAS_BUILD_WORK/compiled" -v quiet
export DINING_SOCIAL_TEST_ORIGIN=http://127.0.0.1:28463
MOMENT_QA_DSN="Host=/tmp;Database=$db;Username=$(id -un)" ASPNETCORE_URLS="$DINING_SOCIAL_TEST_ORIGIN" \
    dotnet "$ATLAS_BUILD_WORK/harness/DiningSocial.dll" > "$ATLAS_BUILD_LOGS/harness.log" 2>&1 &
server=$!
python3 tests/DiningSocial/check.py | tee "$ATLAS_BUILD_OUTPUT/dining-social-checks.txt"
