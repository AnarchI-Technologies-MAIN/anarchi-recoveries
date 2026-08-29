import assert from "node:assert/strict";
import { test } from "node:test";

import {
  createDecisionReceiptSummary,
  createImmutableLedger,
  createImmutableLedgerEvent,
  ledgerEventAsProofChainItem,
} from "../src/index.ts";

const HASH = "b".repeat(64);
const TIME = "2026-08-29T12:00:00Z";

function event(eventId: string, eventType: "EVIDENCE_INGESTED" | "ACTION_EXECUTED", occurredAt = TIME) {
  return createImmutableLedgerEvent({
    eventId,
    eventType,
    occurredAt,
    organizationId: "org-1",
    projectId: "project-1",
    aggregateId: "REC / 00481",
    summary: eventType === "ACTION_EXECUTED" ? "Notice submitted" : "Contract ingested",
    coreVersion: "recovery-core/0.1.0",
    policyVersion: "RECOVERIES_AUTH_V1",
    evaluationHash: HASH,
    sourceRefs: [`ledger/${eventId}`],
    ...(eventType === "ACTION_EXECUTED"
      ? {
          decisionReceipt: createDecisionReceiptSummary({
            decisionId: "decision-1",
            operation: "submit_external_notice",
            resource: "REC / 00481",
            result: "ALLOW",
            authorityClass: "TECHNICAL_AUTHORIZATION",
            policyVersion: "RECOVERIES_AUTH_V1",
            bindingId: "ENF-RECOVERIES-00001",
            expiresAt: "2026-08-29T13:00:00Z",
            decisionHash: HASH,
            receiptRef: "ledger/decision-1",
          }),
        }
      : {}),
  });
}

test("immutable ledger uses a fixed event vocabulary and deterministic ordering", () => {
  const later = event("event-b", "ACTION_EXECUTED", "2026-08-29T12:02:00Z");
  const earlier = event("event-a", "EVIDENCE_INGESTED", "2026-08-29T12:01:00Z");
  const ledger = createImmutableLedger({ organizationId: "org-1", events: [later, earlier] });
  assert.deepEqual(ledger.events.map((item) => item.eventId), ["event-a", "event-b"]);
  assert.equal(Object.isFrozen(ledger), true);
  assert.equal(ledger.events[1]!.decisionReceipt?.result, "ALLOW");
});

test("action events cannot appear without an authorization receipt or across tenants", () => {
  const valid = event("event-a", "ACTION_EXECUTED");
  const { decisionReceipt: _receipt, ...withoutReceipt } = valid;
  assert.throws(() => createImmutableLedgerEvent(withoutReceipt), /requires a decision receipt/);
  assert.throws(
    () => createImmutableLedger({ organizationId: "org-2", events: [valid] }),
    /organization boundary/,
  );
});

test("ledger events can feed the shared proof-chain item contract", () => {
  const item = ledgerEventAsProofChainItem(event("event-a", "ACTION_EXECUTED"));
  assert.equal(item.eventType, "ACTION_EXECUTED");
  assert.equal(item.decisionReceiptRef, "ledger/decision-1");
  assert.equal(item.evaluationHash, HASH);
});
