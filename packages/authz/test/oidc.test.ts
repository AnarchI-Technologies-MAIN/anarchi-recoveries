import assert from "node:assert/strict";
import { test } from "node:test";
import {
  SignJWT,
  createLocalJWKSet,
  exportJWK,
  generateKeyPair,
} from "jose";

import { createOidcTokenVerifier } from "../src/oidc.ts";

const issuer = "https://identity.example.test";
const audience = "recoveries-api";

async function proofKeys() {
  const { privateKey, publicKey } = await generateKeyPair("RS256");
  const publicJwk = await exportJWK(publicKey);
  publicJwk.kid = "proof-key-1";
  publicJwk.alg = "RS256";
  return {
    privateKey,
    localJwks: createLocalJWKSet({ keys: [publicJwk] }),
  };
}

async function signedToken(
  privateKey: Awaited<ReturnType<typeof proofKeys>>["privateKey"],
  overrides: { issuer?: string; audience?: string; subject?: string | null } = {},
) {
  const now = Math.floor(Date.now() / 1000);
  let token = new SignJWT({
    "urn:zitadel:iam:org:id:proof": "external-org-is-provenance-only",
  })
    .setProtectedHeader({ alg: "RS256", kid: "proof-key-1" })
    .setIssuer(overrides.issuer ?? issuer)
    .setAudience(overrides.audience ?? audience)
    .setIssuedAt(now)
    .setExpirationTime(now + 300)
    .setJti("proof-token-1");

  if (overrides.subject !== null) {
    token = token.setSubject(overrides.subject ?? "external-user-1");
  }

  return token.sign(privateKey);
}

test("accepts a correctly signed issuer/audience/subject token", async () => {
  const { privateKey, localJwks } = await proofKeys();
  const verifier = createOidcTokenVerifier(
    { issuer, audience, jwksUri: `${issuer}/oauth/v2/keys` },
    localJwks,
  );

  const identity = await verifier.verify(await signedToken(privateKey));

  assert.deepEqual(identity, {
    externalIssuer: issuer,
    externalSubject: "external-user-1",
    tokenId: "proof-token-1",
    issuedAt: identity.issuedAt,
    expiresAt: identity.expiresAt,
  });
  assert.equal("organizationId" in identity, false);
});

test("rejects a wrong issuer", async () => {
  const { privateKey, localJwks } = await proofKeys();
  const verifier = createOidcTokenVerifier(
    { issuer, audience, jwksUri: `${issuer}/oauth/v2/keys` },
    localJwks,
  );

  await assert.rejects(
    verifier.verify(await signedToken(privateKey, { issuer: "https://attacker.example" })),
    /unexpected "iss" claim value/,
  );
});

test("rejects a wrong audience", async () => {
  const { privateKey, localJwks } = await proofKeys();
  const verifier = createOidcTokenVerifier(
    { issuer, audience, jwksUri: `${issuer}/oauth/v2/keys` },
    localJwks,
  );

  await assert.rejects(
    verifier.verify(await signedToken(privateKey, { audience: "other-api" })),
    /unexpected "aud" claim value/,
  );
});

test("rejects a signed token without subject", async () => {
  const { privateKey, localJwks } = await proofKeys();
  const verifier = createOidcTokenVerifier(
    { issuer, audience, jwksUri: `${issuer}/oauth/v2/keys` },
    localJwks,
  );

  await assert.rejects(
    verifier.verify(await signedToken(privateKey, { subject: null })),
    /missing required "sub" claim/,
  );
});

test("requires HTTPS unless localhost proof mode is explicit", () => {
  assert.throws(
    () => createOidcTokenVerifier({
      issuer: "http://identity.example.test",
      audience,
      jwksUri: "http://identity.example.test/oauth/v2/keys",
    }),
    /must use HTTPS/,
  );

  assert.doesNotThrow(() => createOidcTokenVerifier({
    issuer: "http://127.0.0.1:58080",
    audience,
    jwksUri: "http://127.0.0.1:58080/oauth/v2/keys",
    allowInsecureLocalhost: true,
  }));
});
