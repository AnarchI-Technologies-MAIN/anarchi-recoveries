import { type MobileOpportunitySection, MOBILE_OPPORTUNITY_ORDER } from "./mobile.ts";

const NON_EMPTY = /\S/;

function requireText(value: string, field: string): string {
  if (!NON_EMPTY.test(value)) throw new Error(`${field} is required`);
  return value;
}

function freeze<T>(value: T): Readonly<T> {
  return Object.freeze(value);
}

export interface AndroidClientBoundary {
  target: "android";
  status: "SCAFFOLDED";
  distributionArtifacts: readonly ["apk", "aab"];
  credentialStorage: "Android Keystore";
  authTokensInLocalStorage: false;
  offlineApprovalState: "QUEUED";
  applicationId: string;
  reviewSectionOrder: readonly MobileOpportunitySection[];
}

export function createAndroidClientBoundary(input: { applicationId: string }): AndroidClientBoundary {
  const applicationId = requireText(input.applicationId, "Android application id");
  if (!/^[a-z][a-z0-9]*(?:\.[a-z0-9]+)+$/.test(applicationId)) {
    throw new Error("Android application id must be reverse-domain notation");
  }
  return freeze({
    target: "android",
    status: "SCAFFOLDED",
    distributionArtifacts: ["apk", "aab"],
    credentialStorage: "Android Keystore",
    authTokensInLocalStorage: false,
    offlineApprovalState: "QUEUED",
    applicationId,
    reviewSectionOrder: MOBILE_OPPORTUNITY_ORDER,
  });
}
