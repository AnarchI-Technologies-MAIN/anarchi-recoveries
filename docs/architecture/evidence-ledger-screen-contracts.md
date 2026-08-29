# Evidence Ledger screen contracts

Status: Step 30 framework-neutral view-model baseline

`@anarchi/ui` now contains deterministic contracts for the Evidence Ledger
screen family described by SPEC-1.6:

- `createRescueOverview` fixes the six Rescue metrics and permits only the four
  frozen chart forms. Amounts are `MoneyLine` values, so a chart cannot display
  an untraceable or floating-point number.
- `createRecoveryQueue` fixes the queue columns to `VALUE`, `FINDING`,
  `ENTITLEMENT`, `PROOF`, and `DEADLINE`. There is no generic confidence field.
- `createRecoveryDetail` requires the finding, proof, financial-model, deadline,
  and three explicit state-changing actions. Each action requires confirmation;
  `Send Notice` is a separate named external action.
- `createProofViewer` and `createProofChain` keep source facts, verification
  identity/time, relationships, hashes, edge semantics, and an accessible
  linear representation together. The linear representation is generated from
  the same ordered nodes rather than being a second hand-authored truth.
- `createCashAttribution` requires the supported/prior/ceiling/cash/fee/retained
  values plus provenance-backed incremental recovery. Verification-only state is
  fixed to zero incremental recovery and zero success fee. A non-zero fee before
  cash is rejected.

These are view-model contracts, not a browser, Tauri, or mobile rendering
implementation. They do not fetch data, submit notices, mutate the ledger, or
create recovery determinations. A client adapter must receive authoritative
server data and preserve the contracts; it cannot invent illustrative values or
silently turn a preparation action into a third-party submission.

The contracts use visible status text and ARIA semantics from the shared UI
primitive layer. Color remains a secondary tone. Financial amounts remain
decimal strings with explicit ISO currency and provenance references.
