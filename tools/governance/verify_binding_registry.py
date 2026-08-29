#!/usr/bin/env python3
"""Validate the machine-enforcement bridge without activating authority."""

from __future__ import annotations

import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
REGISTRY_PATH = ROOT / "governance/enforcement-binding-registry.v1.json"
SPEC_SHA256 = "0e3877aff0832db9cc0503d9a8769f2b867a1536441fba149874360fbb8f8869"
STATUSES = {"PUBLISHED", "STAGED", "SIMULATED", "APPROVED", "ACTIVE", "SUPERSEDED", "REVOKED"}
REGISTRY_STATUSES = {"NOT_READY", "READY"}


def required_text(binding: dict, name: str) -> str:
    value = binding.get(name)
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"binding {binding.get('binding_id', '<unknown>')} requires {name}")
    return value


def validate_binding(binding: object, root: Path = ROOT) -> None:
    if not isinstance(binding, dict):
        raise ValueError("binding must be an object")
    required = {
        "binding_id", "canonical_rule_id", "rule_version", "authority_class", "system",
        "component", "operation", "enforcement_point", "implementation_ref", "test_ref",
        "proof_fixture", "fail_mode", "status",
    }
    if set(binding) != required:
        raise ValueError(f"binding fields must be exactly {sorted(required)}")
    binding_id = required_text(binding, "binding_id")
    if not re.fullmatch(r"ENF-[A-Z0-9-]+", binding_id):
        raise ValueError(f"invalid binding_id: {binding_id}")
    rule_id = required_text(binding, "canonical_rule_id")
    if not re.fullmatch(r"RULE-[A-Z0-9-]+", rule_id):
        raise ValueError(f"invalid canonical_rule_id: {rule_id}")
    implementation_ref = required_text(binding, "implementation_ref")
    if not re.fullmatch(r"git:[0-9a-f]{7,64}", implementation_ref):
        raise ValueError(f"invalid implementation_ref: {implementation_ref}")
    if binding["fail_mode"] != "DENY":
        raise ValueError(f"binding {binding_id} must fail closed with DENY")
    status = binding["status"]
    if status not in STATUSES:
        raise ValueError(f"invalid binding status: {status}")
    for name in ("rule_version", "authority_class", "system", "component", "operation", "enforcement_point", "test_ref", "proof_fixture"):
        required_text(binding, name)
    if status == "ACTIVE":
        for name in ("test_ref", "proof_fixture"):
            path = root / binding[name]
            if not path.is_file():
                raise ValueError(f"active binding {binding_id} references missing {name}: {binding[name]}")


def validate_registry(registry: object, root: Path = ROOT) -> int:
    if not isinstance(registry, dict):
        raise ValueError("registry must be an object")
    if set(registry) != {"schema", "status", "source", "bindings"}:
        raise ValueError("registry fields are not exact")
    if registry["schema"] != "anarchi.recoveries.enforcement-binding-registry.v1":
        raise ValueError("unexpected registry schema")
    if registry["status"] not in REGISTRY_STATUSES:
        raise ValueError("registry status must be NOT_READY or READY")
    source = registry["source"]
    if source.get("sha256") != SPEC_SHA256:
        raise ValueError("registry source is not pinned to frozen spec")
    bindings = registry["bindings"]
    if not isinstance(bindings, list):
        raise ValueError("registry bindings must be a list")
    seen: set[str] = set()
    for binding in bindings:
        validate_binding(binding, root)
        binding_id = binding["binding_id"]
        if binding_id in seen:
            raise ValueError(f"duplicate binding_id: {binding_id}")
        seen.add(binding_id)
    if registry["status"] == "READY" and not any(
        binding["status"] == "ACTIVE" for binding in bindings
    ):
        raise ValueError("READY registry requires at least one ACTIVE binding")
    if registry["status"] == "READY" and not (
        root / "proof/m3/STEP-25-RELEASE-PROVENANCE.json"
    ).is_file():
        raise ValueError("READY registry requires release provenance")
    if registry["status"] == "NOT_READY" and any(
        binding["status"] == "ACTIVE" for binding in bindings
    ):
        raise ValueError("NOT_READY registry cannot contain an ACTIVE binding")
    return len(bindings)


def main() -> None:
    registry = json.loads(REGISTRY_PATH.read_text(encoding="utf-8"))
    count = validate_registry(registry)
    print(f"bindings={count} PASS")
    print(f"governance_readiness={registry['status']}")


if __name__ == "__main__":
    main()
