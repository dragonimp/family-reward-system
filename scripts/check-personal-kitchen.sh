#!/usr/bin/env bash
set -euo pipefail
: "${ATLAS_BUILD_WORK:?Use host-build-output}" "${ATLAS_BUILD_OUTPUT:?}"
db="personal_kitchen_test_$(python3 -c 'import uuid;print(uuid.uuid4().hex)')"
createdb "$db"
trap 'dropdb --if-exists "$db"' EXIT
pg_dump -Fc "$db" > "$ATLAS_BUILD_WORK/before.dump"
mkdir -p "$ATLAS_BUILD_WORK/migrations"
cp scripts/migrations/20261107-kitchen-recipes-v1.sql scripts/migrations/20261108-personal-kitchen-v1.sql "$ATLAS_BUILD_WORK/migrations/"
export FAMILY_REWARD_DB_DSN="dbname=$db" FAMILY_REWARD_DB_BACKUP="$ATLAS_BUILD_WORK/before.dump"
bash scripts/run-db-migrations.sh "$ATLAS_BUILD_WORK/migrations"
bash scripts/run-db-migrations.sh "$ATLAS_BUILD_WORK/migrations"
export KITCHEN_TEST_DSN="Host=/tmp;Database=$db;Username=$(id -un)"
export KITCHEN_TEST_IMAGE="$PWD/FamilyReward.Api/recipe-illustrations/b3fcce06-1d3c-5b2f-822b-0419beae6ed4/v1/step-1.jpg"
dotnet run --project tests/PersonalKitchen/PersonalKitchen.csproj --artifacts-path "$ATLAS_BUILD_WORK/dotnet"
dotnet build FamilyReward.Api/FamilyReward.Api.csproj --artifacts-path "$ATLAS_BUILD_WORK/api" -p:UseSharedCompilation=false -m:1 -v:q
echo 'Personal kitchen HTTP, ownership, UUID, migration replay and idempotent counts passed' > "$ATLAS_BUILD_OUTPUT/personal-kitchen-checks.txt"
