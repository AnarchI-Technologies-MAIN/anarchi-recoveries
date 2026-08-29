import assert from "node:assert/strict";
import { test } from "node:test";

import { createMoneyLine, createRecoveryDock, createRecoveryDockItem } from "../src/index.ts";

const money = (label: string, amount: string) => createMoneyLine(label, amount, "USD", "ledger/dock-1");

test("recovery dock exposes a read-only companion total, urgent items, and Open Rescue", () => {
  const dock = createRecoveryDock({
    openRecoverableTotal: money("Open recoverable total", "184720.00"),
    urgentItems: [
      createRecoveryDockItem({
        recoveryId: "REC / 00481",
        title: "Drawing quantity increase",
        value: money("Urgent value", "42810.00"),
        deadline: "2026-09-01T00:00:00Z",
      }),
    ],
  });
  assert.equal(dock.product, "ANARCHI / RECOVERIES");
  assert.equal(dock.persistentCompanion, true);
  assert.equal(dock.urgentCount, 1);
  assert.deepEqual(dock.openRescueAction, { label: "Open Rescue", navigationTarget: "rescue_overview" });
  assert.equal(Object.isFrozen(dock), true);
});

test("dock rejects duplicate urgent items and untraceable totals", () => {
  const item = createRecoveryDockItem({
    recoveryId: "REC / 00481",
    title: "Drawing quantity increase",
    value: money("Urgent value", "1.00"),
    deadline: "2026-09-01T00:00:00Z",
  });
  assert.throws(() => createRecoveryDock({ openRecoverableTotal: money("Total", "2.00"), urgentItems: [item, item] }), /unique/);
  assert.throws(
    () => createRecoveryDock({ openRecoverableTotal: { label: "Total", amount: "2", currency: "USD", provenanceRef: "" }, urgentItems: [] }),
    /provenance/,
  );
});
