#!/usr/bin/env python3
"""Validate production migration prerequisites without contacting production."""

from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / "docs/runbooks/production-migration-readiness.v1.json"
SPEC_SHA256 = "0e3877aff0832db9cc0503d9a8769f2b867a1536441fba149874360fbb8f8869"
EXPECTED_WORKLOADS = [
    "ingress / reverse proxy",
    "API + web",
    "Go workers / connectors",
    "Rust evaluation services",
    "PostgreSQL primary",
    "PostgreSQL replica / backup target",
    "S3 evidence storage",
    "NATS / coordination",
    "Vault / security services",
    "observability + backup / spare capacity",
]


def validate(manifest: object) -> None:
    if not isinstance(manifest, dict):
        raise ValueError("production readiness manifest must be an object")
    if manifest.get("schema") != "anarchi.recoveries.production-migration-readiness.v1":
        raise ValueError("unexpected production readiness schema")
    if manifest.get("spec_sha256") != SPEC_SHA256:
        raise ValueError("production readiness manifest is not pinned to the frozen spec")
    if manifest.get("status") not in {"NOT_AUTHORIZED", "AUTHORIZED"}:
        raise ValueError("production readiness status is invalid")
    if manifest.get("production_mutated") is not False:
        raise ValueError("readiness manifest cannot claim production mutation")
    slots = manifest.get("dedicated_stack_slots")
    if not isinstance(slots, list) or [item.get("slot") for item in slots] != list(range(1, 11)):
        raise ValueError("dedicated stack slots must be numbered 1 through 10")
    if [item.get("workload") for item in slots] != EXPECTED_WORKLOADS:
        raise ValueError("dedicated stack workload map drifted from the frozen spec")
    objectives = manifest.get("objectives")
    if objectives != {
        "postgresql_rpo_minutes_max": 15,
        "core_recoveries_rto_hours_max": 4,
        "independent_full_backup": "nightly",
        "continuous_incremental_db_protection": True,
        "off_stack_encrypted_backup_minimum": 1,
        "backup_restoration_testing": "scheduled_and_recorded",
    }:
        raise ValueError("backup and recovery objectives drifted from the frozen spec")
    preflight = manifest.get("preflight")
    required = {
        "authority_approved",
        "rollback_plan_approved",
        "backup_restore_proof",
        "secret_broker_vault_ready",
        "observability_ready",
        "dedicated_stack_reachable",
    }
    if not isinstance(preflight, dict) or set(preflight) != required or any(not isinstance(value, bool) for value in preflight.values()):
        raise ValueError("production preflight set is incomplete")
    if manifest["status"] == "AUTHORIZED" and not all(preflight.values()):
        raise ValueError("production authorization requires every preflight check")


def main() -> None:
    validate(json.loads(MANIFEST.read_text(encoding="utf-8")))
    print("production_readiness=PASS")
    print("production_authorized=FALSE")


if __name__ == "__main__":
    main()
