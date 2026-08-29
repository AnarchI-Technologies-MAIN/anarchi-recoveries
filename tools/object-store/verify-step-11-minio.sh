#!/usr/bin/env bash
set -euo pipefail
endpoint=http://127.0.0.1:59000
alias_name=recoveries-proof
bucket=recoveries-proof
tmp=$(mktemp -d -t recoveries-evidence-proof.XXXXXXXX)
trap 'rm -rf -- "$tmp"; mc rb --force "$alias_name/$bucket" >/dev/null 2>&1 || true; mc alias rm "$alias_name" >/dev/null 2>&1 || true' EXIT
printf 'AnarchI evidence proof bytes\n' > "$tmp/source.bin"
sha256=$(sha256sum "$tmp/source.bin" | cut -d' ' -f1)
key="org/00000000-0000-4000-8000-000000001101/project/00000000-0000-4000-8000-000000001102/evidence/00000000-0000-4000-8000-000000001103/$sha256/source.bin"
mc alias set "$alias_name" "$endpoint" recoveries_local_proof recoveries-local-proof-only >/dev/null
mc mb "$alias_name/$bucket" >/dev/null
mc cp --attr "sha256=$sha256;original-filename=source.bin" "$tmp/source.bin" "$alias_name/$bucket/$key" >/dev/null
mc stat --json "$alias_name/$bucket/$key" >/dev/null
mc cat "$alias_name/$bucket/$key" > "$tmp/retrieved.bin"
test "$(sha256sum "$tmp/retrieved.bin" | cut -d' ' -f1)" = "$sha256"
test "$(stat -c %s "$tmp/retrieved.bin")" = "$(stat -c %s "$tmp/source.bin")"
test "$(dd if="$tmp/retrieved.bin" bs=1 count=12 2>/dev/null)" = 'AnarchI evid'
mc cat --offset 8 "$alias_name/$bucket/$key" | head -c 7 > "$tmp/range.bin"
test "$(cat "$tmp/range.bin")" = 'evidenc'
mc version enable "$alias_name/$bucket" >/dev/null
printf 'AnarchI evidence proof bytes v2\n' > "$tmp/source-v2.bin"
mc cp --attr "sha256=$sha256;original-filename=source.bin" "$tmp/source-v2.bin" "$alias_name/$bucket/$key" >/dev/null
test "$(mc stat --versions --json "$alias_name/$bucket/$key" | wc -l)" -ge 2
printf 'result=PASS_EVIDENCE_HASH_REPLAY\nkey=%s\nsha256=%s\n' "$key" "$sha256"
