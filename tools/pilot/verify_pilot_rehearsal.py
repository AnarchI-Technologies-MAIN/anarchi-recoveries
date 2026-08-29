#!/usr/bin/env python3
"""Verify a pilot rehearsal evidence bundle without enabling a release."""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
SPEC_SHA256 = "0e3877aff0832db9cc0503d9a8769f2b867a1536441fba149874360fbb8f8869"
CANONICALIZATION = "ANARCHI-JCS-COMPATIBLE-V1"


class VerificationError(ValueError):
    pass


def canonical_bytes(value: Any) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False).encode("utf-8")


def digest(value: Any) -> str:
    return hashlib.sha256(canonical_bytes(value)).hexdigest()


def file_digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def contains_key(value: Any, key: str) -> bool:
    if isinstance(value, dict):
        return key in value or any(contains_key(item, key) for item in value.values())
    if isinstance(value, list):
        return any(contains_key(item, key) for item in value)
    return False


def load(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise VerificationError(f"cannot read {path}: {error}") from error


def verify_receipt(receipt: dict[str, Any], previous_hash: str) -> None:
    if receipt.get("receipt_schema") != "anarchi.recoveries.pilot-rehearsal-transition.v1":
        raise VerificationError("unexpected rehearsal receipt schema")
    if receipt.get("spec_sha256") != SPEC_SHA256:
        raise VerificationError("receipt is not pinned to the frozen spec")
    if receipt.get("canonicalization") != CANONICALIZATION:
        raise VerificationError("receipt canonicalization mismatch")
    if receipt.get("previous_receipt_sha256") != previous_hash:
        raise VerificationError("receipt chain link mismatch")
    if receipt.get("authority", {}).get("production_mutated") is not False:
        raise VerificationError("receipt claims production mutation")
    if receipt.get("authority", {}).get("live_services_contacted") is not False:
        raise VerificationError("receipt claims live service contact")
    supplied_hash = receipt.get("receipt_sha256")
    if not isinstance(supplied_hash, str):
        raise VerificationError("receipt hash missing")
    unsigned = dict(receipt)
    unsigned.pop("receipt_sha256", None)
    if digest(unsigned) != supplied_hash:
        raise VerificationError("receipt hash mismatch")


def validate(bundle_dir: Path) -> dict[str, Any]:
    run_manifest = load(bundle_dir / "run-manifest.v1.json")
    report = load(bundle_dir / "evidence-report.v1.json")
    chain = load(bundle_dir / "receipt-chain.v1.json")
    review = load(bundle_dir / "independent-review.v1.json")
    packet = load(bundle_dir / "pilot-evidence-packet.v1.json")
    blind_packet = load(bundle_dir / "blind-review-packet.v1.json")
    adjudication_template = load(bundle_dir / "independent-adjudication.template.v1.json")
    if run_manifest.get("schema") != "anarchi.recoveries.pilot-rehearsal-run.v1":
        raise VerificationError("unexpected run manifest schema")
    if report.get("schema") != "anarchi.recoveries.pilot-evidence-report.v1":
        raise VerificationError("unexpected evidence report schema")
    if chain.get("schema") != "anarchi.recoveries.pilot-rehearsal-chain.v1":
        raise VerificationError("unexpected receipt chain schema")
    if review.get("schema") != "anarchi.recoveries.pilot-independent-review.v1":
        raise VerificationError("unexpected independent review schema")
    if packet.get("schema") != "anarchi.recoveries.pilot-evidence-packet.v1":
        raise VerificationError("unexpected evidence packet schema")
    if blind_packet.get("schema") != "anarchi.recoveries.pilot-blind-review-packet.v1":
        raise VerificationError("unexpected blind packet schema")
    if adjudication_template.get("schema") != "anarchi.recoveries.independent-adjudication.v1":
        raise VerificationError("unexpected adjudication template schema")
    for value in (run_manifest, report, review):
        if value.get("spec_sha256") != SPEC_SHA256:
            raise VerificationError("artifact is not pinned to the frozen spec")
    if run_manifest.get("authority", {}).get("production_mutated") is not False:
        raise VerificationError("run manifest claims production mutation")
    if run_manifest.get("authority", {}).get("live_services_contacted") is not False:
        raise VerificationError("run manifest claims live service contact")
    if report.get("pilot_recommendation") != "HOLD":
        raise VerificationError("rehearsal cannot recommend release")
    if report.get("precision_threshold") != "NOT_SET_BY_IMPLEMENTATION":
        raise VerificationError("implementation must not invent a precision threshold")
    metrics = report.get("metrics")
    if not isinstance(metrics, dict) or "candidate_extraction" not in metrics or "opportunity" not in metrics:
        raise VerificationError("separate precision metrics are required")
    if "aggregate_ai_quality" in metrics:
        raise VerificationError("aggregate AI quality metric is forbidden")
    receipts = chain.get("receipts")
    if not isinstance(receipts, list) or not receipts:
        raise VerificationError("receipt chain is empty")
    previous = ""
    for receipt in receipts:
        if not isinstance(receipt, dict):
            raise VerificationError("receipt chain member is not an object")
        verify_receipt(receipt, previous)
        previous = receipt["receipt_sha256"]
    if run_manifest.get("receipt_chain_root_sha256") != previous:
        raise VerificationError("run manifest chain root mismatch")
    if run_manifest.get("run_manifest_sha256") != digest({key: value for key, value in run_manifest.items() if key != "run_manifest_sha256"}):
        raise VerificationError("run manifest hash mismatch")
    if report.get("report_sha256") != digest({key: value for key, value in report.items() if key != "report_sha256"}):
        raise VerificationError("evidence report hash mismatch")
    if packet.get("packet_sha256") != digest({key: value for key, value in packet.items() if key != "packet_sha256"}):
        raise VerificationError("evidence packet hash mismatch")
    if blind_packet.get("packet_sha256") != digest({key: value for key, value in blind_packet.items() if key != "packet_sha256"}):
        raise VerificationError("blind packet hash mismatch")
    if contains_key(blind_packet, "expected") or contains_key(blind_packet, "label"):
        raise VerificationError("blind reviewer packet contains expected labels")
    if adjudication_template.get("blind_packet_sha256") != blind_packet.get("packet_sha256"):
        raise VerificationError("adjudication template packet hash mismatch")
    if set(item.get("case_id") for item in adjudication_template.get("cases", [])) != set(item.get("case_id") for item in packet.get("decision_trace", [])):
        raise VerificationError("adjudication template does not cover the packet")
    required_packet_fields = {
        "pilot_identity", "repository_commit", "spec_digest", "rule_registry_digest", "policy_digest",
        "pricing_version", "input_corpus_manifest", "evidence_hashes", "decision_trace", "calculation_trace",
        "human_adjudication", "authority_receipt", "action_payload_hash", "external_action_receipt",
        "payment_evidence", "attribution_result", "fee_calculation", "reconciliation_result", "denials", "unknowns", "final_state",
    }
    if set(packet) & required_packet_fields != required_packet_fields:
        raise VerificationError("evidence packet is missing a court-record field")
    if run_manifest.get("packet_sha256") != packet.get("packet_sha256") or run_manifest.get("blind_packet_sha256") != blind_packet.get("packet_sha256"):
        raise VerificationError("run manifest packet hashes do not match")
    if review.get("reviewed_packet_sha256") != packet.get("packet_sha256") or review.get("reviewed_blind_packet_sha256") != blind_packet.get("packet_sha256"):
        raise VerificationError("review packet hashes do not match")
    if review.get("adjudication_template_sha256") != file_digest(bundle_dir / "independent-adjudication.template.v1.json"):
        raise VerificationError("review adjudication template hash mismatch")
    authority = packet.get("authority_receipt", {})
    if authority.get("result") == "ALLOW":
        authority_unsigned = dict(authority)
        supplied_authority_hash = authority_unsigned.pop("decision_hash", None)
        if not isinstance(supplied_authority_hash, str) or digest(authority_unsigned) != supplied_authority_hash:
            raise VerificationError("authority decision receipt hash mismatch")
    if run_manifest.get("report_sha256") != report.get("report_sha256"):
        raise VerificationError("run manifest report hash mismatch")
    if review.get("reviewed_receipt_chain_root_sha256") != previous:
        raise VerificationError("review receipt root mismatch")
    if review.get("decision") != "PENDING" or review.get("reviewer_id") is not None:
        raise VerificationError("unreviewed evidence must remain explicitly pending")
    case_results = report.get("case_results")
    if not isinstance(case_results, list) or not case_results or any(not item.get("expected_match") for item in case_results):
        raise VerificationError("synthetic case expectation failed")
    stack = run_manifest.get("stack")
    if not isinstance(stack, dict) or stack.get("compose_config") != "PASS":
        raise VerificationError("isolated compose configuration was not proven")
    if not isinstance(stack.get("rendered_config_sha256"), str) or len(stack["rendered_config_sha256"]) != 64:
        raise VerificationError("rendered compose configuration digest is missing")
    if stack.get("production_endpoint_contact_count") != 0:
        raise VerificationError("production endpoint contact count is non-zero")
    for relative_path, expected_hash in run_manifest.get("artifact_sha256", {}).items():
        path = Path(relative_path)
        if not path.is_absolute():
            path = ROOT / path
        if not path.is_file() or file_digest(path) != expected_hash:
            raise VerificationError(f"artifact hash mismatch: {relative_path}")
    step_paths = [bundle_dir / name for name in (
        "STEP-43-PILOT-TEST-STACK-REHEARSAL-RECEIPT.json",
        "STEP-44-PILOT-EVIDENCE-BASELINE-RECEIPT.json",
        "STEP-45-PILOT-INDEPENDENT-REVIEW-RECEIPT.json",
    )]
    if not all(path.is_file() for path in step_paths):
        step_paths = [
            ROOT / "proof/m3/STEP-43-PILOT-TEST-STACK-REHEARSAL-RECEIPT.json",
            ROOT / "proof/m3/STEP-44-PILOT-EVIDENCE-BASELINE-RECEIPT.json",
            ROOT / "proof/m3/STEP-45-PILOT-INDEPENDENT-REVIEW-RECEIPT.json",
        ]
    step_receipts = [load(path) for path in step_paths]
    previous_step = ""
    for step in step_receipts:
        if step.get("receipt_schema") != "anarchi.recoveries.step-transition-receipt.v1":
            raise VerificationError("unexpected step receipt schema")
        if step.get("spec_sha256") != SPEC_SHA256 or step.get("canonicalization") != CANONICALIZATION:
            raise VerificationError("step receipt pin mismatch")
        if step.get("previous_receipt_sha256") != previous_step:
            raise VerificationError("step receipt chain link mismatch")
        if step.get("authority", {}).get("production_mutated") is not False:
            raise VerificationError("step receipt claims production mutation")
        unsigned = dict(step)
        supplied = unsigned.pop("receipt_sha256", None)
        if not isinstance(supplied, str) or digest(unsigned) != supplied:
            raise VerificationError("step receipt hash mismatch")
        for relative_path, expected_hash in step.get("artifact_sha256", {}).items():
            path = Path(relative_path)
            if not path.is_absolute():
                path = ROOT / path
            if not path.is_file() or file_digest(path) != expected_hash:
                raise VerificationError(f"step artifact hash mismatch: {relative_path}")
        previous_step = supplied
    if step_receipts[0].get("run_id") != run_manifest.get("run_id"):
        raise VerificationError("step receipt run identifier mismatch")
    return {
        "case_count": len(case_results),
        "receipt_count": len(receipts),
        "receipt_chain_root": previous,
        "step_chain_root": previous_step,
        "pilot_recommendation": report["pilot_recommendation"],
        "review": review["decision"],
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("bundle_dir", type=Path, nargs="?", default=ROOT / "proof/m3/pilot-rehearsal")
    args = parser.parse_args(argv)
    try:
        result = validate(args.bundle_dir)
        print("pilot_rehearsal_verification=PASS")
        for key, value in result.items():
            print(f"{key}={value}")
        return 0
    except (OSError, VerificationError) as error:
        print(f"pilot_rehearsal_verification=FAIL: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
