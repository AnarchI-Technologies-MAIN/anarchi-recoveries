import assert from "node:assert/strict";
import { test } from "node:test";

import { createAndroidClientBoundary, MOBILE_OPPORTUNITY_ORDER } from "../src/index.ts";

test("Android boundary fixes distribution, Keystore storage, and queued offline approval", () => {
  const boundary = createAndroidClientBoundary({ applicationId: "tech.anarchi.recoveries" });
  assert.deepEqual(boundary.distributionArtifacts, ["apk", "aab"]);
  assert.equal(boundary.credentialStorage, "Android Keystore");
  assert.equal(boundary.authTokensInLocalStorage, false);
  assert.equal(boundary.offlineApprovalState, "QUEUED");
  assert.deepEqual(boundary.reviewSectionOrder, MOBILE_OPPORTUNITY_ORDER);
});

test("Android application identity fails closed when not reverse-domain", () => {
  assert.throws(() => createAndroidClientBoundary({ applicationId: "recoveries" }), /reverse-domain/);
});
