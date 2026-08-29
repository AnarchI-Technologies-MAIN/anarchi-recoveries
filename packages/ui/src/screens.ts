import {
  createExternalActionButton,
  createMoneyLine,
  createStatusLabel,
  type ExternalActionButton,
  type MoneyLine,
  type ProofChainItem,
  type StatusLabel,
  type StatusTone,
} from "./index.ts";

const ISO_TIMESTAMP = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,9})?Z$/;
const SHA256 = /^[a-f0-9]{64}$/;
const NON_EMPTY = /\S/;

function requireText(value: string, field: string): string {
  if (!NON_EMPTY.test(value)) {
    throw new Error(`${field} is required`);
  }
  return value;
}

function requireTimestamp(value: string, field: string): string {
  if (!ISO_TIMESTAMP.test(value) || Number.isNaN(Date.parse(value))) {
    throw new Error(`${field} must be an RFC 3339 UTC timestamp`);
  }
  return value;
}

function requireHash(value: string, field: string): string {
  if (!SHA256.test(value)) {
    throw new Error(`${field} must be lowercase SHA-256`);
  }
  return value;
}

function requireDecimal(value: string, field: string): string {
  if (!/^-?(0|[1-9][0-9]*)(\.[0-9]+)?$/.test(value)) {
    throw new Error(`${field} must be a decimal string`);
  }
  return value;
}

function requireMoney(value: MoneyLine, field: string): MoneyLine {
  try {
    return createMoneyLine(value.label, value.amount, value.currency, value.provenanceRef);
  } catch (error) {
    const detail = error instanceof Error ? error.message : "invalid money line";
    throw new Error(`${field} is invalid: ${detail}`);
  }
}

function isZeroDecimal(value: string): boolean {
  return /^-?0(?:\.0+)?$/.test(value);
}

function freeze<T>(value: T): Readonly<T> {
  return Object.freeze(value);
}

function freezeArray<T>(values: readonly T[]): readonly T[] {
  return Object.freeze([...values]);
}

export const RESCUE_METRIC_KEYS = [
  "potentiallyRecoverable",
  "detectedThisWeek",
  "atRiskUnder7Days",
  "ready",
  "submitted",
  "collected",
] as const;

export type RescueMetricKey = (typeof RESCUE_METRIC_KEYS)[number];

export const RESCUE_CHART_KINDS = [
  "recovery_progression",
  "cash_recovered_over_time",
  "deadline_exposure",
  "project_recovery_ranking",
] as const;

export type RescueChartKind = (typeof RESCUE_CHART_KINDS)[number];

export interface RescueMetric {
  key: RescueMetricKey;
  label: string;
  value: MoneyLine;
  delta?: MoneyLine;
}

export interface RescueChartPoint {
  label: string;
  amount: MoneyLine;
}

export interface RescueChart {
  kind: RescueChartKind;
  title: string;
  points: readonly RescueChartPoint[];
}

export interface RescueOverviewScreen {
  screen: "rescue_overview";
  organizationId: string;
  asOf: string;
  sourceLedgerRef: string;
  metrics: readonly RescueMetric[];
  charts: readonly RescueChart[];
}

export function createRescueMetric(input: {
  key: RescueMetricKey;
  label: string;
  value: MoneyLine;
  delta?: MoneyLine;
}): RescueMetric {
  requireText(input.label, "rescue metric label");
  requireMoney(input.value, "rescue metric value");
  if (input.delta !== undefined) requireMoney(input.delta, "rescue metric delta");
  return freeze({ ...input });
}

export function createRescueChart(input: {
  kind: RescueChartKind;
  title: string;
  points: readonly RescueChartPoint[];
}): RescueChart {
  if (!RESCUE_CHART_KINDS.includes(input.kind)) {
    throw new Error("rescue chart kind is not allowed by the frozen UI contract");
  }
  requireText(input.title, "rescue chart title");
  if (input.points.length === 0) {
    throw new Error("rescue chart requires numeric points");
  }
  for (const point of input.points) {
    requireText(point.label, "rescue chart point label");
    requireMoney(point.amount, "rescue chart amount");
  }
  return freeze({ ...input, points: freezeArray(input.points) });
}

export function createRescueOverview(input: {
  organizationId: string;
  asOf: string;
  sourceLedgerRef: string;
  metrics: readonly RescueMetric[];
  charts: readonly RescueChart[];
}): RescueOverviewScreen {
  requireText(input.organizationId, "rescue overview organization id");
  requireTimestamp(input.asOf, "rescue overview as-of");
  requireText(input.sourceLedgerRef, "rescue overview source ledger reference");
  if (input.metrics.length !== RESCUE_METRIC_KEYS.length) {
    throw new Error("rescue overview requires exactly the six frozen metrics");
  }
  const keys = input.metrics.map((metric) => metric.key);
  for (const rescueMetric of input.metrics) {
    createRescueMetric(rescueMetric);
  }
  for (const key of RESCUE_METRIC_KEYS) {
    if (keys.filter((candidate) => candidate === key).length !== 1) {
      throw new Error(`rescue overview metric ${key} must appear exactly once`);
    }
  }
  if (input.charts.length > 4) {
    throw new Error("rescue overview cannot exceed the four frozen chart forms");
  }
  const chartKinds = input.charts.map((chart) => chart.kind);
  for (const rescueChart of input.charts) {
    createRescueChart(rescueChart);
  }
  if (new Set(chartKinds).size !== chartKinds.length) {
    throw new Error("rescue overview chart kinds must be unique");
  }
  return freeze({
    screen: "rescue_overview",
    organizationId: input.organizationId,
    asOf: input.asOf,
    sourceLedgerRef: input.sourceLedgerRef,
    metrics: freezeArray(input.metrics),
    charts: freezeArray(input.charts),
  });
}

export const RECOVERY_QUEUE_COLUMNS = ["VALUE", "FINDING", "ENTITLEMENT", "PROOF", "DEADLINE"] as const;
export type RecoveryQueueColumn = (typeof RECOVERY_QUEUE_COLUMNS)[number];

export type RecoveryStatus =
  | "SUPPORTED"
  | "REVIEW"
  | "MISSING PROOF"
  | "READY"
  | "SUBMITTED"
  | "COLLECTED"
  | "VERIFICATION"
  | "DEADLINE";

const STATUS_TONES: Record<RecoveryStatus, StatusTone> = {
  SUPPORTED: "success",
  REVIEW: "warning",
  "MISSING PROOF": "danger",
  READY: "info",
  SUBMITTED: "info",
  COLLECTED: "success",
  VERIFICATION: "neutral",
  DEADLINE: "danger",
};

export function createRecoveryStatus(status: RecoveryStatus): StatusLabel {
  return createStatusLabel(status, STATUS_TONES[status]);
}

export interface RecoveryDeadline {
  dueAt: string;
  label: StatusLabel;
}

export interface RecoveryQueueRow {
  recoveryId: string;
  value: MoneyLine;
  finding: string;
  entitlement: StatusLabel;
  proof: StatusLabel;
  deadline: RecoveryDeadline;
}

export interface RecoveryQueueScreen {
  screen: "recovery_queue";
  organizationId: string;
  asOf: string;
  columns: readonly RecoveryQueueColumn[];
  rows: readonly RecoveryQueueRow[];
}

export function createRecoveryDeadline(input: { dueAt: string; status?: RecoveryStatus }): RecoveryDeadline {
  requireTimestamp(input.dueAt, "recovery deadline");
  return freeze({ dueAt: input.dueAt, label: createRecoveryStatus(input.status ?? "DEADLINE") });
}

export function createRecoveryQueueRow(input: RecoveryQueueRow): RecoveryQueueRow {
  requireText(input.recoveryId, "recovery queue id");
  requireText(input.finding, "recovery queue finding");
  requireMoney(input.value, "recovery queue value");
  if (Object.prototype.hasOwnProperty.call(input, "confidence")) {
    throw new Error("recovery queue must not expose an opaque confidence column");
  }
  return freeze({ ...input });
}

export function createRecoveryQueue(input: {
  organizationId: string;
  asOf: string;
  rows: readonly RecoveryQueueRow[];
}): RecoveryQueueScreen {
  requireText(input.organizationId, "recovery queue organization id");
  requireTimestamp(input.asOf, "recovery queue as-of");
  const ids = input.rows.map((row) => row.recoveryId);
  for (const row of input.rows) {
    createRecoveryQueueRow(row);
  }
  if (new Set(ids).size !== ids.length) {
    throw new Error("recovery queue ids must be unique");
  }
  return freeze({
    screen: "recovery_queue",
    organizationId: input.organizationId,
    asOf: input.asOf,
    columns: RECOVERY_QUEUE_COLUMNS,
    rows: freezeArray(input.rows),
  });
}

export interface FactLine {
  label: string;
  value: string;
  provenanceRef: string;
  unit?: string;
}

export function createFactLine(input: FactLine): FactLine {
  requireText(input.label, "fact label");
  requireText(input.value, "fact value");
  requireText(input.provenanceRef, "fact provenance reference");
  if (input.unit !== undefined) {
    requireText(input.unit, "fact unit");
  }
  return freeze({ ...input });
}

export interface RecoveryRuleMetadata {
  ruleId: string;
  ruleVersion: string;
  coreVersion: string;
  policyVersion: string;
}

export function createRecoveryRuleMetadata(input: RecoveryRuleMetadata): RecoveryRuleMetadata {
  for (const [field, value] of Object.entries(input)) {
    requireText(value, `recovery rule ${field}`);
  }
  return freeze({ ...input });
}

export interface FindingPane {
  baseline: FactLine;
  observed: FactLine;
  delta: FactLine;
  entitlement: FactLine;
  rule: RecoveryRuleMetadata;
}

export const PROOF_DOCUMENT_KINDS = ["contract", "revised_drawing", "rfi", "daily_log", "purchase_order"] as const;
export type ProofDocumentKind = (typeof PROOF_DOCUMENT_KINDS)[number];

export interface ProofDocument {
  kind: ProofDocumentKind;
  label: string;
  sourceRef: string;
  status: StatusLabel;
  sourceHash?: string;
}

export function createProofDocument(input: ProofDocument): ProofDocument {
  requireText(input.label, "proof document label");
  requireText(input.sourceRef, "proof document source reference");
  if (input.sourceHash !== undefined) {
    requireHash(input.sourceHash, "proof document source hash");
  }
  return freeze({ ...input });
}

export interface ProofPane {
  documents: readonly ProofDocument[];
}

export function createProofPane(documents: readonly ProofDocument[]): ProofPane {
  for (const document of documents) {
    createProofDocument(document);
  }
  for (const kind of PROOF_DOCUMENT_KINDS) {
    if (documents.filter((document) => document.kind === kind).length !== 1) {
      throw new Error(`proof pane requires exactly one ${kind.replace("_", " ")} document`);
    }
  }
  return freeze({ documents: freezeArray(documents) });
}

export type FinancialLineKind = "journeyman" | "apprentice" | "material" | "equipment" | "markup" | "tax";
export const FINANCIAL_LINE_KINDS: readonly FinancialLineKind[] = [
  "journeyman",
  "apprentice",
  "material",
  "equipment",
  "markup",
  "tax",
];

export interface FinancialModelLine extends MoneyLine {
  kind: FinancialLineKind;
  source: string;
  contractSection: string;
  pricingRule: string;
  roundingRule: string;
  taxRule: string;
  coreVersion: string;
  evidenceCount: number;
}

export function createFinancialModelLine(input: FinancialModelLine): FinancialModelLine {
  createMoneyLine(input.label, input.amount, input.currency, input.provenanceRef);
  for (const [field, value] of Object.entries(input)) {
    if (["evidenceCount", "amount"].includes(field)) continue;
    if (typeof value === "string") requireText(value, `financial line ${field}`);
  }
  if (!Number.isInteger(input.evidenceCount) || input.evidenceCount < 1) {
    throw new Error("financial line evidence count must be a positive integer");
  }
  return freeze({ ...input });
}

export interface FinancialModel {
  lines: readonly FinancialModelLine[];
  total: MoneyLine;
}

export function createFinancialModel(input: FinancialModel): FinancialModel {
  for (const line of input.lines) {
    createFinancialModelLine(line);
  }
  requireMoney(input.total, "financial model total");
  const kinds = input.lines.map((line) => line.kind);
  for (const kind of FINANCIAL_LINE_KINDS) {
    if (kinds.filter((candidate) => candidate === kind).length !== 1) {
      throw new Error(`financial model requires exactly one ${kind} line`);
    }
  }
  return freeze({ lines: freezeArray(input.lines), total: input.total });
}

export type RecoveryDetailActionKind = "reject" | "request_evidence" | "approve_prepare_notice";

export interface RecoveryDetailAction {
  kind: RecoveryDetailActionKind;
  label: string;
  effect: string;
  confirmationRequired: true;
}

export function createRecoveryDetailAction(input: {
  kind: RecoveryDetailActionKind;
  label: string;
  effect: string;
}): RecoveryDetailAction {
  requireText(input.label, "recovery detail action label");
  requireText(input.effect, "recovery detail action effect");
  if (input.kind === "approve_prepare_notice" && input.label !== "Approve & Prepare Notice") {
    throw new Error("notice preparation action must use its explicit product label");
  }
  return freeze({ ...input, confirmationRequired: true });
}

export interface RecoveryDetailScreen {
  screen: "recovery_detail";
  recoveryId: string;
  title: string;
  amount: MoneyLine;
  project: string;
  noticeDeadline: RecoveryDeadline;
  finding: FindingPane;
  proof: ProofPane;
  financialModel: FinancialModel;
  actions: readonly RecoveryDetailAction[];
  sendNotice?: ExternalActionButton;
}

export function createSendNoticeAction(targetSystem: string): ExternalActionButton {
  return createExternalActionButton("Send Notice", "External action", requireText(targetSystem, "notice target system"));
}

export function createRecoveryDetail(input: RecoveryDetailScreen): RecoveryDetailScreen {
  requireText(input.recoveryId, "recovery detail id");
  requireText(input.title, "recovery detail title");
  requireText(input.project, "recovery detail project");
  requireMoney(input.amount, "recovery detail amount");
  requireTimestamp(input.noticeDeadline.dueAt, "recovery detail notice deadline");
  createFactLine(input.finding.baseline);
  createFactLine(input.finding.observed);
  createFactLine(input.finding.delta);
  createFactLine(input.finding.entitlement);
  createRecoveryRuleMetadata(input.finding.rule);
  createProofPane(input.proof.documents);
  createFinancialModel(input.financialModel);
  if (input.actions.some((action) => action.confirmationRequired !== true)) {
    throw new Error("recovery detail actions require explicit confirmation");
  }
  const actionKinds = input.actions.map((action) => action.kind);
  for (const kind of ["reject", "request_evidence", "approve_prepare_notice"] as const) {
    if (actionKinds.filter((candidate) => candidate === kind).length !== 1) {
      throw new Error(`recovery detail requires exactly one ${kind} action`);
    }
  }
  return freeze({ ...input, actions: freezeArray(input.actions) });
}

export type ProofEdgeSemantic = "verified" | "candidate" | "historical" | "contradiction";

export interface ProofChainNode {
  id: string;
  item: ProofChainItem;
}

export interface ProofChainEdge {
  from: string;
  to: string;
  semantic: ProofEdgeSemantic;
}

export interface ProofChain {
  nodes: readonly ProofChainNode[];
  edges: readonly ProofChainEdge[];
  accessibleLinear: readonly string[];
}

export function createProofChain(input: {
  nodes: readonly ProofChainNode[];
  edges: readonly ProofChainEdge[];
}): ProofChain {
  if (input.nodes.length === 0) {
    throw new Error("proof chain requires nodes");
  }
  const ids = input.nodes.map((node) => node.id);
  if (ids.some((id) => !NON_EMPTY.test(id)) || new Set(ids).size !== ids.length) {
    throw new Error("proof chain node ids must be unique and nonempty");
  }
  const nodeSet = new Set(ids);
  for (const edge of input.edges) {
    if (!nodeSet.has(edge.from) || !nodeSet.has(edge.to) || edge.from === edge.to) {
      throw new Error("proof chain edges must reference distinct known nodes");
    }
  }
  const accessibleLinear = input.nodes.map((node, index) => {
    const incoming = input.edges.filter((edge) => edge.to === node.id);
    const relation = incoming.length === 0 ? "origin" : incoming.map((edge) => edge.semantic).join(", ");
    return `${index + 1}. ${node.item.label} [${relation}]`;
  });
  return freeze({
    nodes: freezeArray(input.nodes),
    edges: freezeArray(input.edges),
    accessibleLinear: freezeArray(accessibleLinear),
  });
}

export interface ProofViewerScreen {
  screen: "proof_viewer";
  document: ProofDocument;
  highlightedSourceRegion: string;
  facts: readonly FactLine[];
  verificationIdentity: string;
  verifiedAt: string;
  relationships: readonly string[];
  hash: string;
  chain: ProofChain;
}

export function createProofViewer(input: ProofViewerScreen): ProofViewerScreen {
  createProofDocument(input.document);
  requireText(input.highlightedSourceRegion, "proof viewer highlighted source region");
  requireText(input.verificationIdentity, "proof viewer verification identity");
  requireTimestamp(input.verifiedAt, "proof viewer verification time");
  requireHash(input.hash, "proof viewer hash");
  if (input.facts.length === 0 || input.relationships.length === 0) {
    throw new Error("proof viewer requires facts and relationships");
  }
  for (const fact of input.facts) createFactLine(fact);
  return freeze({ ...input, facts: freezeArray(input.facts), relationships: freezeArray(input.relationships) });
}

export interface RateValue {
  value: string;
  unit: "%";
  provenanceRef: string;
}

export function createRateValue(input: RateValue): RateValue {
  requireDecimal(input.value, "rate value");
  requireText(input.provenanceRef, "rate provenance reference");
  if (input.value.startsWith("-")) {
    throw new Error("rate value cannot be negative");
  }
  return freeze({ ...input });
}

export interface CashAttributionScreen {
  screen: "cash_attribution";
  recoveryId: string;
  supportedValue: MoneyLine;
  priorRecognizedValue: MoneyLine;
  attributableCeiling: MoneyLine;
  cashReceived: MoneyLine;
  incrementalRecovery: MoneyLine;
  successFeeRate: RateValue;
  successFee: MoneyLine;
  customerRetained: MoneyLine;
  verificationOnly: boolean;
  verificationMessage?: string;
}

export function createCashAttribution(input: CashAttributionScreen): CashAttributionScreen {
  requireText(input.recoveryId, "cash attribution recovery id");
  for (const [field, value] of Object.entries(input)) {
    if (["screen", "recoveryId", "successFeeRate", "verificationOnly", "verificationMessage"].includes(field)) continue;
    requireMoney(value as MoneyLine, `cash attribution ${field}`);
  }
  createRateValue(input.successFeeRate);
  if (input.verificationOnly) {
    if (!isZeroDecimal(input.incrementalRecovery.amount) || !isZeroDecimal(input.successFee.amount)) {
      throw new Error("verification-only attribution must show zero incremental recovery and zero success fee");
    }
    if (input.verificationMessage !== "Independent verification completed. No incremental recovery attributed to AnarchI.") {
      throw new Error("verification-only attribution message is fixed");
    }
  } else if (isZeroDecimal(input.cashReceived.amount) && !isZeroDecimal(input.successFee.amount)) {
    throw new Error("success fee cannot be displayed before attributable cash is received");
  }
  return freeze({ ...input });
}
