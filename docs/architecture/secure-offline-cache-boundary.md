# Secure offline cache boundary

Status: Step 34 limited-cache contract; OS-backed implementation is not yet
claimed

The native client crate accepts an `EncryptedCacheEntry` only when it has:

- one of the five allowed cache kinds from SPEC-1.6;
- organization and item identity;
- nonempty opaque ciphertext;
- an opaque OS key handle (for example, a future Windows credential-store
  handle);
- explicit capture and expiry timestamps;
- an observed-at timestamp that is still before expiry.

The API exposes no plaintext evidence, customer secret, authentication token,
or local-storage token path. Expired entries fail closed. Offline approval is
still only `QUEUED`; cache presence does not grant pricing, entitlement,
evaluation, or submission authority.

This is a boundary and validation layer, not an encryption implementation. Step
34 is not complete until the Windows credential store, encrypted evidence cache,
expiry cleanup, remote logout/revocation, and independent storage tests exist.
