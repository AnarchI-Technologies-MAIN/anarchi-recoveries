export type StatusTone = "neutral" | "success" | "warning" | "danger" | "info";

export interface StatusLabel {
  text: string;
  tone: StatusTone;
  ariaLabel: string;
}

export function createStatusLabel(text: string, tone: StatusTone): StatusLabel {
  if (text.trim() === "") {
    throw new Error("status text is required");
  }
  return Object.freeze({ text, tone, ariaLabel: `Status: ${text}` });
}

export interface MoneyLine {
  label: string;
  amount: string;
  currency: string;
  provenanceRef: string;
}

export function createMoneyLine(
  label: string,
  amount: string,
  currency: string,
  provenanceRef: string,
): MoneyLine {
  if ([label, amount, currency, provenanceRef].some((value) => value.trim() === "")) {
    throw new Error("money line requires label, decimal amount, currency, and provenance");
  }
  if (!/^[A-Z]{3}$/.test(currency)) {
    throw new Error("money line currency must be an uppercase ISO code");
  }
  if (!/^-?(0|[1-9][0-9]*)(\.[0-9]+)?$/.test(amount)) {
    throw new Error("money line amount must be a decimal string");
  }
  return Object.freeze({ label, amount, currency, provenanceRef });
}

export interface ProofChainItem {
  eventType: string;
  label: string;
  occurredAt: string;
  coreVersion: string;
  policyVersion: string;
  evaluationHash: string;
  decisionReceiptRef?: string;
}

export function createProofChainItem(input: ProofChainItem): ProofChainItem {
  for (const [name, value] of Object.entries(input)) {
    if (name !== "decisionReceiptRef" && typeof value === "string" && value.trim() === "") {
      throw new Error(`${name} is required for proof chain item`);
    }
  }
  if (!/^[a-f0-9]{64}$/.test(input.evaluationHash)) {
    throw new Error("proof chain evaluation hash must be lowercase SHA-256");
  }
  return Object.freeze({ ...input });
}

export interface ExternalActionButton {
  label: string;
  sideEffectLabel: string;
  targetSystem: string;
  confirmationRequired: true;
}

export function createExternalActionButton(
  label: string,
  sideEffectLabel: string,
  targetSystem: string,
): ExternalActionButton {
  if ([label, sideEffectLabel, targetSystem].some((value) => value.trim() === "")) {
    throw new Error("external action requires label, side-effect label, and target system");
  }
  return Object.freeze({ label, sideEffectLabel, targetSystem, confirmationRequired: true });
}
