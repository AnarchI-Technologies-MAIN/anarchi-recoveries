import { createProofChainItem, type ProofChainItem } from "./index.ts";

const ISO_TIMESTAMP = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,9})?Z$/;
const SHA256 = /^[a-f0-9]{64}$/;
const NON_EMPTY = /\S/;

function requireText(value: string, field: string): string {
  if (!NON_EMPTY.test(value)) throw new Error(`${field} is required`);
  return value;
}

function requireTimestamp(value: string, field: string): string {
  if (!ISO_TIMESTAMP.test(value) || Number.isNaN(Date.parse(value))) {
    throw new Error(`${field} must be an RFC 3339 UTC timestamp`);
  }
  return value;
}

function requireHash(value: string, field: string): string {
  if (!SHA256.test(value)) throw new Error(`${field} must be lowercase SHA-256`);
  return value;
}

function freeze<T>(value: T): Readonly<T> {
  return Object.freeze(value);
}

function freezeArray<T>(values: readonly T[]): readonly T[] {
  return Object.freeze([...values]);
}

export const IMMUTABLE_LEDGER_EVENT_TYPES = [
  "EVIDENCE_INGESTED",
  "FACT_EXTRACTED",
  "FACT_VERIFIED",
  "RECOVERY_EVALUATED",
  "PRICE_CALCULATED",
  "APPROVED",
  "ACTION_EXECUTED",
  "PAYMENT_OBSERVED",
  "ATTRIBUTION_RECONCILED",
  "SUCCESS_FEE_ACCRUED",
] as const;

export type ImmutableLedgerEventType = (typeof IMMUTABLE_LEDGER_EVENT_TYPES)[number];

export type LedgerDecisionResult = "ALLOW" | "DENY";

export interface DecisionReceiptSummary {
  decisionId: string;
  operation: string;
  resource: string;
  result: LedgerDecisionResult;
  authorityClass: string;
  policyVersion: string;
  bindingId: string;
  expiresAt: string;
  decisionHash: string;
  receiptRef: string;
}

export function createDecisionReceiptSummary(input: DecisionReceiptSummary): DecisionReceiptSummary {
  for (const [field, value] of Object.entries(input)) {
    if (field === "result") continue;
    requireText(value, `decision receipt ${field}`);
  }
  requireTimestamp(input.expiresAt, "decision receipt expiry");
  requireHash(input.decisionHash, "decision receipt hash");
  if (input.result !== "ALLOW" && input.result !== "DENY") {
    throw new Error("decision receipt result must be ALLOW or DENY");
  }
  return freeze({ ...input });
}

export interface ImmutableLedgerEvent {
  eventId: string;
  eventType: ImmutableLedgerEventType;
  occurredAt: string;
  organizationId: string;
  projectId: string;
  aggregateId: string;
  summary: string;
  coreVersion: string;
  policyVersion: string;
  evaluationHash: string;
  sourceRefs: readonly string[];
  decisionReceipt?: DecisionReceiptSummary;
}

export function createImmutableLedgerEvent(input: ImmutableLedgerEvent): ImmutableLedgerEvent {
  for (const field of ["eventId", "organizationId", "projectId", "aggregateId", "summary", "coreVersion", "policyVersion"] as const) {
    requireText(input[field], `ledger event ${field}`);
  }
  requireTimestamp(input.occurredAt, "ledger event timestamp");
  requireHash(input.evaluationHash, "ledger event evaluation hash");
  if (!IMMUTABLE_LEDGER_EVENT_TYPES.includes(input.eventType)) {
    throw new Error("ledger event type is not in the frozen immutable ledger vocabulary");
  }
  if (input.sourceRefs.length === 0 || input.sourceRefs.some((sourceRef) => !NON_EMPTY.test(sourceRef))) {
    throw new Error("ledger event requires nonempty source references");
  }
  if (["APPROVED", "ACTION_EXECUTED"].includes(input.eventType) && input.decisionReceipt === undefined) {
    throw new Error(`${input.eventType} ledger event requires a decision receipt`);
  }
  if (input.decisionReceipt !== undefined) createDecisionReceiptSummary(input.decisionReceipt);
  return freeze({ ...input, sourceRefs: freezeArray(input.sourceRefs) });
}

export interface ImmutableLedgerScreen {
  screen: "immutable_ledger";
  organizationId: string;
  events: readonly ImmutableLedgerEvent[];
}

export function createImmutableLedger(input: {
  organizationId: string;
  events: readonly ImmutableLedgerEvent[];
}): ImmutableLedgerScreen {
  requireText(input.organizationId, "ledger organization id");
  const events = input.events.map((event) => createImmutableLedgerEvent(event));
  const eventIds = events.map((event) => event.eventId);
  if (new Set(eventIds).size !== eventIds.length) {
    throw new Error("ledger event ids must be unique");
  }
  if (events.some((event) => event.organizationId !== input.organizationId)) {
    throw new Error("ledger event organization boundary mismatch");
  }
  const ordered = [...events].sort((left, right) => {
    const timestampOrder = left.occurredAt.localeCompare(right.occurredAt);
    return timestampOrder !== 0 ? timestampOrder : left.eventId.localeCompare(right.eventId);
  });
  return freeze({ screen: "immutable_ledger", organizationId: input.organizationId, events: freezeArray(ordered) });
}

export function ledgerEventAsProofChainItem(event: ImmutableLedgerEvent): ProofChainItem {
  const item = {
    eventType: event.eventType,
    label: event.summary,
    occurredAt: event.occurredAt,
    coreVersion: event.coreVersion,
    policyVersion: event.policyVersion,
    evaluationHash: event.evaluationHash,
  } as const;
  return event.decisionReceipt === undefined
    ? createProofChainItem(item)
    : createProofChainItem({ ...item, decisionReceiptRef: event.decisionReceipt.receiptRef });
}
