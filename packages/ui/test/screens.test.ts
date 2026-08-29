import assert from "node:assert/strict";
import { test } from "node:test";

import {
  FINANCIAL_LINE_KINDS,
  PROOF_DOCUMENT_KINDS,
  RESCUE_METRIC_KEYS,
  createCashAttribution,
  createFactLine,
  createFinancialModel,
  createFinancialModelLine,
  createProofChain,
  createProofChainItem,
  createProofDocument,
  createProofPane,
  createProofViewer,
  createRateValue,
  createRecoveryDeadline,
  createRecoveryDetail,
  createRecoveryDetailAction,
  createRecoveryQueue,
  createRecoveryQueueRow,
  createRecoveryStatus,
  createRescueChart,
  createRescueMetric,
  createRescueOverview,
  createSendNoticeAction,
  createMoneyLine,
  type FinancialLineKind,
} from "../src/index.ts";

const AS_OF = "2026-08-29T12:00:00Z";
const HASH = "a".repeat(64);

function money(label: string, amount: string, provenanceRef = "ledger/eval-1") {
  return createMoneyLine(label, amount, "USD", provenanceRef);
}

function metric(key: (typeof RESCUE_METRIC_KEYS)[number]) {
  return createRescueMetric({ key, label: key, value: money(key, "10.00", `ledger/${key}`) });
}

test("rescue overview fixes the six metrics and allowed chart vocabulary", () => {
  const chart = createRescueChart({
    kind: "deadline_exposure",
    title: "Deadline exposure",
    points: [{ label: "Under 7 days", amount: money("At risk", "42.00", "ledger/deadline") }],
  });
  const screen = createRescueOverview({
    organizationId: "org-1",
    asOf: AS_OF,
    sourceLedgerRef: "ledger/rescue-1",
    metrics: RESCUE_METRIC_KEYS.map(metric),
    charts: [chart],
  });
  assert.equal(screen.screen, "rescue_overview");
  assert.deepEqual(screen.metrics.map((item) => item.key), RESCUE_METRIC_KEYS);
  assert.equal(Object.isFrozen(screen), true);
  assert.throws(
    () => createRescueOverview({ organizationId: "org-1", asOf: AS_OF, sourceLedgerRef: "ledger/1", metrics: [metric(RESCUE_METRIC_KEYS[0])], charts: [] }),
    /exactly the six frozen metrics/,
  );
});

test("recovery queue exposes fixed columns and rejects opaque confidence", () => {
  const row = createRecoveryQueueRow({
    recoveryId: "REC / 00481",
    value: money("Value", "481.00"),
    finding: "Drawing quantity increased",
    entitlement: createRecoveryStatus("SUPPORTED"),
    proof: createRecoveryStatus("READY"),
    deadline: createRecoveryDeadline({ dueAt: "2026-09-01T00:00:00Z" }),
  });
  const queue = createRecoveryQueue({ organizationId: "org-1", asOf: AS_OF, rows: [row] });
  assert.deepEqual(queue.columns, ["VALUE", "FINDING", "ENTITLEMENT", "PROOF", "DEADLINE"]);
  assert.equal("confidence" in queue.rows[0]!, false);
  assert.throws(
    () => createRecoveryQueueRow({ ...row, confidence: 0.99 } as typeof row & { confidence: number }),
    /opaque confidence/,
  );
});

function finding() {
  return {
    baseline: createFactLine({ label: "Baseline", value: "100", unit: "LF", provenanceRef: "doc/contract#4" }),
    observed: createFactLine({ label: "Observed", value: "140", unit: "LF", provenanceRef: "doc/drawing#9" }),
    delta: createFactLine({ label: "Delta", value: "40", unit: "LF", provenanceRef: "ledger/eval-1" }),
    entitlement: createFactLine({ label: "Entitlement", value: "Supported", provenanceRef: "rule/RULE-1" }),
    rule: { ruleId: "DRAWING_QUANTITY_INCREASE_V1", ruleVersion: "1", coreVersion: "recovery-core/0.1.0", policyVersion: "RECOVERIES_AUTH_V1" },
  };
}

function proofPane() {
  return createProofPane(PROOF_DOCUMENT_KINDS.map((kind) => createProofDocument({
    kind,
    label: kind,
    sourceRef: `s3://evidence/${kind}`,
    status: createRecoveryStatus("SUPPORTED"),
    sourceHash: HASH,
  })));
}

function financialModel() {
  const lines = FINANCIAL_LINE_KINDS.map((kind: FinancialLineKind) => createFinancialModelLine({
    kind,
    label: kind,
    amount: "10.00",
    currency: "USD",
    provenanceRef: `ledger/${kind}`,
    source: `source/${kind}`,
    contractSection: "4.1",
    pricingRule: "PRICE_V1",
    roundingRule: "HALF_UP_2DP",
    taxRule: "TAX_NONE",
    coreVersion: "recovery-core/0.1.0",
    evidenceCount: 1,
  }));
  return createFinancialModel({ lines, total: money("Total", "60.00", "ledger/total") });
}

test("recovery detail requires proof, financial traceability, and explicit actions", () => {
  const detail = createRecoveryDetail({
    screen: "recovery_detail",
    recoveryId: "REC / 00481",
    title: "Drawing quantity increase",
    amount: money("Recovery", "481.00"),
    project: "Project One",
    noticeDeadline: createRecoveryDeadline({ dueAt: "2026-09-01T00:00:00Z" }),
    finding: finding(),
    proof: proofPane(),
    financialModel: financialModel(),
    actions: [
      createRecoveryDetailAction({ kind: "reject", label: "Reject", effect: "Records a rejection in the ledger" }),
      createRecoveryDetailAction({ kind: "request_evidence", label: "Request Evidence", effect: "Creates an evidence request" }),
      createRecoveryDetailAction({ kind: "approve_prepare_notice", label: "Approve & Prepare Notice", effect: "Prepares a notice without submitting it" }),
    ],
    sendNotice: createSendNoticeAction("Procore"),
  });
  assert.equal(detail.actions.every((action) => action.confirmationRequired), true);
  assert.equal(detail.sendNotice?.confirmationRequired, true);
  assert.throws(
    () => createRecoveryDetailAction({ kind: "approve_prepare_notice", label: "Approve", effect: "" }),
    /effect is required/,
  );
});

test("proof chain and viewer expose accessible order plus verification metadata", () => {
  const nodes = ["baseline", "drawing", "recovery"].map((id, index) => ({
    id,
    item: createProofChainItem({
      eventType: "recovery.evaluated.v1",
      label: id,
      occurredAt: AS_OF,
      coreVersion: "recovery-core/0.1.0",
      policyVersion: "RECOVERIES_AUTH_V1",
      evaluationHash: HASH,
    }),
  }));
  const chain = createProofChain({
    nodes,
    edges: [
      { from: "baseline", to: "drawing", semantic: "verified" },
      { from: "drawing", to: "recovery", semantic: "candidate" },
    ],
  });
  const viewer = createProofViewer({
    screen: "proof_viewer",
    document: createProofDocument({ kind: "contract", label: "Contract", sourceRef: "s3://evidence/contract", status: createRecoveryStatus("SUPPORTED") }),
    highlightedSourceRegion: "page 4, paragraph 2",
    facts: [createFactLine({ label: "Quantity", value: "140", unit: "LF", provenanceRef: "doc/drawing#9" })],
    verificationIdentity: "verifier-1",
    verifiedAt: AS_OF,
    relationships: ["drawing supports recovery"],
    hash: HASH,
    chain,
  });
  assert.deepEqual(viewer.chain.accessibleLinear, [
    "1. baseline [origin]",
    "2. drawing [verified]",
    "3. recovery [candidate]",
  ]);
  assert.throws(() => createProofChain({ nodes, edges: [{ from: "missing", to: "drawing", semantic: "verified" }] }), /known nodes/);
});

test("cash attribution fails closed for verification-only and pre-cash fee states", () => {
  const base = {
    screen: "cash_attribution" as const,
    recoveryId: "REC / 00481",
    supportedValue: money("Supported", "100.00"),
    priorRecognizedValue: money("Prior", "0.00"),
    attributableCeiling: money("Ceiling", "100.00"),
    cashReceived: money("Cash", "0.00"),
    incrementalRecovery: money("Incremental", "0.00"),
    successFeeRate: createRateValue({ value: "15", unit: "%", provenanceRef: "policy/fee" }),
    successFee: money("Fee", "0.00"),
    customerRetained: money("Retained", "0.00"),
    verificationOnly: true,
    verificationMessage: "Independent verification completed. No incremental recovery attributed to AnarchI.",
  };
  assert.equal(createCashAttribution(base).verificationOnly, true);
  assert.throws(() => createCashAttribution({ ...base, successFee: money("Fee", "1.00") }), /zero incremental recovery/);
  const { verificationMessage: _verificationMessage, ...withoutVerificationMessage } = base;
  const nonVerification = { ...withoutVerificationMessage, verificationOnly: false, successFee: money("Fee", "1.00") };
  assert.throws(() => createCashAttribution(nonVerification), /before attributable cash/);
});
