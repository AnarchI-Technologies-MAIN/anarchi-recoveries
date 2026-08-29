# ADR-001: Evaluation receipt placement

**Status:** Accepted  
**Date:** 2026-08-29  
**Scope:** Step 15 evaluation persistence

## Context

The frozen SPEC-1.6 relational entity list names `recovery_opportunities`, but it does not name a separate evaluation-receipt table. The execution sequence nevertheless requires every deterministic evaluation and its hash to be durably replayable, including a valid `NO_OPPORTUNITY` result.

Creating an unlisted table would expand the frozen schema without an explicit specification revision. Omitting no-opportunity evaluations would lose proof of a deterministic negative decision.

## Decision

Use the existing immutable `recoveries.audit_events` relation as the receipt authority for every evaluation. Store the complete core-produced record, canonical decision bytes, canonicalization identifier, evaluation hash, and evaluation time in the audit details. Create a `recoveries.recovery_opportunities` row only when the core decision is `OPPORTUNITY`.

The `recoveries.persist_recovery_evaluation` security-definer function is the sole evaluation write boundary. It requires tenant context, an active baseline, the pinned canonicalization identifier, a lowercase SHA-256 hash that matches the supplied canonical decision bytes and record, and a decision/result shape that matches the supplied tenant and baseline. It emits `recovery.evaluated.v1` in the same transaction. Exact retries are idempotent; conflicting reuse of an evaluation, audit ID, event ID, or idempotency key fails closed.

Direct runtime writes to `recovery_opportunities` are revoked. The evaluation role has execute-only access to the boundary function and no table DML grants.

## Consequences

- Every positive and negative evaluation has an immutable, tenant-scoped receipt.
- Opportunity lifecycle state remains in the existing domain entity and is not conflated with the audit record.
- The outbox event and audit receipt commit atomically with the opportunity row when one exists.
- A future dedicated evaluation entity would require an explicit SPEC revision and a new atomic migration; it is not silently introduced here.

## Controls

This decision preserves DRIFT-001, DRIFT-002, DRIFT-017, DRIFT-020, DRIFT-022, DRIFT-023, DRIFT-026, DRIFT-042, and DRIFT-044. The Step-15 proof demonstrates positive and negative persistence, exact replay without duplication, envelope hash replay, tenant-boundary enforcement, runtime write denial, and invalid-hash rejection.
