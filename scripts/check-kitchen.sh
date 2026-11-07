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
bash scripts/run-db-migrations.sh "$ATLAS_BUILD_WORK/migrations"
export KITCHEN_TEST_DSN="Host=/tmp;Database=$db;Username=$(id -un)"
dotnet run --project tests/Kitchen/Kitchen.csproj --artifacts-path "$ATLAS_BUILD_WORK/dotnet"
echo 'Kitchen PostgreSQL migration replay and HTTP tests passed' > "$ATLAS_BUILD_OUTPUT/kitchen-checks.txt"
