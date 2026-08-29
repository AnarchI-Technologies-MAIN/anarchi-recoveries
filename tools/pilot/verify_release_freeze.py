#!/usr/bin/env python3
"""Validate the pilot freeze decision without enabling a release."""

from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / "docs/runbooks/pilot-release-freeze.v1.json"
SPEC_SHA256 = "0e3877aff0832db9cc0503d9a8769f2b867a1536441fba149874360fbb8f8869"
REQUIRED_GATES = {
    "precision_baseline_proven",
    "tenant_security_incidents_zero_proven",
    "evidence_backed_explanations_proven",
    "action_reconciliation_loop_proven",
    "policy_legal_docs_published",
    "support_process_operational",
    "incident_response_tested",
    "restore_tested",
    "security_review_complete",
    "governance_required_bindings_proven",
    "customer_export_delete_tested",
    "billing_attribution_tested",
    "production_migration_authorized",
    "client_release_artifacts_signed",
    "live_http_proof",
}


def validate(manifest: object) -> None:
    if not isinstance(manifest, dict):
        raise ValueError("pilot freeze manifest must be an object")
    if manifest.get("schema") != "anarchi.recoveries.pilot-release-freeze.v1":
        raise ValueError("unexpected pilot freeze schema")
    if manifest.get("spec_sha256") != SPEC_SHA256:
        raise ValueError("pilot freeze manifest is not pinned to the frozen spec")
    if manifest.get("status") not in {"HOLD_NOT_READY", "READY"}:
        raise ValueError("pilot freeze status is invalid")
    if manifest.get("release_decision") not in {"HOLD", "RELEASE"}:
        raise ValueError("pilot release decision is invalid")
    if manifest.get("production_mutated") is not False:
        raise ValueError("pilot freeze cannot claim production mutation")
    if (manifest["status"] == "HOLD_NOT_READY") != (manifest["release_decision"] == "HOLD"):
        raise ValueError("pilot status and release decision disagree")
    gates = manifest.get("gates")
    if not isinstance(gates, dict) or set(gates) != REQUIRED_GATES or any(not isinstance(value, bool) for value in gates.values()):
        raise ValueError("pilot gate set is incomplete")
    if manifest["status"] == "READY" and not all(gates.values()):
        raise ValueError("pilot release requires every gate")
    reasons = manifest.get("hold_reasons")
    if not isinstance(reasons, list) or any(not isinstance(reason, str) or not reason.strip() for reason in reasons):
        raise ValueError("pilot hold reasons must be explicit")
    if manifest["status"] == "READY" and reasons:
        raise ValueError("ready pilot cannot retain hold reasons")


def main() -> None:
    value = json.loads(MANIFEST.read_text(encoding="utf-8"))
    validate(value)
    passed = sum(value["gates"].values())
    print("pilot_freeze_manifest=PASS")
    print(f"pilot_gate_counts={passed}/{len(REQUIRED_GATES)}")
    print(f"pilot_release_decision={value['release_decision']}")


if __name__ == "__main__":
    main()
