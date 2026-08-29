# Immutable Ledger UI contract

Status: Step 31 framework-neutral ledger view-model baseline

`@anarchi/ui` exposes the frozen immutable-ledger event vocabulary:

```text
EVIDENCE_INGESTED
FACT_EXTRACTED
FACT_VERIFIED
RECOVERY_EVALUATED
PRICE_CALCULATED
APPROVED
ACTION_EXECUTED
PAYMENT_OBSERVED
ATTRIBUTION_RECONCILED
SUCCESS_FEE_ACCRUED
```

Each event carries its timestamp, organization/project/aggregate boundary,
core version, policy version, evaluation hash, source references, and a visible
summary. `APPROVED` and `ACTION_EXECUTED` events cannot be created without a
decision-receipt summary containing operation, resource, authority class,
binding, expiry, and decision hash. Events from another organization are
rejected by the screen contract.

The ledger is ordered deterministically by event timestamp and event ID. It is
an evidence timeline, not a blockchain presentation. The same event can be
adapted into the shared proof-chain item contract, keeping its provenance and
decision-receipt reference visible.

This layer is display-only. It does not append events, authorize actions, call
connectors, or replace the server-side immutable ledger.
