import assert from "node:assert/strict";
import { test } from "node:test";

import {
  METRIC_NAMES,
  metricLabels,
  requireWorkContext,
  type WorkContext,
} from "../src/context.ts";

const context: WorkContext = {
  traceId: "trace-1",
  correlationId: "correlation-1",
  organizationId: "org-1",
  projectId: "project-1",
  aggregateId: "aggregate-1",
  eventId: "event-1",
};

test("requires every frozen work-context identifier", () => {
  assert.deepEqual(requireWorkContext(context), context);
  assert.deepEqual(metricLabels(context), context);
});

test("rejects a missing or blank identifier", () => {
  const invalid = { ...context, eventId: " " };
  assert.throws(() => requireWorkContext(invalid), /eventId is required/);
});

test("returns an immutable copy and exposes frozen metric names", () => {
  const labels = requireWorkContext(context);
  assert.notEqual(labels, context);
  assert.equal(Object.isFrozen(labels), true);
  assert.ok(METRIC_NAMES.includes("dead_letters"));
  assert.ok(METRIC_NAMES.includes("anar_core_authorization_denies"));
});
