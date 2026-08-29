# Step 22 pilot hardening boundary

This runbook defines the non-production exit evidence for the first pilot
slice. It does not authorize a production migration, customer import, vendor
write, payment collection, or automated action.

## Required controls

Every request or work item carries a complete immutable context:

```text
trace_id
correlation_id
organization_id
project_id
aggregate_id
event_id
```

The shared observability package rejects blank identifiers and exposes the
frozen metric names from SPEC-1.6. Logs remain diagnostic; the Postgres audit
ledger remains the authority for business history.

## AI/extraction outage proof

When an extraction provider fails:

1. the provider error is returned;
2. no fallback fact is persisted;
3. no verification authority is created;
4. source evidence remains owned by the ingestion/object-store boundary;
5. deterministic recovery and payment state are unchanged.

The outage test is intentionally local and uses no external model or vendor
credentials.

## Pilot test matrix

The following families are mandatory before any pilot activation receipt is
issued:

```text
golden fixture equality       decimal precision          DST / business days
duplicate detection           late evidence              superseded baseline
allowance exhaustion          existing CO overlap        partial payments
multi-payment allocation      rejected / contradictory facts
automation thresholds         tenant isolation / RLS     concurrent allocations
FX replay                     outbox stale lease         dead-letter handling
policy deny / allow            payload mutation invalidation
offline revalidation          secret-reference isolation
backup restoration
```

Only the families backed by a passing, reproducible fixture may be marked
`PASS` in a later pilot receipt. Unimplemented families remain explicit open
items; they are not silently treated as covered by adjacent tests.
