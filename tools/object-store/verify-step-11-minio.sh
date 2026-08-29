#!/usr/bin/env bash
set -euo pipefail
if [[ -z "${RECOVERIES_OBJECT_STORE_ACCESS_KEY:-}" || -z "${RECOVERIES_OBJECT_STORE_SECRET_KEY:-}" ]]; then
  echo "RECOVERIES_OBJECT_STORE_ACCESS_KEY and RECOVERIES_OBJECT_STORE_SECRET_KEY are required" >&2
  exit 64
fi
endpoint=http://127.0.0.1:59000
alias_name=recoveries-proof
bucket=recoveries-proof
tmp=$(mktemp -d -t recoveries-evidence-proof.XXXXXXXX)
trap 'rm -rf -- "$tmp"; mc rb --force "$alias_name/$bucket" >/dev/null 2>&1 || true; mc alias rm "$alias_name" >/dev/null 2>&1 || true' EXIT
printf 'AnarchI evidence proof bytes\n' > "$tmp/source.bin"
sha256=$(sha256sum "$tmp/source.bin" | cut -d' ' -f1)
key="org/00000000-0000-4000-8000-000000001101/project/00000000-0000-4000-8000-000000001102/evidence/00000000-0000-4000-8000-000000001103/$sha256/source.bin"
mc alias set "$alias_name" "$endpoint" "$RECOVERIES_OBJECT_STORE_ACCESS_KEY" "$RECOVERIES_OBJECT_STORE_SECRET_KEY" >/dev/null
mc mb "$alias_name/$bucket" >/dev/null
mc cp --attr "sha256=$sha256;original-filename=source.bin" "$tmp/source.bin" "$alias_name/$bucket/$key" >/dev/null
mc stat --json "$alias_name/$bucket/$key" > "$tmp/stat.json"
test "$(jq -r '.metadata["X-Amz-Meta-Sha256"]' "$tmp/stat.json")" = "$sha256"
test "$(jq -r '.metadata["X-Amz-Meta-Original-Filename"]' "$tmp/stat.json")" = 'source.bin'
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
download_url=$(mc share download --json --expire 5m "$alias_name/$bucket/$key" | jq -r .share)
curl -fsS "$download_url" > "$tmp/presigned-get.bin"
test "$(sha256sum "$tmp/presigned-get.bin" | cut -d' ' -f1)" = "$(sha256sum "$tmp/source-v2.bin" | cut -d' ' -f1)"
upload_key="presigned/upload.bin"
upload_command=$(mc share upload --json --expire 5m "$alias_name/$bucket/$upload_key" | jq -r --arg file "$tmp/source.bin" '.share | sub("@<FILE>"; "@" + $file)')
upload_command=${upload_command/curl /curl -fsS }
bash -c "$upload_command" >/dev/null
test "$(mc cat "$alias_name/$bucket/$upload_key")" = "$(cat "$tmp/source.bin")"
current_etag=$(mc stat --json "$alias_name/$bucket/$key" | jq -r .etag)
curl -fsS -H "If-Match: \"$current_etag\"" "$download_url" >/dev/null
test "$(curl -sS -o /dev/null -w '%{http_code}' -H 'If-Match: "not-the-etag"' "$download_url")" = '412'
dd if=/dev/zero of="$tmp/multipart.bin" bs=1M count=70 status=none
mc cp "$tmp/multipart.bin" "$alias_name/$bucket/multipart.bin" >/dev/null
test "$(mc stat --json "$alias_name/$bucket/multipart.bin" | jq -r .etag)" != ""
lock_bucket="recoveries-lock-proof"
mc mb --with-lock "$alias_name/$lock_bucket" >/dev/null
mc retention set --default governance 1d "$alias_name/$lock_bucket" >/dev/null
mc retention info --default "$alias_name/$lock_bucket" | rg -i 'governance' >/dev/null
mc rb "$alias_name/$lock_bucket" >/dev/null
printf 'proof=put_get_head_metadata\nproof=range_read\nproof=versioning\nproof=presigned_put_get\nproof=conditional_requests\nproof=multipart\nproof=policy_driven_object_lock\nresult=PASS_EVIDENCE_HASH_REPLAY\nkey=%s\nsha256=%s\n' "$key" "$sha256"
