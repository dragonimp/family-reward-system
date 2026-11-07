#!/usr/bin/env bash
set -euo pipefail
: "${ATLAS_BUILD_WORK:?Use host-build-output}" "${ATLAS_BUILD_OUTPUT:?}"
db="kitchen_test_$(python3 -c 'import uuid; print(uuid.uuid4().hex)')"
createdb "$db"
trap 'dropdb --if-exists "$db"' EXIT
pg_dump -Fc "$db" > "$ATLAS_BUILD_WORK/before.dump"
mkdir -p "$ATLAS_BUILD_WORK/migrations"
cp scripts/migrations/20261107-kitchen-recipes-v1.sql "$ATLAS_BUILD_WORK/migrations/"
export FAMILY_REWARD_DB_DSN="dbname=$db" FAMILY_REWARD_DB_BACKUP="$ATLAS_BUILD_WORK/before.dump"
bash scripts/run-db-migrations.sh "$ATLAS_BUILD_WORK/migrations"
cp scripts/migrations/20261107-kitchen-illustrations-v1.sql "$ATLAS_BUILD_WORK/migrations/"
# A late recipe mismatch must roll back all earlier image bindings and the ledger.
psql "$FAMILY_REWARD_DB_DSN" -X -v ON_ERROR_STOP=1 -c "UPDATE kitchen_recipes SET body=jsonb_set(body,'{steps,0,action}','\"fixture changed\"') WHERE id='f3be4543-ac91-506a-900d-9c343a43424d'" >/dev/null
if bash scripts/run-db-migrations.sh "$ATLAS_BUILD_WORK/migrations" > "$ATLAS_BUILD_WORK/expected-version-rejection.log" 2>&1; then
  echo 'Changed recipe unexpectedly accepted image bindings' >&2; exit 1
fi
[[ "$(psql "$FAMILY_REWARD_DB_DSN" -X -At -c "SELECT count(*) FROM kitchen_recipes WHERE body->>'illustrationStatus'='ready'")" == 0 ]] || exit 1
psql "$FAMILY_REWARD_DB_DSN" -X -v ON_ERROR_STOP=1 -c "UPDATE kitchen_recipes SET body=jsonb_set(body,'{steps,0,action}','\"煮开\"') WHERE id='f3be4543-ac91-506a-900d-9c343a43424d'" >/dev/null
bash scripts/run-db-migrations.sh "$ATLAS_BUILD_WORK/migrations"
bash scripts/run-db-migrations.sh "$ATLAS_BUILD_WORK/migrations"
export KITCHEN_TEST_DSN="Host=/tmp;Database=$db;Username=$(id -un)"
cp scripts/migrations/20261107-kitchen-dessert-catalog-v1.sql "$ATLAS_BUILD_WORK/migrations/"
bash scripts/run-db-migrations.sh "$ATLAS_BUILD_WORK/migrations"
bash scripts/run-db-migrations.sh "$ATLAS_BUILD_WORK/migrations"
dotnet run --project tests/Kitchen/Kitchen.csproj --artifacts-path "$ATLAS_BUILD_WORK/dotnet"
echo 'Kitchen PostgreSQL migration replay and HTTP tests passed' > "$ATLAS_BUILD_OUTPUT/kitchen-checks.txt"
