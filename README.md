# AnarchI Tech Recoveries

Deterministic financial-recovery software governed by
`SPEC-1.6-AnarchI-Tech-Recoveries-FROZEN.md`.

The repository begins at the M1 deterministic boundary. The Rust recovery core
has no network, database, implicit clock, randomness, LLM, authorization, secret
resolution, or external side effects. It accepts explicit versioned input and
returns a typed decision with a reproducible canonical SHA-256 digest.

## Authority boundaries

- Anar-Core decides whether privileged actions may occur.
- Recovery Core calculates deterministic financial truth.
- Broker and Vault resolve separately authorized secret capabilities.
- Action Runner executes an approved immutable action plan.
- This M1 repository implements only the pure Recovery Core boundary.

Canonical governance text and this README are not executable authorization.

## Verify

```text
cargo test --workspace --locked
cargo clippy --workspace --all-targets -- -D warnings
cargo fmt --all -- --check
```

## Frozen source provenance

The initial implementation is derived from the user-provided frozen blueprint:

```text
name: SPEC-1.6-AnarchI-Tech-Recoveries-FROZEN.md
size_bytes: 73369
modified_utc: 2026-08-28T23:40:10.8795475Z
sha256: 0E3877AFF0832DB9CC0503D9A8769F2B867A1536441FBA149874360FBB8F8869
```

