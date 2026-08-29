#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${RECOVERIES_TEST_DATABASE_URL:-}" ]]; then
  echo "RECOVERIES_TEST_DATABASE_URL is required" >&2
  exit 64
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
migration_root="$repo_root/infra/postgres/migrations"

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

  psql "$RECOVERIES_TEST_DATABASE_URL" -X -v ON_ERROR_STOP=1 -f "$migration"
  psql "$RECOVERIES_TEST_DATABASE_URL" -X -v ON_ERROR_STOP=1 \
    -c "INSERT INTO recoveries.schema_migrations(version, sha256) VALUES ('$version', '$digest')"
done < <(find "$migration_root" -maxdepth 1 -type f -name '*.sql' | sort)
