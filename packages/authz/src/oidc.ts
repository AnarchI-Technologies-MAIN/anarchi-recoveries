import {
  createRemoteJWKSet,
  jwtVerify,
  type JWTVerifyGetKey,
} from "jose";

const ALLOWED_ALGORITHMS = ["RS256", "ES256"] as const;

export interface OidcVerifierConfig {
  issuer: string;
  audience: string;
  jwksUri: string;
  allowInsecureLocalhost?: boolean;
}

export interface VerifiedExternalIdentity {
  externalIssuer: string;
  externalSubject: string;
  tokenId: string | null;
  issuedAt: number;
  expiresAt: number;
}

export interface OidcTokenVerifier {
  verify(token: string): Promise<VerifiedExternalIdentity>;
}

function validatedUrl(
  value: string,
  field: "issuer" | "jwksUri",
  allowInsecureLocalhost: boolean,
): URL {
  const url = new URL(value);
  const isInsecureLocalhost =
    allowInsecureLocalhost &&
    url.protocol === "http:" &&
    (url.hostname === "localhost" || url.hostname === "127.0.0.1");

  if (url.protocol !== "https:" && !isInsecureLocalhost) {
    throw new Error(`${field} must use HTTPS outside an explicit localhost proof boundary`);
  }

  if (url.username || url.password || url.hash) {
    throw new Error(`${field} must not contain credentials or a fragment`);
  }

  return url;
}

export function createOidcTokenVerifier(
  config: OidcVerifierConfig,
  verificationKey?: JWTVerifyGetKey,
): OidcTokenVerifier {
  const allowInsecureLocalhost = config.allowInsecureLocalhost === true;
  const issuerUrl = validatedUrl(config.issuer, "issuer", allowInsecureLocalhost);
  const jwksUrl = validatedUrl(config.jwksUri, "jwksUri", allowInsecureLocalhost);

  if (!config.audience.trim()) {
    throw new Error("audience is required");
  }

  const key = verificationKey ?? createRemoteJWKSet(jwksUrl);
  const expectedIssuer = issuerUrl.toString().replace(/\/$/, "");

  return {
    async verify(token: string): Promise<VerifiedExternalIdentity> {
      if (!token.trim()) {
        throw new Error("OIDC token is required");
      }

      const { payload } = await jwtVerify(token, key, {
        issuer: expectedIssuer,
        audience: config.audience,
        algorithms: [...ALLOWED_ALGORITHMS],
        requiredClaims: ["iss", "sub", "iat", "exp"],
      });

      if (typeof payload.sub !== "string" || !payload.sub.trim()) {
        throw new Error("verified OIDC token has no non-empty subject");
      }
      if (typeof payload.iss !== "string") {
        throw new Error("verified OIDC token has no issuer");
      }
      if (typeof payload.iat !== "number" || typeof payload.exp !== "number") {
        throw new Error("verified OIDC token has invalid temporal claims");
      }

      return {
        externalIssuer: payload.iss,
        externalSubject: payload.sub,
        tokenId: typeof payload.jti === "string" ? payload.jti : null,
        issuedAt: payload.iat,
        expiresAt: payload.exp,
      };
    },
  };
}
