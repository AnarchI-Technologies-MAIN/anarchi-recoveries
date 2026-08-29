#!/usr/bin/env python3
"""Validate that the Step 27 policy baseline is review-only and fail-closed."""

from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / "docs/policies/policy-manifest.v1.json"
SPEC_SHA256 = "0e3877aff0832db9cc0503d9a8769f2b867a1536441fba149874360fbb8f8869"
REQUIRED_DOCUMENTS = {
    "MSA", "ORDER_FORM", "SUCCESS_FEE_SCHEDULE", "PRIVACY_POLICY", "DPA",
    "ACCEPTABLE_USE", "SECURITY_OVERVIEW", "SUBPROCESSOR_LIST", "SUPPORT_POLICY",
}


def validate(manifest: object) -> None:
    if not isinstance(manifest, dict):
        raise ValueError("policy manifest must be an object")
    if manifest.get("schema") != "anarchi.recoveries.policy-manifest.v1":
        raise ValueError("unexpected policy manifest schema")
    if manifest.get("status") != "DRAFT_FOR_REVIEW":
        raise ValueError("policy baseline must remain DRAFT_FOR_REVIEW")
    if manifest.get("spec_sha256") != SPEC_SHA256:
        raise ValueError("policy manifest is not pinned to the frozen spec")
    if manifest.get("production_activation") is not False:
        raise ValueError("policy baseline cannot activate production")
    documents = manifest.get("documents")
    if not isinstance(documents, list):
        raise ValueError("policy documents must be a list")
    ids = {item.get("id") for item in documents if isinstance(item, dict)}
    if ids != REQUIRED_DOCUMENTS:
        raise ValueError("required policy document set is incomplete or contains extras")
    if any(item.get("status") != "DRAFT_FOR_REVIEW" for item in documents):
        raise ValueError("customer-facing policy documents require review")
    privacy = manifest.get("privacy")
    if not isinstance(privacy, dict) or privacy.get("customer_owns_data") is not True:
        raise ValueError("customer data ownership must be explicit")
    if privacy.get("general_purpose_model_training_default") is not False:
        raise ValueError("general-purpose model training must be off by default")
    retention = manifest.get("retention")
    if not isinstance(retention, dict) or retention.get("termination_export_days") != 30:
        raise ValueError("termination export window must be 30 days")
    if retention.get("ordinary_backup_age_out_days") != 90:
        raise ValueError("ordinary backup age-out must be 90 days")
    if retention.get("deletion_is_lifecycle_state") is not True:
        raise ValueError("deletion must be modeled as lifecycle state")
    support = manifest.get("support")
    if not isinstance(support, dict) or support.get("pilot_service_credit_sla") is not False:
        raise ValueError("pilot service-credit SLA must remain false")
    functions = manifest.get("security_functions")
    if functions != ["GOVERN", "IDENTIFY", "PROTECT", "DETECT", "RESPOND", "RECOVER"]:
        raise ValueError("security function set is incomplete or reordered")


def main() -> None:
    validate(json.loads(MANIFEST.read_text(encoding="utf-8")))
    print("policy_manifest=PASS")
    print("production_activation=FALSE")


if __name__ == "__main__":
    main()
