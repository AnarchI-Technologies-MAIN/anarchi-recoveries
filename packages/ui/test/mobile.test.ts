import assert from "node:assert/strict";
import { test } from "node:test";

import { createMoneyLine, createMobileReviewScreen, createRecoveryDetailAction, MOBILE_OPPORTUNITY_ORDER } from "../src/index.ts";

const money = (label: string, amount: string) => createMoneyLine(label, amount, "USD", "ledger/mobile-1");
const approval = createRecoveryDetailAction({ kind: "approve_prepare_notice", label: "Approve & Prepare Notice", effect: "Prepare notice" });

test("iPhone review fixes the frozen opportunity order and defers heavy drawing comparison", () => {
  const screen = createMobileReviewScreen({
    target: "iphone",
    viewportWidthPx: 390,
    recoveryId: "REC / 00481",
    amount: money("Amount", "481.00"),
    deadline: "2026-09-01T00:00:00Z",
    delta: money("Delta", "40.00"),
    entitlement: "SUPPORTED",
    proofSummary: "Contract, drawing, and RFI linked",
    financialSummary: money("Financial summary", "481.00"),
    approval,
  });
  assert.deepEqual(screen.sectionOrder, MOBILE_OPPORTUNITY_ORDER);
  assert.deepEqual(screen.drawingComparison, { available: false, deferPrompt: "Open on desktop/iPad" });
  assert.equal(screen.entitlement.text, "SUPPORTED");
});

test("iPad can expose drawing comparison, while invalid viewport boundaries fail closed", () => {
  const screen = createMobileReviewScreen({
    target: "ipad",
    viewportWidthPx: 1024,
    recoveryId: "REC / 00481",
    amount: money("Amount", "481.00"),
    deadline: "2026-09-01T00:00:00Z",
    delta: money("Delta", "40.00"),
    entitlement: "REVIEW",
    proofSummary: "Proof pending",
    financialSummary: money("Financial summary", "481.00"),
    approval,
    drawingComparisonAvailable: true,
  });
  assert.deepEqual(screen.drawingComparison, { available: true });
  assert.throws(
    () => createMobileReviewScreen({
      target: "iphone",
      viewportWidthPx: 1024,
      recoveryId: screen.recoveryId,
      amount: screen.amount,
      deadline: screen.deadline,
      delta: screen.delta,
      entitlement: "REVIEW",
      proofSummary: screen.proofSummary,
      financialSummary: screen.financialSummary,
      approval,
    }),
    /iPhone target/,
  );
});
