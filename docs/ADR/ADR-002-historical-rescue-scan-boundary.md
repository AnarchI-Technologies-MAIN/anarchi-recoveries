# ADR-002: Historical rescue is a read-only, evidence-gated scan

Status: Accepted for Step 21 of SPEC-1.6

## Decision

Historical rescue begins as a pure scan over normalized historical records. The
scan is deterministic and produces a replayable result hash. It does not ingest
files, call vendor APIs, infer facts, calculate a price, create an opportunity,
allocate a payment, accrue a fee, or execute an external action.

The scanner requires an explicit scan identity, organization, project, rule
version, and evaluation time. Every record must carry the exact deduplication
dimensions frozen by the specification:

```text
project / scope item / location / change type /
origin revision or directive / time bucket
```

Records are sorted by that key and record ID before classification. Repeated
keys are retained in the output and marked `DUPLICATE`; history is never
silently discarded.

Revision labels are descriptive only. Ordering is an explicit non-negative
`baseline_revision_order` / `observed_revision_order` pair supplied by the
normalization boundary; the scanner never compares vendor revision strings
lexically.

## Classification contract

The scanner implements `DRAWING_QUANTITY_INCREASE_V1` as a conservative review
classifier:

- all verified conditions and source provenance present -> `ELIGIBLE_FOR_REVIEW`;
- direction or performed work not yet verified, with the other evidence gates
  satisfied -> `POTENTIAL_CHANGE`;
- missing verification, evidence, mapping, or source version ->
  `MORE_EVIDENCE_REQUIRED`;
- non-positive revision/quantity delta, remaining allowance, or existing
  change-order coverage -> `NO_OPPORTUNITY`;
- repeated deterministic deduplication key -> `DUPLICATE`.

The result includes passed, failed, and missing conditions, the record fact ID,
source evidence IDs, rule version, and a canonical scan hash. No historical
finding is treated as a financial entitlement or a billable recovery until the
ordinary deterministic evaluation, attribution, cash-observation, and billing
boundaries independently pass.

## Consequences

This preserves the pilot preference for precision over recall and keeps
historical discovery compatible with immutable evidence and baseline history.
Connector ingestion, durable storage, review UI, and fee attribution remain
separate transitions and require their own receipts.
