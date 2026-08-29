# RULE-AUTH-RECOVERIES-001: external notice requires human approval

Status: executable proof staged for Step 24 of SPEC-1.6

An external notice may be proposed for a recovery opportunity, but the
`submit_external_notice` operation is allowed only when the request carries a
non-empty human approval identifier. The request is scoped by subject,
organization, resource, purpose, policy version, and a hash of the exact
payload.

The pure gate returns `DENY` with `HUMAN_APPROVAL_REQUIRED` when approval is
absent and `ALLOW` with `HUMAN_APPROVAL_PRESENT` when it is present. Invalid
operation, purpose, identity, policy, or payload fields fail closed. This gate
does not send a notice, call a vendor, or persist a receipt.
