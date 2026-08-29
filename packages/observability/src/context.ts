export interface WorkContext {
  traceId: string;
  correlationId: string;
  organizationId: string;
  projectId: string;
  aggregateId: string;
  eventId: string;
}

export const METRIC_NAMES = [
  "ingestion_throughput",
  "normalization_latency",
  "extraction_latency",
  "evaluation_latency",
  "queue_depth",
  "connector_failures",
  "opportunities_detected",
  "value_detected",
  "value_approved",
  "value_submitted",
  "value_invoiced",
  "value_collected",
  "deadline_risk",
  "evidence_completeness",
  "billing_accruals",
  "dead_letters",
  "vault_broker_failures",
  "anar_core_authorization_denies",
] as const;

export type MetricName = (typeof METRIC_NAMES)[number];

const CONTEXT_FIELDS = [
  "traceId",
  "correlationId",
  "organizationId",
  "projectId",
  "aggregateId",
  "eventId",
] as const satisfies readonly (keyof WorkContext)[];

export function requireWorkContext(input: WorkContext): WorkContext {
  for (const field of CONTEXT_FIELDS) {
    if (typeof input[field] !== "string" || input[field].trim() === "") {
      throw new Error(`${field} is required for observability`);
    }
  }
  return Object.freeze({ ...input });
}

export function metricLabels(context: WorkContext): WorkContext {
  return requireWorkContext(context);
}
