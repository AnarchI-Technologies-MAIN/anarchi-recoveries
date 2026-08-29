import { type MoneyLine, type RecoveryDetailAction, type RecoveryStatus, createMoneyLine, createRecoveryStatus } from "./index.ts";

const NON_EMPTY = /\S/;

function requireText(value: string, field: string): string {
  if (!NON_EMPTY.test(value)) throw new Error(`${field} is required`);
  return value;
}

function requireMoney(value: MoneyLine, field: string): void {
  try {
    createMoneyLine(value.label, value.amount, value.currency, value.provenanceRef);
  } catch (error) {
    const detail = error instanceof Error ? error.message : "invalid money line";
    throw new Error(`${field} is invalid: ${detail}`);
  }
}

function freeze<T>(value: T): Readonly<T> {
  return Object.freeze(value);
}

function freezeArray<T>(values: readonly T[]): readonly T[] {
  return Object.freeze([...values]);
}

export type MobileClientTarget = "iphone" | "ipad";
export const MOBILE_OPPORTUNITY_ORDER = [
  "amount",
  "deadline",
  "delta",
  "entitlement",
  "proof",
  "financial_model",
  "approval",
] as const;
export type MobileOpportunitySection = (typeof MOBILE_OPPORTUNITY_ORDER)[number];

export interface MobileReviewScreen {
  screen: "mobile_review";
  target: MobileClientTarget;
  viewportWidthPx: number;
  recoveryId: string;
  amount: MoneyLine;
  deadline: string;
  delta: MoneyLine;
  entitlement: ReturnType<typeof createRecoveryStatus>;
  proofSummary: string;
  financialSummary: MoneyLine;
  approval: RecoveryDetailAction;
  sectionOrder: readonly MobileOpportunitySection[];
  drawingComparison: {
    available: boolean;
    deferPrompt?: "Open on desktop/iPad";
  };
}

export function createMobileReviewScreen(input: {
  target: MobileClientTarget;
  viewportWidthPx: number;
  recoveryId: string;
  amount: MoneyLine;
  deadline: string;
  delta: MoneyLine;
  entitlement: RecoveryStatus;
  proofSummary: string;
  financialSummary: MoneyLine;
  approval: RecoveryDetailAction;
  drawingComparisonAvailable?: boolean;
}): MobileReviewScreen {
  requireText(input.recoveryId, "mobile recovery id");
  requireText(input.proofSummary, "mobile proof summary");
  if (!Number.isInteger(input.viewportWidthPx) || input.viewportWidthPx < 320) {
    throw new Error("mobile viewport width must be an integer of at least 320px");
  }
  if (input.target === "iphone" && input.viewportWidthPx > 768) {
    throw new Error("iPhone target must be at or below 768px");
  }
  if (input.target === "ipad" && (input.viewportWidthPx < 768 || input.viewportWidthPx > 1100)) {
    throw new Error("iPad target must be between 768px and 1100px");
  }
  requireMoney(input.amount, "mobile amount");
  requireMoney(input.delta, "mobile delta");
  requireMoney(input.financialSummary, "mobile financial summary");
  const drawingComparison = input.drawingComparisonAvailable ?? false;
  return freeze({
    screen: "mobile_review",
    target: input.target,
    viewportWidthPx: input.viewportWidthPx,
    recoveryId: input.recoveryId,
    amount: input.amount,
    deadline: input.deadline,
    delta: input.delta,
    entitlement: createRecoveryStatus(input.entitlement),
    proofSummary: input.proofSummary,
    financialSummary: input.financialSummary,
    approval: input.approval,
    sectionOrder: MOBILE_OPPORTUNITY_ORDER,
    drawingComparison: drawingComparison ? { available: true } : { available: false, deferPrompt: "Open on desktop/iPad" },
  });
}
