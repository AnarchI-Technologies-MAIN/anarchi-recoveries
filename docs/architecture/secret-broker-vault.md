# Secret Broker / Vault boundary

Status: Step 26 non-production contract

Recoveries stores and passes only organization- and purpose-scoped secret
references. A reference is not a credential and is not authorization. The
action runner must present a valid Anar-Core `ALLOW` decision receipt whose
organization, purpose, binding, policy, and payload scope match the request.

The broker then asks Vault for a short-lived lease and returns only an opaque
capability containing the lease ID, secret reference, scope, operation, and
expiry. Plaintext secret material is intentionally absent from the Go types and
never crosses the application, database, NATS, trace, audit, analytics, or
client boundaries. A revoked/deleted credential, missing approval, wrong
purpose, wrong organization, or malformed lease fails closed.

The current adapter is an interface with local fakes for proof. Connecting a
real Vault deployment and a governed broker worker is a later infrastructure
transition and requires its own production receipt.
