import { createMoneyLine, type MoneyLine } from "./index.ts";

const ISO_TIMESTAMP = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,9})?Z$/;
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

export interface RecoveryDockItem {
  recoveryId: string;
  title: string;
  value: MoneyLine;
  deadline: string;
}

export function createRecoveryDockItem(input: RecoveryDockItem): RecoveryDockItem {
  requireText(input.recoveryId, "dock recovery id");
  requireText(input.title, "dock recovery title");
  requireMoney(input.value, "dock recovery value");
  requireTimestamp(input.deadline, "dock recovery deadline");
  return freeze({ ...input });
}

export interface RecoveryDock {
  screen: "recovery_dock";
  product: "ANARCHI / RECOVERIES";
  persistentCompanion: true;
  openRecoverableTotal: MoneyLine;
  urgentCount: number;
  urgentItems: readonly RecoveryDockItem[];
  openRescueAction: {
    label: "Open Rescue";
    navigationTarget: "rescue_overview";
  };
}

export function createRecoveryDock(input: {
  openRecoverableTotal: MoneyLine;
  urgentItems: readonly RecoveryDockItem[];
}): RecoveryDock {
  requireMoney(input.openRecoverableTotal, "dock open recoverable total");
  for (const item of input.urgentItems) createRecoveryDockItem(item);
  const ids = input.urgentItems.map((item) => item.recoveryId);
  if (new Set(ids).size !== ids.length) throw new Error("dock urgent recovery ids must be unique");
  return freeze({
    screen: "recovery_dock",
    product: "ANARCHI / RECOVERIES",
    persistentCompanion: true,
    openRecoverableTotal: input.openRecoverableTotal,
    urgentCount: input.urgentItems.length,
    urgentItems: freezeArray(input.urgentItems),
    openRescueAction: { label: "Open Rescue", navigationTarget: "rescue_overview" },
  });
}
