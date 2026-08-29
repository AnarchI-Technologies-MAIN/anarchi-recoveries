import assert from "node:assert/strict";
import { test } from "node:test";

import { dark, light, radius, spacing, themes, typography } from "../src/index.ts";

test("locks the Evidence Ledger light palette", () => {
  assert.equal(light.canvas, "#F4F5F1");
  assert.equal(light.brand, "#0B756D");
  assert.equal(light.danger, "#B63B35");
  assert.equal(light.warning, "#A85D00");
});

test("locks the dark counterpart without replacing the light product palette", () => {
  assert.equal(dark.canvas, "#0C0F0E");
  assert.equal(dark.brand, "#43D4C4");
  assert.deepEqual(Object.keys(themes), ["light", "dark"]);
});

test("locks typography, 4px spacing, and radius scales", () => {
  assert.equal(typography.primary, "Geist Sans");
  assert.equal(typography.evidence, "Geist Mono");
  assert.deepEqual(spacing, [4, 8, 12, 16, 24, 32, 48, 64]);
  assert.deepEqual(radius, { field: 4, tag: 4, button: 6, card: 8, panel: 12 });
});
