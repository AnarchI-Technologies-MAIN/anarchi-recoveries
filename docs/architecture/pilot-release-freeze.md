# Pilot release freeze

Status: Step 42 `HOLD / NOT_READY`

The pilot freeze manifest enumerates the complete release decision rather than
letting a passing unit suite imply a pilot. It includes the pilot goals
(precision, no tenant/security incidents, evidence-backed explanations, and a
successful action/reconciliation loop) plus the operational gates from the
frozen specification: legal/policy publication, support, incident response,
restore, security review, governance proof, customer export/delete, billing
attribution, authorized production migration, signed client artifacts, and
live HTTP proof.

Only the governance-binding and billing-attribution gates are currently proven
by local artifacts. The manifest therefore stays `HOLD_NOT_READY` with explicit
reasons. `tools/pilot/verify_release_freeze.py` rejects a `READY` decision until
every gate is true and hold reasons are empty. It never enables deployment or
changes production.
