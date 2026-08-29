#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${RECOVERIES_TEST_DATABASE_URL:-}" ]]; then
  echo "RECOVERIES_TEST_DATABASE_URL is required" >&2
  exit 64
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
migration_root="$repo_root/infra/postgres/migrations"
role_bootstrap="$repo_root/infra/postgres/bootstrap/service-roles.sql"

while IFS= read -r migration; do
  version="$(basename "$migration" .sql)"
  digest="$(sha256sum "$migration" | cut -d' ' -f1)"
  if [[ ! "$version" =~ ^[0-9]{6}_[a-z0-9_]+$ ]] || [[ ! "$digest" =~ ^[a-f0-9]{64}$ ]]; then
    echo "invalid migration identity: $version" >&2
    exit 66
  fi
  already_applied="$(
    psql "$RECOVERIES_TEST_DATABASE_URL" -X -qAt \
      -v ON_ERROR_STOP=1 \
      -c "SELECT sha256 FROM recoveries.schema_migrations WHERE version = '$version'" \
      2>/dev/null || true
  )"

  if [[ -n "$already_applied" ]]; then
    if [[ "$already_applied" != "$digest" ]]; then
      echo "migration digest mismatch: $version" >&2
      exit 65
    fi
    continue
  fi

  psql "$RECOVERIES_TEST_DATABASE_URL" -X -v ON_ERROR_STOP=1 -f "$role_bootstrap"

  migration_role_exists="$(
    psql "$RECOVERIES_TEST_DATABASE_URL" -X -qAt \
      -v ON_ERROR_STOP=1 \
      -c "SELECT 1 FROM pg_roles WHERE rolname = 'recoveries_migration_role'" \
      2>/dev/null || true
  )"

  if [[ "$migration_role_exists" == "1" ]]; then
    PGOPTIONS="${PGOPTIONS:-} -c role=recoveries_migration_role" \
      psql "$RECOVERIES_TEST_DATABASE_URL" -X -v ON_ERROR_STOP=1 -f "$migration"
  else
    psql "$RECOVERIES_TEST_DATABASE_URL" -X -v ON_ERROR_STOP=1 -f "$migration"
  fi
  psql "$RECOVERIES_TEST_DATABASE_URL" -X -v ON_ERROR_STOP=1 \
    -c "INSERT INTO recoveries.schema_migrations(version, sha256) VALUES ('$version', '$digest')"
done < <(find "$migration_root" -maxdepth 1 -type f -name '*.sql' | sort)
