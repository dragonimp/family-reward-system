#!/usr/bin/env bash
set -euo pipefail

[[ $# == 1 && -d "$1" ]] || { echo 'Usage: run-db-migrations.sh <migrations-directory>' >&2; exit 2; }
: "${FAMILY_REWARD_DB_DSN:?Set the verified PostgreSQL connection string}"
: "${FAMILY_REWARD_DB_BACKUP:?Set the path to a completed database backup}"
[[ -s "$FAMILY_REWARD_DB_BACKUP" ]] || { echo 'Database backup is missing or empty' >&2; exit 2; }

shopt -s nullglob
files=("$1"/*.sql)
for file in "${files[@]}"; do
  id="$(basename "$file" .sql)"
  [[ "$id" =~ ^[0-9]{8}-[a-z0-9-]+$ ]] || { echo "Invalid migration ID: $id" >&2; exit 2; }
  if command -v sha256sum >/dev/null 2>&1; then
    checksum="$(sha256sum "$file" | cut -d' ' -f1)"
  else
    checksum="$(shasum -a 256 "$file" | cut -d' ' -f1)"
  fi
  {
    cat <<'SQL'
BEGIN;
SELECT pg_advisory_xact_lock(705221804);
CREATE TABLE IF NOT EXISTS family_reward_schema_migrations (
    migration_id TEXT PRIMARY KEY,
    sha256 CHAR(64) NOT NULL,
    completed_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
SELECT EXISTS (
    SELECT 1 FROM family_reward_schema_migrations
    WHERE migration_id = :'migration_id' AND sha256 <> :'checksum'
) AS hash_mismatch \gset
\if :hash_mismatch
SELECT 1 / 0;
\endif
SELECT NOT EXISTS (
    SELECT 1 FROM family_reward_schema_migrations WHERE migration_id = :'migration_id'
) AS run_migration \gset
\if :run_migration
SQL
    cat "$file"
    cat <<'SQL'
INSERT INTO family_reward_schema_migrations (migration_id, sha256)
VALUES (:'migration_id', :'checksum');
\endif
COMMIT;
SQL
  } | psql "$FAMILY_REWARD_DB_DSN" -X -v ON_ERROR_STOP=1 -v migration_id="$id" -v checksum="$checksum" -f -
done
