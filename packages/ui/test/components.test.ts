import assert from "node:assert/strict";
import { test } from "node:test";

import {
  createExternalActionButton,
  createMoneyLine,
  createProofChainItem,
  createStatusLabel,
} from "../src/index.ts";

test("status labels carry text and an accessible semantic", () => {
  const value = createStatusLabel("Needs verification", "warning");
  assert.equal(value.ariaLabel, "Status: Needs verification");
  assert.equal(Object.isFrozen(value), true);
  assert.throws(() => createStatusLabel(" ", "warning"), /status text/);
});

test("money lines require decimal strings, explicit currency, and provenance", () => {
  assert.deepEqual(createMoneyLine("Supported value", "4938.23", "USD", "eval-1"), {
    label: "Supported value",
    amount: "4938.23",
    currency: "USD",
    provenanceRef: "eval-1",
  });
  assert.throws(() => createMoneyLine("Value", "4,938.23", "USD", "eval-1"), /decimal string/);
  assert.throws(() => createMoneyLine("Value", "1.00", "usd", "eval-1"), /ISO code/);
});

test("proof chain items require a lowercase SHA-256 evaluation hash", () => {
  const item = createProofChainItem({
    eventType: "recovery.evaluated.v1",
    label: "Evaluation",
    occurredAt: "2026-08-29T00:00:00Z",
    coreVersion: "recovery-core/0.1.0",
    policyVersion: "RECOVERIES_AUTH_V1",
    evaluationHash: "a".repeat(64),
  });
  assert.equal(item.eventType, "recovery.evaluated.v1");
  assert.throws(() => createProofChainItem({ ...item, evaluationHash: "not-a-hash" }), /SHA-256/);
});

test("external actions visibly require confirmation and name the side effect", () => {
  const action = createExternalActionButton("Send notice", "External action", "Procore");
  assert.equal(action.confirmationRequired, true);
  assert.equal(action.sideEffectLabel, "External action");
  assert.throws(() => createExternalActionButton("Send", "", "Procore"), /side-effect label/);
});
