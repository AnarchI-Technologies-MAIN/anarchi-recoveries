# Pilot rehearsal proof boundary

The pilot rehearsal is a local evidence exercise. It is not a release, a
production migration, a customer import, or a vendor integration.

## Isolation

`infra/compose/pilot-rehearsal.compose.yaml` is a dedicated Compose project for
the rehearsal. Postgres, NATS/JetStream, MinIO, and Zitadel are bound to
loopback-only ports, use ephemeral storage where supported, and share an
internal network. The runner supplies credentials through its process
environment only. It rejects production endpoints and production markers before
Compose is started.

The runner can validate the Compose configuration without starting services, or
start the project with `--start-stack`, wait for all health checks, and tear it
down with volumes and orphan containers removed. A stack receipt records the
image digests, configuration digest, health result, and teardown result.

## Synthetic corpus

`fixtures/pilot/manifest.v1.json` is the only input corpus. It contains
synthetic recovery, action, and cash cases plus explicit negative cases. Source
bytes are never rewritten. The corpus digest is included in the run manifest and
every case receipt.

## Receipt chain

`tools/pilot/run_rehearsal.py` emits a canonical receipt for each case. Receipt
hashes use sorted JSON with compact separators and lowercase SHA-256 under
`ANARCHI-JCS-COMPATIBLE-V1`. Each receipt links to its predecessor and records
the source commit, frozen SPEC hash, case input/output digests, and authority
state. Exact reruns with the same run ID reproduce the same case and chain
hashes.

`tools/pilot/verify_pilot_rehearsal.py` verifies the chain, artifact hashes,
case expectations, isolation claims, separate precision metrics, and the
explicit pending independent-review record. It cannot mark a release ready.

## Pilot Evidence Packet (court record)

Each run also emits `pilot-evidence-packet.v1.json`. This is the consumable
financial proof artifact. It carries the pilot identity, repository/spec/rule/
policy/pricing provenance, input-corpus and evidence hashes, decision and
calculation traces, authority receipt, action payload hash, external-action
receipt, payment evidence, attribution and fee results, reconciliation result,
all denials, all unknowns, and the final held state. A reviewer can answer the
economic and authority questions from this packet without querying a running
service.

`blind-review-packet.v1.json` is derived from the same packet and contains no
expected labels or ground-truth fields. The verifier rejects a blind packet that
contains those keys. The independent reviewer receives only this blind packet;
their adjudication is recorded separately and compared dimension by dimension:
opportunity precision, financial exactness, evidence sufficiency, authority
correctness, replay identity, action integrity, attribution correctness,
unknown preservation, and false-positive prevention. No threshold is chosen
after observing the measurements.

## Payment-provider boundary

`tools/pilot/payment_boundary.py` exercises the provider-shaped sequence locally:
checkout requested, payment initiated, webhook received, signature verified,
event deduplicated, amount/currency/catalog matched, business state changed, and
receipt persisted. The simulator uses an in-process test secret, reports zero
network contacts, and never loads Stripe credentials. A real Stripe account is a
later credentialed deployment transition after this boundary is independently
accepted.

## Evidence posture

The evidence report keeps candidate extraction, verified facts, and opportunity
precision separate. It does not invent an aggregate AI-quality score or a pilot
precision threshold. A reviewer may accept or disagree with the evidence, but
the reviewer receipt has no release authority. The existing pilot freeze must
remain `HOLD_NOT_READY` while production authorization, restore proof, signed
client artifacts, policy publication, and live HTTP proof remain open.

If a behavior/specification discrepancy is found, the run stops at that
transition. Inputs and outputs are preserved, a corrective-transition receipt
and focused ADR are added, a regression fixture is recorded, and the chain is
rerun. Historical receipts and the frozen specification are never rewritten.
