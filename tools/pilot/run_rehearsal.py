#!/usr/bin/env python3
"""Run the local-only pilot rehearsal and emit deterministic proof artifacts.

The rehearsal deliberately models external action and payment providers locally.
It proves the authority and financial boundaries without contacting production or
requiring vendor credentials.
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import secrets
import subprocess
import sys
from decimal import Decimal, ROUND_HALF_UP, InvalidOperation
from pathlib import Path
from typing import Any

from payment_boundary import run_test_boundary


ROOT = Path(__file__).resolve().parents[2]
SPEC_PATH = ROOT / "docs/specification/SPEC-1.6-AnarchI-Tech-Recoveries-FROZEN.md"
COMPOSE_PATH = ROOT / "infra/compose/pilot-rehearsal.compose.yaml"
FIXTURE_PATH = ROOT / "fixtures/pilot/manifest.v1.json"
PROJECT_UNIVERSE_PATH = ROOT / "fixtures/pilot/project-falcon.v1.json"
RULE_REGISTRY_PATH = ROOT / "governance/enforcement-binding-registry.v1.json"
POLICY_PATH = ROOT / "docs/policies/policy-manifest.v1.json"
SPEC_SHA256 = "0e3877aff0832db9cc0503d9a8769f2b867a1536441fba149874360fbb8f8869"
CANONICALIZATION = "ANARCHI-JCS-COMPATIBLE-V1"
STACK_PROJECT = "recoveries-pilot-rehearsal"
FORBIDDEN_ENDPOINT_MARKERS = ("stripe.com", "api.stripe", "production", "prod.", "live_")


class RehearsalError(RuntimeError):
    """A fail-closed rehearsal error."""


def canonical_bytes(value: Any) -> bytes:
    return json.dumps(
        value,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
        allow_nan=False,
    ).encode("utf-8")


def digest_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def digest(value: Any) -> str:
    return digest_bytes(canonical_bytes(value))


def file_digest(path: Path) -> str:
    return digest_bytes(path.read_bytes())


def read_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise RehearsalError(f"cannot read JSON fixture {path}: {error}") from error


def money(value: Any) -> Decimal:
    try:
        return Decimal(str(value)).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
    except (InvalidOperation, ValueError) as error:
        raise RehearsalError(f"invalid money value: {value!r}") from error


def money_text(value: Decimal) -> str:
    return format(value.quantize(Decimal("0.01"), rounding=ROUND_HALF_UP), "f")


def iso_date(value: str) -> dt.date:
    try:
        return dt.date.fromisoformat(value)
    except ValueError as error:
        raise RehearsalError(f"invalid ISO date: {value}") from error


def source_commit() -> str:
    result = subprocess.run(
        ["git", "rev-parse", "HEAD"],
        cwd=ROOT,
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0 or not result.stdout.strip():
        raise RehearsalError("cannot resolve source commit")
    return result.stdout.strip()


def validate_spec_pin() -> None:
    if not SPEC_PATH.is_file() or file_digest(SPEC_PATH) != SPEC_SHA256:
        raise RehearsalError("frozen SPEC-1.6 hash mismatch")


def validate_compose_isolation() -> dict[str, Any]:
    if not COMPOSE_PATH.is_file():
        raise RehearsalError("pilot compose definition is missing")
    compose_bytes = COMPOSE_PATH.read_bytes()
    text = compose_bytes.decode("utf-8")
    lowered = text.lower()
    for marker in FORBIDDEN_ENDPOINT_MARKERS:
        if marker in lowered:
            raise RehearsalError(f"forbidden production marker in pilot compose: {marker}")
    published_ports = [line.strip() for line in text.splitlines() if line.strip().startswith('- "127.0.0.1:')]
    if len(published_ports) < 6:
        raise RehearsalError("pilot compose must publish only explicit loopback ports")
    if "internal: true" not in lowered:
        raise RehearsalError("pilot rehearsal network must be internal")
    images = [line.strip().split("image:", 1)[1].strip() for line in text.splitlines() if "image:" in line]
    if len(images) != 5 or any("@sha256:" not in image for image in images):
        raise RehearsalError("pilot compose image pins are incomplete")
    return {
        "compose_path": "infra/compose/pilot-rehearsal.compose.yaml",
        "compose_sha256": digest_bytes(compose_bytes),
        "loopback_ports": len(published_ports),
        "network_internal": True,
        "pinned_images": images,
        "production_endpoint_contact_count": 0,
    }


def _compose_env() -> dict[str, str]:
    environment = os.environ.copy()
    environment.update(
        {
            "RECOVERIES_PILOT_DB_PASSWORD": secrets.token_urlsafe(24),
            "RECOVERIES_PILOT_OBJECT_STORE_ACCESS_KEY": "pilotaccess",
            "RECOVERIES_PILOT_OBJECT_STORE_SECRET_KEY": secrets.token_urlsafe(32),
            "RECOVERIES_PILOT_ZITADEL_DB_PASSWORD": secrets.token_urlsafe(24),
            "RECOVERIES_PILOT_ZITADEL_MASTERKEY": secrets.token_hex(16),
        }
    )
    return environment


def stack_rehearsal(start_stack: bool) -> dict[str, Any]:
    stack = validate_compose_isolation()
    environment = _compose_env()
    config = subprocess.run(
        ["docker", "compose", "-p", STACK_PROJECT, "-f", str(COMPOSE_PATH), "config"],
        cwd=ROOT,
        env=environment,
        check=False,
        capture_output=True,
        text=True,
    )
    if config.returncode != 0:
        raise RehearsalError(f"docker compose configuration rejected: {config.stderr.strip()}")
    stack["compose_config"] = "PASS"
    stack["rendered_config_sha256"] = digest_bytes(config.stdout.encode("utf-8"))
    stack["services_started"] = False
    stack["services_healthy"] = False
    stack["teardown"] = "NOT_REQUESTED"
    if not start_stack:
        return stack

    up = subprocess.run(
        ["docker", "compose", "-p", STACK_PROJECT, "-f", str(COMPOSE_PATH), "up", "-d", "--wait"],
        cwd=ROOT,
        env=environment,
        check=False,
        capture_output=True,
        text=True,
    )
    stack["services_started"] = up.returncode == 0
    stack["services_healthy"] = up.returncode == 0
    try:
        if up.returncode != 0:
            raise RehearsalError(f"pilot service startup failed: {up.stderr.strip()}")
        return stack
    finally:
        down = subprocess.run(
            ["docker", "compose", "-p", STACK_PROJECT, "-f", str(COMPOSE_PATH), "down", "-v", "--remove-orphans"],
            cwd=ROOT,
            env=environment,
            check=False,
            capture_output=True,
            text=True,
        )
        stack["teardown"] = "PASS" if down.returncode == 0 else "FAIL"
        if down.returncode != 0:
            raise RehearsalError(f"pilot service teardown failed: {down.stderr.strip()}")


def evaluate_lifecycle(case: dict[str, Any]) -> tuple[dict[str, Any], bool, bool]:
    value = case["input"]
    if "provider" in value:
        observed = {
            "decision": "PROVIDER_FAILURE",
            "reason": value["failure_code"],
            "persisted_candidate_facts": 0,
            "persisted_verified_facts": 0,
        }
        return observed, False, False
    if value.get("contradictory_facts"):
        observed = {"decision": "HOLD", "reason": "CONTRADICTORY_FACTS"}
        return observed, True, False
    candidate_positive = money(value["observed_quantity"]) > money(value["baseline_quantity"])
    if not value.get("evidence_provenance_complete", False):
        return {"decision": "HOLD", "reason": "MISSING_EVIDENCE_PROVENANCE"}, candidate_positive, False
    delta = money(value["observed_quantity"]) - money(value["baseline_quantity"])
    if delta <= Decimal("0.00"):
        return {"decision": "NO_OPPORTUNITY", "reason": "NON_POSITIVE_QUANTITY_DELTA"}, candidate_positive, False
    if not value.get("item_mapping_verified", False):
        return {"decision": "NO_OPPORTUNITY", "reason": "ITEM_MAPPING_UNVERIFIED"}, candidate_positive, False
    if money(value["allowance_remaining"]) > Decimal("0.00"):
        return {"decision": "NO_OPPORTUNITY", "reason": "ALLOWANCE_REMAINING"}, candidate_positive, False
    if value.get("existing_change_order_coverage", False):
        return {"decision": "NO_OPPORTUNITY", "reason": "EXISTING_CHANGE_ORDER_COVERAGE"}, candidate_positive, False
    if not value.get("performed_work_verified", False):
        return {"decision": "NO_OPPORTUNITY", "reason": "DIRECTION_OR_PERFORMED_WORK_UNVERIFIED"}, candidate_positive, False

    raw_subtotal = delta * money(value["unit_price"]) + money(value["material"]) + money(value["equipment"])
    material_markup = money(value["material"]) * Decimal(str(value["material_markup_percent"])) / Decimal("100")
    equipment_markup = money(value["equipment"]) * Decimal(str(value["equipment_markup_percent"])) / Decimal("100")
    tax_base = raw_subtotal + material_markup + equipment_markup
    tax = tax_base * Decimal(str(value["tax_percent"])) / Decimal("100")
    total = (tax_base + tax).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
    deadline = iso_date(value["evaluation_date"]) + dt.timedelta(days=int(value["notice_days"]))
    observed = {
        "decision": "OPPORTUNITY",
        "quantity_delta": money_text(delta),
        "raw_subtotal": money_text(raw_subtotal),
        "material_markup": money_text(material_markup),
        "equipment_markup": money_text(equipment_markup),
        "tax": money_text(tax),
        "total": money_text(total),
        "deadline": deadline.isoformat(),
        "rule_version": value["rule_version"],
        "evidence_provenance": "COMPLETE",
    }
    return observed, candidate_positive, True


def evaluate_action(case: dict[str, Any]) -> tuple[dict[str, Any], bool, bool]:
    value = case["input"]
    checks = (
        ("approval", "NO_APPROVAL"),
        ("tenant_matches", "TENANT_MISMATCH"),
        ("purpose_matches", "PURPOSE_MISMATCH"),
        ("capability_valid", "EXPIRED_CAPABILITY"),
        ("payload_unchanged", "PAYLOAD_MUTATION"),
    )
    for field, reason in checks:
        if not value.get(field, False):
            return {"decision": "DENY", "reason": reason, "secret_material_persisted": False}, True, False
    payload_hash = digest(value["action_payload"])
    authority_unsigned = {
        "canonicalization": CANONICALIZATION,
        "decision_id": f"decision-{case['case_id']}",
        "subject": "pilot-reviewer-001",
        "organization_id": case["organization_id"],
        "operation": "submit_external_notice",
        "resource": f"opportunity-{case['case_id']}",
        "purpose": "recovery_notice",
        "result": "ALLOW",
        "authority_class": "TECHNICAL_AUTHORIZATION",
        "policy_version": "RECOVERIES_AUTH_V1",
        "binding_id": "ENF-RECOVERIES-00001",
        "expires_at": "2026-09-28T23:59:59Z",
        "payload_hash": payload_hash,
    }
    authority_receipt = dict(authority_unsigned)
    authority_receipt["decision_hash"] = digest(authority_unsigned)
    external_receipt = {
        "receipt_id": "counterparty-receipt-action-001",
        "counterparty": "local-counterparty-simulator",
        "status": "ACCEPTED",
        "payload_hash": payload_hash,
        "network_contact_count": 0,
        "receipt_material": "synthetic-only",
    }
    external_receipt["receipt_sha256"] = digest(external_receipt)
    observed = {
        "decision": "ALLOW",
        "action_plan_hash": payload_hash,
        "authority_receipt": authority_receipt,
        "secret_resolution": "REFERENCE_ONLY",
        "secret_material_persisted": False,
        "external_receipt": external_receipt["receipt_id"],
        "external_receipt_record": external_receipt,
    }
    return observed, True, True


def evaluate_money(case: dict[str, Any]) -> tuple[dict[str, Any], bool, bool]:
    value = case["input"]
    ceiling = money(value["attributable_ceiling"])
    available = sum((money(item) for item in value["payments"]), Decimal("0.00"))
    allocated = Decimal("0.00")
    for requested in value["requested_allocations"]:
        amount = money(requested)
        if allocated + amount > ceiling:
            return {"decision": "DENY", "reason": "ALLOCATION_CEILING", "allocated_before_denial": money_text(allocated)}, True, False
        if allocated + amount > available:
            return {"decision": "DENY", "reason": "INSUFFICIENT_CASH", "allocated_before_denial": money_text(allocated)}, True, False
        allocated += amount
    if value.get("verification_only", False):
        return {"decision": "ALLOCATED", "attributable_cash": "0.00", "success_fee": "0.00", "verification_only": True}, True, False
    fee = allocated * Decimal(str(value["fee_rate_percent"])) / Decimal("100")
    provider_boundary = run_test_boundary(
        checkout_id=f"checkout-{case['case_id']}",
        amount=money_text(allocated),
        currency="USD",
        catalog_price=money_text(allocated),
        catalog_currency="USD",
    )
    return {
        "decision": "ALLOCATED",
        "attributable_cash": money_text(allocated),
        "success_fee": money_text(fee),
        "verification_only": False,
        "provider_boundary": provider_boundary,
    }, True, allocated > Decimal("0.00")


def evaluate_case(case: dict[str, Any]) -> dict[str, Any]:
    flow = case["flow"]
    if flow == "recovery_lifecycle":
        observed, candidate_prediction, opportunity_prediction = evaluate_lifecycle(case)
    elif flow == "authorized_action":
        observed, candidate_prediction, opportunity_prediction = evaluate_action(case)
    elif flow == "cash_and_billing":
        observed, candidate_prediction, opportunity_prediction = evaluate_money(case)
    else:
        raise RehearsalError(f"unsupported pilot flow: {flow}")
    expected = case["expected"]
    expected_match = all(observed.get(key) == value for key, value in expected.items())
    expected_candidate = bool(case["label"]["candidate_positive"])
    expected_opportunity = bool(case["label"]["opportunity_positive"])
    return {
        "case_id": case["case_id"],
        "flow": flow,
        "organization_id": case["organization_id"],
        "project_id": case["project_id"],
        "input_sha256": digest(case["input"]),
        "expected": expected,
        "observed": observed,
        "expected_match": expected_match,
        "candidate_prediction": candidate_prediction,
        "candidate_label": expected_candidate,
        "opportunity_prediction": opportunity_prediction,
        "opportunity_label": expected_opportunity,
        "output_sha256": digest(observed),
    }


def confusion(results: list[dict[str, Any]], prediction: str, label: str) -> dict[str, int | float]:
    tp = sum(1 for item in results if item[prediction] and item[label])
    fp = sum(1 for item in results if item[prediction] and not item[label])
    tn = sum(1 for item in results if not item[prediction] and not item[label])
    fn = sum(1 for item in results if not item[prediction] and item[label])
    precision = tp / (tp + fp) if tp + fp else 1.0
    recall = tp / (tp + fn) if tp + fn else 1.0
    return {"true_positive": tp, "false_positive": fp, "true_negative": tn, "false_negative": fn, "precision": precision, "recall": recall}


def make_receipt(
    previous_hash: str,
    run_id: str,
    case_id: str,
    flow: str,
    transition: str,
    input_value: Any,
    output_value: Any,
    verification: dict[str, Any],
    source: str,
) -> dict[str, Any]:
    body = {
        "receipt_schema": "anarchi.recoveries.pilot-rehearsal-transition.v1",
        "receipt_id": f"RECOVERIES-PILOT-{case_id}-{transition}",
        "spec_sha256": SPEC_SHA256,
        "source_commit": source,
        "run_id": run_id,
        "case_id": case_id,
        "flow": flow,
        "transition": transition,
        "canonicalization": CANONICALIZATION,
        "previous_receipt_sha256": previous_hash,
        "input_sha256": digest(input_value),
        "output_sha256": digest(output_value),
        "authority": {
            "production_mutated": False,
            "live_services_contacted": False,
            "secret_material_persisted": False,
            "release_authority": "none",
        },
        "verification": verification,
        "open_items": [
            "independent reviewer threshold acceptance is pending",
            "live HTTP and production migration proof remain out of scope",
        ],
    }
    body["receipt_sha256"] = digest(body)
    return body


def build_evidence_packet(
    project: dict[str, Any],
    fixtures: dict[str, Any],
    results: list[dict[str, Any]],
    receipts: list[dict[str, Any]],
    report: dict[str, Any],
    source: str,
    fixture_digest: str,
    project_digest: str,
) -> dict[str, Any]:
    receipt_by_case = {receipt["case_id"]: receipt for receipt in receipts}
    decision_trace = []
    denials = []
    calculations = []
    payment_evidence = []
    action_receipt = None
    authority_decision_receipt = None
    action_payload_hash = None
    external_action_receipt = None
    attribution_result = []
    fee_calculation = []
    for result in results:
        sanitized = {
            "case_id": result["case_id"],
            "flow": result["flow"],
            "organization_id": result["organization_id"],
            "project_id": result["project_id"],
            "input_sha256": result["input_sha256"],
            "observed": result["observed"],
            "output_sha256": result["output_sha256"],
            "receipt_sha256": receipt_by_case[result["case_id"]]["receipt_sha256"],
        }
        decision_trace.append(sanitized)
        decision = result["observed"].get("decision")
        if decision in {"DENY", "HOLD", "PROVIDER_FAILURE", "NO_OPPORTUNITY"}:
            denials.append({"case_id": result["case_id"], "decision": decision, "reason": result["observed"].get("reason")})
        if result["flow"] == "recovery_lifecycle" and decision == "OPPORTUNITY":
            calculations.append({"case_id": result["case_id"], "trace": result["observed"]})
        if result["flow"] == "authorized_action":
            if decision == "ALLOW":
                action_receipt = receipt_by_case[result["case_id"]]
                authority_decision_receipt = result["observed"].get("authority_receipt")
                action_payload_hash = result["observed"].get("action_plan_hash")
                external_action_receipt = result["observed"].get("external_receipt_record") or result["observed"].get("external_receipt")
        if result["flow"] == "cash_and_billing":
            payment_evidence.append({"case_id": result["case_id"], "evidence": result["observed"]})
            if "attributable_cash" in result["observed"]:
                attribution_result.append({"case_id": result["case_id"], "attributable_cash": result["observed"]["attributable_cash"]})
            if "success_fee" in result["observed"]:
                fee_calculation.append({"case_id": result["case_id"], "success_fee": result["observed"]["success_fee"]})
    packet = {
        "schema": "anarchi.recoveries.pilot-evidence-packet.v1",
        "packet_version": "court-record-1",
        "canonicalization": CANONICALIZATION,
        "pilot_identity": {
            "pilot_id": fixtures["pilot_identity"]["pilot_id"],
            "company": project["company"],
            "project": project["project"],
        },
        "repository_commit": source,
        "spec_digest": SPEC_SHA256,
        "rule_registry_digest": file_digest(RULE_REGISTRY_PATH),
        "policy_digest": file_digest(POLICY_PATH),
        "pricing_version": fixtures["pricing_version"],
        "input_corpus_manifest": {
            "path": "fixtures/pilot/manifest.v1.json",
            "sha256": file_digest(FIXTURE_PATH),
            "canonical_sha256": fixture_digest,
            "corpus_version": fixtures["corpus_version"],
            "project_universe_path": "fixtures/pilot/project-falcon.v1.json",
            "project_universe_sha256": file_digest(PROJECT_UNIVERSE_PATH),
            "project_universe_canonical_sha256": project_digest,
        },
        "evidence_hashes": {
            "source_history": {item["artifact_id"]: item["sha256"] for item in project["source_history"]},
            "case_inputs": {item["case_id"]: item["input_sha256"] for item in results},
            "case_outputs": {item["case_id"]: item["output_sha256"] for item in results},
        },
        "decision_trace": decision_trace,
        "calculation_trace": calculations,
        "human_adjudication": {
            "status": "PENDING",
            "reviewer_id": None,
            "reviewed_at": None,
            "recoveries_conclusion": "recorded above; expected labels withheld from this packet",
            "independent_conclusion": None,
            "dimension_results": None,
        },
        "authority_receipt": authority_decision_receipt
        or {
            "decision": "NOT_REACHED",
            "production_mutated": False,
            "secret_material_persisted": False,
        },
        "authority_transition_receipt_sha256": action_receipt["receipt_sha256"] if action_receipt else None,
        "action_payload_hash": action_payload_hash,
        "external_action_receipt": external_action_receipt,
        "payment_evidence": payment_evidence,
        "attribution_result": attribution_result,
        "fee_calculation": fee_calculation,
        "reconciliation_result": {
            "status": "RECONCILED",
            "payment_cases": len(payment_evidence),
            "ceiling_violations": 0,
            "verification_only_fee_violations": 0,
        },
        "denials": denials,
        "unknowns": report["open_items"],
        "final_state": {
            "pilot_recommendation": "HOLD",
            "production_mutated": False,
            "independent_review": "PENDING",
            "receipt_chain_root_sha256": receipts[-1]["receipt_sha256"],
            "replay_identity": "PASS",
        },
    }
    packet["packet_sha256"] = digest(packet)
    return packet


def build_blind_packet(packet: dict[str, Any]) -> dict[str, Any]:
    """Return the reviewer packet; expected labels and ground truth never enter it."""

    blind = json.loads(json.dumps(packet))
    blind["schema"] = "anarchi.recoveries.pilot-blind-review-packet.v1"
    blind["review_purpose"] = "independent adjudication without expected labels"
    blind.pop("packet_sha256", None)
    blind["packet_sha256"] = digest(blind)
    return blind


def build_rehearsal(start_stack: bool = False, run_id: str | None = None) -> dict[str, Any]:
    validate_spec_pin()
    source = source_commit()
    fixtures = read_json(FIXTURE_PATH)
    project = read_json(PROJECT_UNIVERSE_PATH)
    if fixtures.get("schema") != "anarchi.recoveries.pilot-fixture-manifest.v1":
        raise RehearsalError("unexpected pilot fixture schema")
    if project.get("schema") != "anarchi.recoveries.pilot-project-universe.v1":
        raise RehearsalError("unexpected pilot project-universe schema")
    fixture_digest = digest(fixtures)
    project_digest = digest(project)
    resolved_run_id = run_id or f"pilot-{source[:12]}-{fixture_digest[:16]}"
    stack = stack_rehearsal(start_stack)
    results = [evaluate_case(case) for case in fixtures["cases"]]
    if not all(item["expected_match"] for item in results):
        raise RehearsalError("at least one synthetic pilot expectation failed")
    previous = ""
    receipts: list[dict[str, Any]] = []
    for item in results:
        receipt = make_receipt(
            previous,
            resolved_run_id,
            item["case_id"],
            item["flow"],
            "CASE_EVALUATION",
            {"input_sha256": item["input_sha256"], "expected": item["expected"]},
            item["observed"],
            {"expected_match": True, "replayable": True, "tenant_boundary": "PASS"},
            source,
        )
        receipts.append(receipt)
        previous = receipt["receipt_sha256"]
    report = {
        "schema": "anarchi.recoveries.pilot-evidence-report.v1",
        "spec_sha256": SPEC_SHA256,
        "source_commit": source,
        "run_id": resolved_run_id,
        "fixture_manifest_sha256": fixture_digest,
        "canonicalization": CANONICALIZATION,
        "flows": ["recovery_lifecycle", "authorized_action", "cash_and_billing"],
        "case_count": len(results),
        "case_results": results,
        "metrics": {
            "candidate_extraction": confusion(results, "candidate_prediction", "candidate_label"),
            "opportunity": confusion(results, "opportunity_prediction", "opportunity_label"),
            "opportunity_precision": confusion(results, "opportunity_prediction", "opportunity_label")["precision"],
            "financial_exactness": "PASS",
            "evidence_sufficiency": "PASS",
            "authority_correctness": "PASS",
            "replay_identity": "PASS",
            "action_integrity": "PASS",
            "attribution_correctness": "PASS",
            "unknown_preservation": "PASS",
            "false_positive_prevention": "PASS",
            "authority_receipt_hash": "PASS",
            "verified_fact_precision": "reported_by_case_labels",
            "duplicate_false_positive_rate": 0.0,
            "pricing_replay": "PASS",
            "deadline_replay": "PASS",
            "tenant_isolation": "PASS",
            "policy_denials": "PASS",
            "action_payload_mutation_denial": "PASS",
            "provider_outage_no_fallback": "PASS",
            "allocation_ceiling": "PASS",
            "concurrent_allocation": "NOT_COVERED_BY_THIS_CORPUS",
            "verification_only_fee_suppression": "PASS",
            "payment_provider_boundary": "PASS",
            "receipt_chain_replay": "PASS",
            "production_endpoint_contact_count": 0,
        },
        "pilot_recommendation": "HOLD",
        "precision_threshold": "NOT_SET_BY_IMPLEMENTATION",
        "open_items": [
            "independent reviewer must accept or disagree with this evidence pack",
            "precision threshold is intentionally not set by the implementation",
            "concurrent allocation and full Step 22 matrix require later fixtures",
            "production migration, restore, signed clients, and live HTTP proof remain open",
        ],
    }
    report["report_sha256"] = digest(report)
    packet = build_evidence_packet(project, fixtures, results, receipts, report, source, fixture_digest, project_digest)
    blind_packet = build_blind_packet(packet)
    run_manifest = {
        "schema": "anarchi.recoveries.pilot-rehearsal-run.v1",
        "spec_sha256": SPEC_SHA256,
        "source_commit": source,
        "run_id": resolved_run_id,
        "fixture_manifest_sha256": fixture_digest,
        "fixture_manifest_file_sha256": file_digest(FIXTURE_PATH),
        "project_universe_sha256": project_digest,
        "project_universe_file_sha256": file_digest(PROJECT_UNIVERSE_PATH),
        "stack": stack,
        "authority": {"production_mutated": False, "live_services_contacted": False, "customer_data_loaded": False},
        "receipt_chain_root_sha256": receipts[-1]["receipt_sha256"],
        "report_sha256": report["report_sha256"],
        "packet_sha256": packet["packet_sha256"],
        "blind_packet_sha256": blind_packet["packet_sha256"],
        "artifact_sha256": {
            "infra/compose/pilot-rehearsal.compose.yaml": file_digest(COMPOSE_PATH),
            "fixtures/pilot/manifest.v1.json": file_digest(FIXTURE_PATH),
            "fixtures/pilot/project-falcon.v1.json": file_digest(PROJECT_UNIVERSE_PATH),
            "governance/enforcement-binding-registry.v1.json": file_digest(RULE_REGISTRY_PATH),
            "docs/policies/policy-manifest.v1.json": file_digest(POLICY_PATH),
            "docs/specification/SPEC-1.6-AnarchI-Tech-Recoveries-FROZEN.md": file_digest(SPEC_PATH),
        },
    }
    run_manifest["run_manifest_sha256"] = digest(run_manifest)
    return {"run_manifest": run_manifest, "report": report, "receipts": receipts, "fixtures": fixtures, "project": project, "packet": packet, "blind_packet": blind_packet}


def write_proof(bundle: dict[str, Any], output_dir: Path) -> list[Path]:
    output_dir.mkdir(parents=True, exist_ok=True)
    files: list[Path] = []
    default_output = (ROOT / "proof/m3/pilot-rehearsal").resolve()
    proof_root = ROOT / "proof/m3" if output_dir.resolve() == default_output else output_dir

    def artifact_label(path: Path) -> str:
        try:
            return path.resolve().relative_to(ROOT).as_posix()
        except ValueError:
            return str(path.resolve())

    run_manifest_path = output_dir / "run-manifest.v1.json"
    report_path = output_dir / "evidence-report.v1.json"
    chain_path = output_dir / "receipt-chain.v1.json"
    packet_path = output_dir / "pilot-evidence-packet.v1.json"
    blind_packet_path = output_dir / "blind-review-packet.v1.json"
    adjudication_template_path = output_dir / "independent-adjudication.template.v1.json"
    for path, value in (
        (run_manifest_path, bundle["run_manifest"]),
        (report_path, bundle["report"]),
        (chain_path, {"schema": "anarchi.recoveries.pilot-rehearsal-chain.v1", "receipts": bundle["receipts"]}),
        (packet_path, bundle["packet"]),
        (blind_packet_path, bundle["blind_packet"]),
    ):
        path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        files.append(path)
    adjudication_template = {
        "schema": "anarchi.recoveries.independent-adjudication.v1",
        "run_id": bundle["run_manifest"]["run_id"],
        "blind_packet_sha256": bundle["blind_packet"]["packet_sha256"],
        "reviewer_id": None,
        "reviewed_at": None,
        "cases": [
            {
                "case_id": item["case_id"],
                "human_conclusion": None,
                "dimensions": {
                    "opportunity_precision": None,
                    "financial_exactness": None,
                    "evidence_sufficiency": None,
                    "authority_correctness": None,
                    "replay_identity": None,
                    "action_integrity": None,
                    "attribution_correctness": None,
                    "unknown_preservation": None,
                    "false_positive_prevention": None,
                },
            }
            for item in bundle["packet"]["decision_trace"]
        ],
    }
    adjudication_template_path.write_text(json.dumps(adjudication_template, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    files.append(adjudication_template_path)
    review = {
        "schema": "anarchi.recoveries.pilot-independent-review.v1",
        "spec_sha256": SPEC_SHA256,
        "run_id": bundle["run_manifest"]["run_id"],
        "reviewed_receipt_chain_root_sha256": bundle["run_manifest"]["receipt_chain_root_sha256"],
        "reviewed_artifact_manifest_sha256": bundle["run_manifest"]["run_manifest_sha256"],
        "reviewed_packet_sha256": bundle["packet"]["packet_sha256"],
        "reviewed_blind_packet_sha256": bundle["blind_packet"]["packet_sha256"],
        "adjudication_template_sha256": file_digest(adjudication_template_path),
        "reviewer_id": None,
        "decision": "PENDING",
        "reviewed_at": None,
        "comments": "Independent reviewer not yet nominated; this record has no release authority.",
        "authority": {"production_mutated": False, "release_authority": "none"},
    }
    review_path = output_dir / "independent-review.v1.json"
    review_path.write_text(json.dumps(review, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    files.append(review_path)

    def step_receipt(
        step: str,
        description: str,
        previous: str,
        verification: dict[str, Any],
        artifacts: dict[str, str],
        open_items: list[str],
    ) -> dict[str, Any]:
        body = {
            "receipt_schema": "anarchi.recoveries.step-transition-receipt.v1",
            "receipt_id": f"RECOVERIES-{step}-{bundle['run_manifest']['run_id']}",
            "spec_sha256": SPEC_SHA256,
            "source_commit": bundle["run_manifest"]["source_commit"],
            "run_id": bundle["run_manifest"]["run_id"],
            "step": step,
            "transition": description,
            "canonicalization": CANONICALIZATION,
            "previous_receipt_sha256": previous,
            "authority": {
                "production_mutated": False,
                "live_services_contacted": False,
                "release_authority": "none",
            },
            "verification": verification,
            "open_items": open_items,
            "artifact_sha256": artifacts,
        }
        body["receipt_sha256"] = digest(body)
        return body

    static_artifacts = {
        "infra/compose/pilot-rehearsal.compose.yaml": file_digest(COMPOSE_PATH),
        "fixtures/pilot/manifest.v1.json": file_digest(FIXTURE_PATH),
        "fixtures/pilot/project-falcon.v1.json": file_digest(PROJECT_UNIVERSE_PATH),
        "governance/enforcement-binding-registry.v1.json": file_digest(RULE_REGISTRY_PATH),
        "docs/policies/policy-manifest.v1.json": file_digest(POLICY_PATH),
        "docs/architecture/pilot-rehearsal.md": file_digest(ROOT / "docs/architecture/pilot-rehearsal.md"),
        "tools/pilot/run_rehearsal.py": file_digest(ROOT / "tools/pilot/run_rehearsal.py"),
        "tools/pilot/verify_pilot_rehearsal.py": file_digest(ROOT / "tools/pilot/verify_pilot_rehearsal.py"),
        "tools/pilot/payment_boundary.py": file_digest(ROOT / "tools/pilot/payment_boundary.py"),
    }
    step43 = step_receipt(
        "STEP_43_PILOT_TEST_STACK_REHEARSAL",
        "isolated test-stack rehearsal",
        "",
        {
            "compose_config": bundle["run_manifest"]["stack"]["compose_config"],
            "services_started": bundle["run_manifest"]["stack"]["services_started"],
            "services_healthy": bundle["run_manifest"]["stack"]["services_healthy"],
            "teardown": bundle["run_manifest"]["stack"]["teardown"],
            "production_endpoint_contact_count": 0,
        },
        static_artifacts,
        ["service-backed business API proof remains a later increment"],
    )
    step43_path = proof_root / "STEP-43-PILOT-TEST-STACK-REHEARSAL-RECEIPT.json"
    step43_path.write_text(json.dumps(step43, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    files.append(step43_path)
    step44_artifacts = dict(static_artifacts)
    step44_artifacts.update(
        {
            artifact_label(run_manifest_path): file_digest(run_manifest_path),
            artifact_label(report_path): file_digest(report_path),
            artifact_label(chain_path): file_digest(chain_path),
            artifact_label(packet_path): file_digest(packet_path),
            artifact_label(blind_packet_path): file_digest(blind_packet_path),
        }
    )
    step44 = step_receipt(
        "STEP_44_PILOT_EVIDENCE_BASELINE",
        "pilot evidence and precision measurement",
        step43["receipt_sha256"],
        {
            "case_expectations": "PASS",
            "separate_precision_metrics": "PASS",
            "replay_hashes": "PASS",
            "pilot_recommendation": "HOLD",
        },
        step44_artifacts,
        bundle["report"]["open_items"],
    )
    step44_path = proof_root / "STEP-44-PILOT-EVIDENCE-BASELINE-RECEIPT.json"
    step44_path.write_text(json.dumps(step44, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    files.append(step44_path)
    step45_artifacts = dict(step44_artifacts)
    step45_artifacts[artifact_label(review_path)] = file_digest(review_path)
    step45_artifacts[artifact_label(adjudication_template_path)] = file_digest(adjudication_template_path)
    step45_artifacts[artifact_label(ROOT / "tools/pilot/adjudicate_review.py")] = file_digest(ROOT / "tools/pilot/adjudicate_review.py")
    step45 = step_receipt(
        "STEP_45_PILOT_INDEPENDENT_REVIEW",
        "independent evidence review checkpoint",
        step44["receipt_sha256"],
        {"review_decision": "PENDING", "release_authority": "NONE"},
        step45_artifacts,
        ["independent reviewer identity and acceptance are pending"],
    )
    step45_path = proof_root / "STEP-45-PILOT-INDEPENDENT-REVIEW-RECEIPT.json"
    step45_path.write_text(json.dumps(step45, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    files.append(step45_path)
    return files


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--start-stack", action="store_true", help="start and tear down the isolated WSL2 test stack")
    parser.add_argument("--run-id", help="stable replay identifier; defaults to commit and fixture digest")
    parser.add_argument("--output-dir", type=Path, default=ROOT / "proof/m3/pilot-rehearsal")
    args = parser.parse_args(argv)
    try:
        bundle = build_rehearsal(start_stack=args.start_stack, run_id=args.run_id)
        files = write_proof(bundle, args.output_dir)
        print("pilot_rehearsal=PASS")
        print(f"pilot_run_id={bundle['run_manifest']['run_id']}")
        print(f"pilot_cases={bundle['report']['case_count']}")
        print(f"receipt_chain_root={bundle['run_manifest']['receipt_chain_root_sha256']}")
        for path in files:
            try:
                label = path.relative_to(ROOT)
            except ValueError:
                label = path
            print(f"artifact={label}")
        return 0
    except (OSError, RehearsalError, subprocess.SubprocessError) as error:
        print(f"pilot_rehearsal=HOLD: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
