#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
proof_tmp=$(mktemp -d -t recoveries-core-boundary.XXXXXXXX)
trap 'rm -f -- "$proof_tmp/actual.json"; rmdir -- "$proof_tmp"' EXIT

cargo build --quiet --manifest-path "$repo_root/Cargo.toml" --bin recovery-core-runner
go run "$repo_root/services/normalization/cmd/core-boundary-proof" \
  "$repo_root/target/debug/recovery-core-runner" \
  "$repo_root/fixtures/projects/proj_01/drawing_delta_input.json" \
  "$repo_root/fixtures/projects/proj_01/drawing_delta_expected.json"
