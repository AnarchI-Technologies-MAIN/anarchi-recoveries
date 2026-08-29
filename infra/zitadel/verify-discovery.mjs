import { createHash } from "node:crypto";

const expectedIssuer = process.env.RECOVERIES_ZITADEL_TEST_ISSUER;
if (!expectedIssuer) {
  throw new Error("RECOVERIES_ZITADEL_TEST_ISSUER is required");
}

const discoveryResponse = await fetch(`${expectedIssuer}/.well-known/openid-configuration`);
if (!discoveryResponse.ok) {
  throw new Error(`OIDC discovery failed with HTTP ${discoveryResponse.status}`);
}

const discoveryBytes = Buffer.from(await discoveryResponse.arrayBuffer());
const discovery = JSON.parse(discoveryBytes.toString("utf8"));

if (discovery.issuer !== expectedIssuer) {
  throw new Error(`issuer mismatch: expected ${expectedIssuer}, observed ${discovery.issuer}`);
}
if (typeof discovery.jwks_uri !== "string" || !discovery.jwks_uri.startsWith(`${expectedIssuer}/`)) {
  throw new Error("JWKS URI is absent or outside the exact issuer boundary");
}
if (!Array.isArray(discovery.id_token_signing_alg_values_supported)
    || !discovery.id_token_signing_alg_values_supported.includes("RS256")) {
  throw new Error("OIDC discovery does not advertise required RS256 signing support");
}

const jwksResponse = await fetch(discovery.jwks_uri);
if (!jwksResponse.ok) {
  throw new Error(`JWKS request failed with HTTP ${jwksResponse.status}`);
}

const jwksBytes = Buffer.from(await jwksResponse.arrayBuffer());
const jwks = JSON.parse(jwksBytes.toString("utf8"));
if (!Array.isArray(jwks.keys) || jwks.keys.length === 0) {
  throw new Error("JWKS contains no verification keys");
}
if (!jwks.keys.every((key) => key.use === "sig" && key.kty === "RSA" && key.alg === "RS256")) {
  throw new Error("JWKS contains a key outside the frozen local proof algorithm boundary");
}

const digest = (bytes) => createHash("sha256").update(bytes).digest("hex");
console.log(JSON.stringify({
  issuer: discovery.issuer,
  jwksUri: discovery.jwks_uri,
  signingAlgorithms: discovery.id_token_signing_alg_values_supported,
  keyCount: jwks.keys.length,
  discoverySha256: digest(discoveryBytes),
  jwksSha256: digest(jwksBytes),
}));
