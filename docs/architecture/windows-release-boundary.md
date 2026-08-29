# Windows release boundary

Status: Step 33 release-manifest baseline; no installer or signed binary

`apps/client/release-manifest.v1.json` pins the frozen Windows target:

```text
AnarchI-Recoveries-x64-Setup.exe
user-level install
```

The manifest is intentionally `NOT_RELEASED`. Its update channel is disabled
until a real artifact, Authenticode certificate proof, and release receipt
exist. `tools/client/verify_release_manifest.py` rejects an unreleased manifest
that claims an artifact or signature, and rejects a released manifest that
lacks both. The validator does not create, sign, publish, or update anything.

This keeps packaging, signing, and update authority separate from the client
shell boundary. A future release transition must add the exact binary digest,
certificate digest, release receipt, and independent verification before an
update channel can be enabled.
