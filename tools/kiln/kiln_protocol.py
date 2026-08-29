#!/usr/bin/env python3
"""Pure specimen mutation/fracture/survivor/restoration protocol for Kiln."""

from __future__ import annotations

import copy
import hashlib
import json
from dataclasses import dataclass
from typing import Any


FORBIDDEN_KILN_ACTIONS = frozenset({"repair", "promote", "commit", "push", "publish", "deploy", "authorize"})


def canonical_bytes(value: Any) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")


def digest(value: Any) -> str:
    return hashlib.sha256(canonical_bytes(value)).hexdigest()


@dataclass(frozen=True)
class KilnSpecimen:
    specimen_id: str
    source: dict[str, Any]
    source_sha256: str


@dataclass(frozen=True)
class MutationResult:
    specimen_id: str
    mutation: str
    mutated: dict[str, Any]
    mutated_sha256: str
    source_sha256: str


@dataclass(frozen=True)
class ProofResult:
    name: str
    passed: bool
    details: tuple[str, ...]


def make_specimen(specimen_id: str, source: dict[str, Any]) -> KilnSpecimen:
    if not specimen_id.strip():
        raise ValueError("specimen_id is required")
    if not isinstance(source, dict) or not source:
        raise ValueError("specimen source must be a nonempty object")
    frozen_source = copy.deepcopy(source)
    return KilnSpecimen(specimen_id, frozen_source, digest(frozen_source))


def mutate(specimen: KilnSpecimen, path: tuple[str, ...], replacement: Any) -> MutationResult:
    if not path or any(not segment.strip() for segment in path):
        raise ValueError("mutation path is required")
    mutated = copy.deepcopy(specimen.source)
    cursor: Any = mutated
    for segment in path[:-1]:
        if not isinstance(cursor, dict) or segment not in cursor:
            raise ValueError("mutation path does not exist")
        cursor = cursor[segment]
    if not isinstance(cursor, dict) or path[-1] not in cursor:
        raise ValueError("mutation path does not exist")
    cursor[path[-1]] = copy.deepcopy(replacement)
    return MutationResult(
        specimen.specimen_id,
        ".".join(path),
        mutated,
        digest(mutated),
        specimen.source_sha256,
    )


def fracture_proof(result: MutationResult) -> ProofResult:
    passed = result.mutated_sha256 != result.source_sha256
    return ProofResult(
        "fracture",
        passed,
        ("mutation changes specimen digest" if passed else "mutation did not change specimen digest",),
    )


def survivor_proof(result: MutationResult, required_paths: tuple[tuple[str, ...], ...]) -> ProofResult:
    missing: list[str] = []
    for path in required_paths:
        cursor: Any = result.mutated
        for segment in path:
            if not isinstance(cursor, dict) or segment not in cursor:
                missing.append(".".join(path))
                break
            cursor = cursor[segment]
    return ProofResult("survivor", not missing, tuple(["required fields survived"] if not missing else missing))


def restoration_proof(specimen: KilnSpecimen, restored: dict[str, Any]) -> ProofResult:
    passed = digest(restored) == specimen.source_sha256
    return ProofResult(
        "restoration",
        passed,
        ("restored digest matches source" if passed else "restored digest differs from source",),
    )


def forbid_authority(action: str) -> None:
    if action.strip().lower() in FORBIDDEN_KILN_ACTIONS:
        raise PermissionError(f"Kiln cannot {action}")
