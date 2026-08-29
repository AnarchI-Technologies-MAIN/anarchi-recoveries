#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${RECOVERIES_TEST_DATABASE_URL:-}" ]]; then
  echo "RECOVERIES_TEST_DATABASE_URL is required" >&2
  exit 64
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
proof_tmp="$(mktemp -d -t recoveries-outbox-proof.XXXXXXXX)"
worker_a_output="$proof_tmp/worker-a.txt"
worker_b_output="$proof_tmp/worker-b.txt"

cleanup() {
  psql "$RECOVERIES_TEST_DATABASE_URL" -X -v ON_ERROR_STOP=1 -q <<'SQL'
DELETE FROM recoveries.transactional_outbox
WHERE organization_id = '00000000-0000-4000-8000-000000001020';
DELETE FROM recoveries.projects
WHERE organization_id = '00000000-0000-4000-8000-000000001020';
DELETE FROM recoveries.organizations
WHERE id = '00000000-0000-4000-8000-000000001020';
SQL
  rm -f -- "$worker_a_output" "$worker_b_output"
  rmdir -- "$proof_tmp"
}
trap cleanup EXIT

psql "$RECOVERIES_TEST_DATABASE_URL" -X -v ON_ERROR_STOP=1 \
  -f "$repo_root/tools/migration-check/seed-step-10-concurrency.sql" >/dev/null

psql "$RECOVERIES_TEST_DATABASE_URL" -X -qAt -v ON_ERROR_STOP=1 >"$worker_a_output" <<'SQL' &
BEGIN;
SET LOCAL ROLE recoveries_outbox_publisher_role;
SELECT set_config('anarchi.current_organization_id', '00000000-0000-4000-8000-000000001020', true);
SELECT id::text || '|' || claim_token::text
FROM recoveries.claim_outbox('concurrent-worker-a', 1, '2026-08-29T00:00:00Z', interval '30 seconds');
SELECT pg_sleep(2);
COMMIT;
SQL
worker_a_pid=$!

sleep 0.25

psql "$RECOVERIES_TEST_DATABASE_URL" -X -qAt -v ON_ERROR_STOP=1 >"$worker_b_output" <<'SQL'
BEGIN;
SET LOCAL ROLE recoveries_outbox_publisher_role;
SELECT set_config('anarchi.current_organization_id', '00000000-0000-4000-8000-000000001020', true);
SELECT id::text || '|' || claim_token::text
FROM recoveries.claim_outbox('concurrent-worker-b', 1, '2026-08-29T00:00:00Z', interval '30 seconds');
COMMIT;
SQL

wait "$worker_a_pid"

worker_a_claim="$(rg -o '[0-9a-f-]{36}\|[0-9a-f-]{36}' "$worker_a_output")"
worker_b_claim="$(rg -o '[0-9a-f-]{36}\|[0-9a-f-]{36}' "$worker_b_output")"

if [[ -z "$worker_a_claim" || -z "$worker_b_claim" || "$worker_a_claim" == "$worker_b_claim" ]]; then
  echo "concurrent SKIP LOCKED proof failed" >&2
  exit 1
fi

worker_a_id="${worker_a_claim%%|*}"
worker_b_id="${worker_b_claim%%|*}"
if [[ "$worker_a_id" == "$worker_b_id" ]]; then
  echo "concurrent workers claimed the same row" >&2
  exit 1
fi

printf 'worker_a=%s\nworker_b=%s\nresult=PASS_SKIP_LOCKED_DISTINCT_CLAIMS\n' \
  "$worker_a_claim" "$worker_b_claim"
